//
//  UWBManager.swift
//  GameApp
//
//  Created by Belle See on 4/28/26.
//


import NearbyInteraction
import MultipeerConnectivity
import Combine

class UWBManager: NSObject, ObservableObject {
    // Published state
    @Published var nearbyPlayers: [String: Float] = [:]  // clientId → distance in meters
    @Published var hasNearbyPlayer = false  // true if any player within 5m
    
    // Nearby Interaction
    private var niSession: NISession?
    private var myToken: NIDiscoveryToken?
    
    // Multipeer for token exchange
    private let serviceType = "puckscanned"
    private var myPeerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    // Map peer → NI session
    private var peerSessions: [MCPeerID: NISession] = [:]
    private var peerTokens: [MCPeerID: NIDiscoveryToken] = [:]
    
    var clientId: String = ""
    var isImposter = false

    override init() {
        super.init()
    }
    
    func start(clientId: String) {
        self.clientId = clientId
        myPeerID = MCPeerID(displayName: clientId)
        
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
    
    func stop() {
        advertiser?.stopAdvertisingPeer()
        browser?.stopBrowsingForPeers()
        session?.disconnect()
        peerSessions.values.forEach { $0.invalidate() }
        peerSessions.removeAll()
        nearbyPlayers.removeAll()
        hasNearbyPlayer = false
    }
    
    private func startNISession(with peer: MCPeerID) {
        let niSession = NISession()
        niSession.delegate = self
        peerSessions[peer] = niSession
        
        guard let token = niSession.discoveryToken else { return }
        myToken = token
        
        // Send our token to the peer
        if let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            try? session.send(data, toPeers: [peer], with: .reliable)
        }
    }
    
    private func updateNearbyStatus() {
        hasNearbyPlayer = nearbyPlayers.values.contains { $0 <= 5.0 }
    }
}

// MARK: - MCSession Delegate
extension UWBManager: MCSessionDelegate {
    func session(_ session: MCSession, peer: MCPeerID, didChange state: MCSessionState) {
        if state == .connected {
            if isImposter {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.startNISession(with: peer)
                }
            }
        } else if state == .notConnected {
            peerSessions[peer]?.invalidate()
            peerSessions.removeValue(forKey: peer)
            DispatchQueue.main.async {
                self.nearbyPlayers.removeValue(forKey: peer.displayName)
                self.updateNearbyStatus()
            }
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peer: MCPeerID) {
        // Received peer's NI token — start ranging
        guard let token = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NIDiscoveryToken.self, from: data),
              let niSession = peerSessions[peer] else { return }
        
        peerTokens[peer] = token
        let config = NINearbyPeerConfiguration(peerToken: token)
        niSession.run(config)
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName: String, fromPeer: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiser Delegate
extension UWBManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peer: MCPeerID, withContext: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowser Delegate
extension UWBManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peer: MCPeerID, withDiscoveryInfo: [String: String]?) {
        browser.invitePeer(peer, to: session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peer: MCPeerID) {
        DispatchQueue.main.async {
            self.nearbyPlayers.removeValue(forKey: peer.displayName)
            self.updateNearbyStatus()
        }
    }
}

// MARK: - NISession Delegate
extension UWBManager: NISessionDelegate {
    func session(_ session: NISession, didUpdate nearbyObjects: [NINearbyObject]) {
        guard let peer = peerSessions.first(where: { $0.value === session })?.key,
              let distance = nearbyObjects.first?.distance else { return }
        
        DispatchQueue.main.async {
            self.nearbyPlayers[peer.displayName] = distance
            self.updateNearbyStatus()
            print("📡 \(peer.displayName) is \(distance)m away")
        }
    }
    
    func session(_ session: NISession, didRemove nearbyObjects: [NINearbyObject], reason: NINearbyObject.RemovalReason) {
        guard let peer = peerSessions.first(where: { $0.value === session })?.key else { return }
        DispatchQueue.main.async {
            self.nearbyPlayers.removeValue(forKey: peer.displayName)
            self.updateNearbyStatus()
        }
    }
    
    func sessionWasSuspended(_ session: NISession) {}
    func sessionSuspensionEnded(_ session: NISession) {}
}
