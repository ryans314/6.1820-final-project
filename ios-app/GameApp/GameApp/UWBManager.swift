//
//  UWBManager.swift
//  GameApp
//
//  Created by Belle See on 4/28/26.
//

import NearbyInteraction
import MultipeerConnectivity
import Combine

// Prefix all UWB logs with [UWB] for easy filtering in Xcode console
private func uwbLog(_ msg: String) {
    print("[UWB] \(msg)")
}

class UWBManager: NSObject, ObservableObject {
    // Published state (only imposter reads this)
    @Published var nearbyPlayers: [String: Float] = [:]
    @Published var hasNearbyPlayer = false

    // Multipeer
    private let serviceType = "puck-game"
    private var myPeerID: MCPeerID!
    private var mcSession: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    // One NISession per connected peer
    // Use a concurrent queue with .barrier for writes — eliminates deadlock risk
    // that existed when queue.sync writes were nested inside DispatchQueue.main.asyncAfter callbacks.
    private var peerSessions: [MCPeerID: NISession] = [:]
    private let queue = DispatchQueue(label: "uwb.manager", attributes: .concurrent)

    var clientId: String = ""
    var isImposter = false

    override init() { super.init() }

    func start(clientId: String) {
        self.clientId = clientId
        myPeerID = MCPeerID(displayName: clientId)

        uwbLog("▶️ Starting — clientId=\(clientId) role=\(isImposter ? "IMPOSTER" : "crewmate")")

        mcSession = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        mcSession.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        uwbLog("📢 Advertising as \(clientId) on service '\(serviceType)'")

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
        uwbLog("🔍 Browsing for peers on service '\(serviceType)'")
    }

    func stop() {
        uwbLog("⏹️ Stopping UWBManager — disconnecting all sessions")
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        mcSession?.disconnect()

        queue.async(flags: .barrier) {
            uwbLog("🗑️ Invalidating \(self.peerSessions.count) NISession(s)")
            self.peerSessions.values.forEach { $0.invalidate() }
            self.peerSessions.removeAll()
        }
        DispatchQueue.main.async {
            self.nearbyPlayers.removeAll()
            self.hasNearbyPlayer = false
            uwbLog("🧹 Cleared nearbyPlayers")
        }
    }

    // NISession must be initialised on the main thread to reliably produce
    // a discoveryToken. We're already called from main via asyncAfter — keep it that way.
    private func startNISession(with peer: MCPeerID) {
        uwbLog("🛰️ Starting NISession for peer: \(peer.displayName)")
        let niSession = NISession()
        niSession.delegate = self

        queue.async(flags: .barrier) {
            self.peerSessions[peer] = niSession
            uwbLog("💾 Stored NISession for \(peer.displayName) — total sessions: \(self.peerSessions.count)")
        }

        if niSession.discoveryToken != nil {
            uwbLog("🪙 Token ready immediately for \(peer.displayName), sending now")
        } else {
            uwbLog("⏳ Token not ready yet for \(peer.displayName), starting retry loop (max 5 attempts)")
        }
        sendToken(niSession.discoveryToken, to: peer, retries: 5)
    }

    // Retry loop — discoveryToken can be nil immediately after NISession init
    private func sendToken(_ token: NIDiscoveryToken?, to peer: MCPeerID, retries: Int) {
        if let token = token {
            guard let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
                uwbLog("❌ Failed to archive discovery token for \(peer.displayName)")
                return
            }
            do {
                try mcSession.send(data, toPeers: [peer], with: .reliable)
                uwbLog("📤 Sent discovery token to \(peer.displayName) (\(data.count) bytes)")
            } catch {
                uwbLog("❌ Failed to send token to \(peer.displayName): \(error.localizedDescription)")
            }
        } else if retries > 0 {
            uwbLog("🔄 Token nil for \(peer.displayName), retrying in 0.2s (\(retries) retries left)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                guard let self = self else { return }
                var session: NISession?
                self.queue.sync { session = self.peerSessions[peer] }
                self.sendToken(session?.discoveryToken, to: peer, retries: retries - 1)
            }
        } else {
            uwbLog("❌ Gave up sending token to \(peer.displayName) — token never became available")
        }
    }

    private func updateNearbyStatus() {
        let wasNearby = hasNearbyPlayer
        hasNearbyPlayer = nearbyPlayers.values.contains { $0 <= 5.0 }
        if hasNearbyPlayer != wasNearby {
            uwbLog("🚨 hasNearbyPlayer changed → \(hasNearbyPlayer)")
        }
    }

    private func removePeer(_ peer: MCPeerID) {
        uwbLog("🔌 Removing peer: \(peer.displayName)")
        queue.async(flags: .barrier) {
            self.peerSessions[peer]?.invalidate()
            self.peerSessions.removeValue(forKey: peer)
            uwbLog("🗑️ Removed NISession for \(peer.displayName) — remaining sessions: \(self.peerSessions.count)")
        }
        DispatchQueue.main.async {
            self.nearbyPlayers.removeValue(forKey: peer.displayName)
            self.updateNearbyStatus()
        }
    }
}

// MARK: - MCSession Delegate
extension UWBManager: MCSessionDelegate {
    func session(_ session: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
        let stateLabel: String
        switch state {
        case .connected:    stateLabel = "✅ connected"
        case .connecting:   stateLabel = "🔄 connecting"
        case .notConnected: stateLabel = "❌ not connected"
        @unknown default:   stateLabel = "❓ unknown"
        }
        uwbLog("🔗 MCSession peer \(peer.displayName) → \(stateLabel)")

        if state == .connected {
            uwbLog("⏳ Waiting 0.3s before starting NISession with \(peer.displayName)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.startNISession(with: peer)
            }
        } else if state == .notConnected {
            removePeer(peer)
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peer: MCPeerID) {
        uwbLog("📥 Received \(data.count) bytes from \(peer.displayName)")

        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data) else {
            uwbLog("❌ Failed to unarchive NIDiscoveryToken from \(peer.displayName) — data may be malformed")
            return
        }
        uwbLog("🪙 Successfully decoded discovery token from \(peer.displayName)")

        var niSession: NISession?
        queue.sync { niSession = peerSessions[peer] }
        guard let niSession = niSession else {
            uwbLog("❌ No NISession found for \(peer.displayName) — token received too early?")
            return
        }

        // BOTH sides must call niSession.run(config) with the peer's token.
        // UWB ranging is symmetric — the crewmate's hardware must actively participate
        // for the imposter to receive distance data. Without this, the imposter's
        // NISession never fires didUpdate because the remote peer isn't ranging back.
        //
        // The imposter-only gate lives in NISessionDelegate (guard isImposter else { return })
        // so crewmates range silently and never act on distance updates.
        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession.run(config)
        uwbLog("▶️ NISession.run(config) called for peer \(peer.displayName) [role=\(isImposter ? "IMPOSTER" : "crewmate")]")
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiser Delegate
extension UWBManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peer: MCPeerID,
                    withContext: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        uwbLog("📨 Received invitation from \(peer.displayName) — accepting")
        invitationHandler(true, mcSession)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        uwbLog("❌ Advertiser failed to start: \(error.localizedDescription)")
    }
}

// MARK: - MCNearbyServiceBrowser Delegate
extension UWBManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peer: MCPeerID, withDiscoveryInfo: [String: String]?) {
        let willInvite = myPeerID.displayName > peer.displayName
        uwbLog("👀 Found peer: \(peer.displayName) — \(willInvite ? "inviting (we are lexicographically greater)" : "waiting for their invite")")
        if willInvite {
            browser.invitePeer(peer, to: mcSession, withContext: nil, timeout: 10)
        }
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peer: MCPeerID) {
        uwbLog("👋 Lost peer from browser: \(peer.displayName)")
        removePeer(peer)
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        uwbLog("❌ Browser failed to start: \(error.localizedDescription)")
    }
}

// MARK: - NISession Delegate
extension UWBManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        // Crewmates run the config (required for UWB to work) but never act on distance data.
        guard isImposter else { return }

        var peer: MCPeerID?
        queue.sync { peer = peerSessions.first { $0.value === session }?.key }
        guard let peer = peer else {
            uwbLog("⚠️ didUpdate fired but couldn't match NISession to a peer")
            return
        }

        guard let distance = nearbyObjects.first?.distance else {
            uwbLog("⚠️ didUpdate for \(peer.displayName) — distance unavailable (direction only?)")
            return
        }

        DispatchQueue.main.async {
            self.nearbyPlayers[peer.displayName] = distance
            self.updateNearbyStatus()
            uwbLog("📡 \(peer.displayName) is \(String(format: "%.2f", distance))m away | nearby=\(self.hasNearbyPlayer)")
        }
    }

    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        var peer: MCPeerID?
        queue.sync { peer = peerSessions.first { $0.value === session }?.key }
        guard let peer = peer else { return }

        let reasonLabel: String
        switch reason {
        case .peerEnded:    reasonLabel = "peer ended session"
        case .timeout:      reasonLabel = "timeout"
        @unknown default:   reasonLabel = "unknown"
        }
        uwbLog("🚫 NISession removed \(peer.displayName) — reason: \(reasonLabel)")

        DispatchQueue.main.async {
            self.nearbyPlayers.removeValue(forKey: peer.displayName)
            self.updateNearbyStatus()
        }
    }

    func sessionWasSuspended(_ session: NISession) {
        var peer: MCPeerID?
        queue.sync { peer = peerSessions.first { $0.value === session }?.key }
        uwbLog("😴 NISession suspended for peer: \(peer?.displayName ?? "unknown")")
    }

    func sessionSuspensionEnded(_ session: NISession) {
        // Re-exchange tokens so ranging can resume.
        // Both sides need to re-run config after suspension, but only the imposter
        // needs to re-send — crewmates will re-run their config when they receive
        // the imposter's fresh token.
        guard isImposter else { return }

        var peer: MCPeerID?
        queue.sync { peer = peerSessions.first { $0.value === session }?.key }
        guard let peer = peer else {
            uwbLog("⚠️ sessionSuspensionEnded — couldn't match NISession to a peer")
            return
        }
        uwbLog("⏰ NISession suspension ended for \(peer.displayName) — re-sending token")
        sendToken(session.discoveryToken, to: peer, retries: 5)
    }

    func session(_ session: NISession, didInvalidateWith error: Error) {
        var peer: MCPeerID?
        queue.sync { peer = peerSessions.first { $0.value === session }?.key }
        uwbLog("❌ NISession invalidated for \(peer?.displayName ?? "unknown"): \(error.localizedDescription)")
    }
}
