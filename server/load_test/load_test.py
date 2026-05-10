# load_test.py
import asyncio
import argparse
import json
import statistics
import time
import uuid
from contextlib import asynccontextmanager

import websockets

DEFAULT_URL = "ws://localhost:8000/ws"


@asynccontextmanager
async def phone_client(base_url: str, player_id: str, username: str):
    """Connect, send identify, await ack. Yields the websocket."""
    uri = f"{base_url}/phone/{player_id}"
    async with websockets.connect(uri, max_size=2**20, ping_interval=None) as ws:
        await ws.send(json.dumps({"type": "identify", "username": username}))
        # Drain ack + initial player_list broadcast
        ack = await ws.recv()
        yield ws


# ---------------------------------------------------------------------------
# Test 1: connection scaling — how many phones can connect simultaneously?
# ---------------------------------------------------------------------------
async def test_connections(base_url: str, target: int, ramp_rate: int, hold_seconds: int):
    """
    Ramps up `target` phone connections at `ramp_rate` per second,
    holds them open for `hold_seconds`, then disconnects.
    Reports success / failure / time-to-ack.
    """
    results = {"connected": 0, "failed": 0, "ack_latencies_ms": []}
    stop = asyncio.Event()

    async def one_client(i):
        pid = f"loadtest-{i}-{uuid.uuid4().hex[:6]}"
        try:
            t0 = time.perf_counter()
            uri = f"{base_url}/phone/{pid}"
            async with websockets.connect(uri, ping_interval=None) as ws:
                await ws.send(json.dumps({"type": "identify", "username": pid}))
                await ws.recv()  # ack
                results["ack_latencies_ms"].append((time.perf_counter() - t0) * 1000)
                results["connected"] += 1
                # Drain incoming broadcasts to avoid backpressure
                async def drain():
                    try:
                        async for _ in ws:
                            pass
                    except Exception:
                        pass
                drain_task = asyncio.create_task(drain())
                await stop.wait()
                drain_task.cancel()
        except Exception as e:
            results["failed"] += 1
            if results["failed"] <= 5:
                print(f"  connect failure ({pid}): {type(e).__name__}: {e}")

    print(f"Ramping up {target} connections at {ramp_rate}/s...")
    tasks = []
    start = time.perf_counter()
    for i in range(target):
        tasks.append(asyncio.create_task(one_client(i)))
        if (i + 1) % ramp_rate == 0:
            await asyncio.sleep(1)

    # Wait until everyone has either connected or failed
    for _ in range(60):
        if results["connected"] + results["failed"] >= target:
            break
        await asyncio.sleep(0.5)

    ramp_time = time.perf_counter() - start
    print(f"Ramp complete in {ramp_time:.1f}s | "
          f"connected={results['connected']} failed={results['failed']}")

    if results["ack_latencies_ms"]:
        lat = results["ack_latencies_ms"]
        print(f"Connect+ack latency ms: "
              f"p50={statistics.median(lat):.1f} "
              f"p95={statistics.quantiles(lat, n=20)[18]:.1f} "
              f"max={max(lat):.1f}")

    print(f"Holding for {hold_seconds}s...")
    await asyncio.sleep(hold_seconds)
    stop.set()
    await asyncio.gather(*tasks, return_exceptions=True)


# ---------------------------------------------------------------------------
# Test 2: message throughput + latency (requires `ping`/`pong` handler)
# ---------------------------------------------------------------------------
async def test_messages(base_url: str, n_clients: int, msgs_per_client: int, rate_per_client: float):
    """
    Connects n_clients phones, then each sends `msgs_per_client` ping messages
    at `rate_per_client` msgs/sec. Measures round-trip latency.
    """
    latencies_ms = []
    errors = 0
    barrier = asyncio.Event()

    async def one_client(i):
        nonlocal errors
        pid = f"msgtest-{i}-{uuid.uuid4().hex[:6]}"
        try:
            async with phone_client(base_url, pid, pid) as ws:
                await barrier.wait()  # all clients start sending together
                interval = 1.0 / rate_per_client if rate_per_client > 0 else 0
                for _ in range(msgs_per_client):
                    t0 = time.perf_counter()
                    await ws.send(json.dumps({"type": "ping", "ts": t0}))
                    # Wait for *our* pong (skip any broadcasts)
                    while True:
                        raw = await ws.recv()
                        msg = json.loads(raw)
                        if msg.get("type") == "pong":
                            latencies_ms.append((time.perf_counter() - t0) * 1000)
                            break
                    if interval:
                        await asyncio.sleep(interval)
        except Exception as e:
            errors += 1
            if errors <= 3:
                print(f"  client {pid} error: {e}")

    print(f"Connecting {n_clients} clients...")
    tasks = [asyncio.create_task(one_client(i)) for i in range(n_clients)]
    await asyncio.sleep(min(5 + n_clients * 0.01, 30))  # allow connect
    print(f"Starting message phase: {msgs_per_client} msgs/client @ {rate_per_client}/s")

    t_start = time.perf_counter()
    barrier.set()
    await asyncio.gather(*tasks, return_exceptions=True)
    elapsed = time.perf_counter() - t_start

    total = len(latencies_ms)
    print(f"\n=== Message test results ===")
    print(f"Clients: {n_clients} | Errors: {errors}")
    print(f"Round-trips completed: {total}")
    print(f"Wall time: {elapsed:.2f}s | Throughput: {total/elapsed:.1f} msg/s")
    if latencies_ms:
        latencies_ms.sort()
        q = statistics.quantiles(latencies_ms, n=100) if len(latencies_ms) >= 100 else None
        print(f"Latency ms: "
              f"min={latencies_ms[0]:.2f} "
              f"p50={statistics.median(latencies_ms):.2f} "
              f"p95={(q[94] if q else max(latencies_ms)):.2f} "
              f"p99={(q[98] if q else max(latencies_ms)):.2f} "
              f"max={latencies_ms[-1]:.2f}")

# ---------------------------------------------------------------------------
# Test 3: latency scaling sweep — runs test_messages at increasing load
# ---------------------------------------------------------------------------
async def test_scaling(base_url: str):
    """
    Runs the message test at increasing client counts and prints a summary
    table so you can see how latency degrades with load.
    """
    sweeps = [
        # (clients, msgs_per_client, rate_per_client_per_sec)
        (10,   50, 10),
        (50,   50, 10),
        (100,  50, 10),
        (250,  50, 10),
        (500,  20, 10),
        (1000, 20, 5),
        (2000, 10, 5),
    ]

    summary = []
    for n_clients, msgs, rate in sweeps:
        print(f"\n{'='*60}")
        print(f"SWEEP: {n_clients} clients, {msgs} msgs each @ {rate}/s")
        print(f"{'='*60}")

        latencies_ms = []
        errors = 0
        barrier = asyncio.Event()

        async def one_client(i):
            nonlocal errors
            pid = f"sweep-{n_clients}-{i}-{uuid.uuid4().hex[:6]}"
            try:
                async with phone_client(base_url, pid, pid) as ws:
                    await barrier.wait()
                    interval = 1.0 / rate if rate > 0 else 0
                    for _ in range(msgs):
                        t0 = time.perf_counter()
                        await ws.send(json.dumps({"type": "ping", "ts": t0}))
                        while True:
                            raw = await asyncio.wait_for(ws.recv(), timeout=10)
                            msg = json.loads(raw)
                            if msg.get("type") == "pong":
                                latencies_ms.append((time.perf_counter() - t0) * 1000)
                                break
                        if interval:
                            await asyncio.sleep(interval)
            except Exception as e:
                errors += 1

        tasks = [asyncio.create_task(one_client(i)) for i in range(n_clients)]
        # Allow connections to settle (scale wait with client count)
        await asyncio.sleep(min(3 + n_clients * 0.01, 30))

        t_start = time.perf_counter()
        barrier.set()
        await asyncio.gather(*tasks, return_exceptions=True)
        elapsed = time.perf_counter() - t_start

        if latencies_ms:
            latencies_ms.sort()
            p50 = statistics.median(latencies_ms)
            p95 = latencies_ms[int(len(latencies_ms) * 0.95)]
            p99 = latencies_ms[int(len(latencies_ms) * 0.99)]
            throughput = len(latencies_ms) / elapsed
            summary.append({
                "clients": n_clients,
                "completed": len(latencies_ms),
                "errors": errors,
                "throughput": throughput,
                "p50": p50, "p95": p95, "p99": p99,
                "max": latencies_ms[-1],
            })
            print(f"  done: {len(latencies_ms)} round-trips, {errors} errors, "
                  f"{throughput:.1f} msg/s")
            print(f"  latency ms: p50={p50:.2f} p95={p95:.2f} "
                  f"p99={p99:.2f} max={latencies_ms[-1]:.2f}")
        else:
            print(f"  ALL FAILED ({errors} errors) — stopping sweep")
            break

        # Cooldown between sweeps so the server can release sockets
        await asyncio.sleep(3)

    # Final summary table
    print(f"\n\n{'='*78}")
    print("SCALING SUMMARY")
    print(f"{'='*78}")
    print(f"{'clients':>8} {'done':>8} {'errors':>7} {'msg/s':>9} "
          f"{'p50 ms':>9} {'p95 ms':>9} {'p99 ms':>9} {'max ms':>9}")
    print("-" * 78)
    for r in summary:
        print(f"{r['clients']:>8} {r['completed']:>8} {r['errors']:>7} "
              f"{r['throughput']:>9.1f} {r['p50']:>9.2f} {r['p95']:>9.2f} "
              f"{r['p99']:>9.2f} {r['max']:>9.2f}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def main():
    parser = argparse.ArgumentParser(description="WebSocket load test")
    parser.add_argument("--url", default=DEFAULT_URL,
                        help="Base WS URL (default: ws://localhost:8000/ws)")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p1 = sub.add_parser("connections", help="Test max simultaneous connections")
    p1.add_argument("--target", type=int, default=500)
    p1.add_argument("--ramp-rate", type=int, default=50,
                    help="Connections per second during ramp-up")
    p1.add_argument("--hold", type=int, default=10,
                    help="Seconds to hold connections open after ramp")

    p2 = sub.add_parser("messages", help="Test message throughput + latency")
    p2.add_argument("--clients", type=int, default=50)
    p2.add_argument("--msgs", type=int, default=100)
    p2.add_argument("--rate", type=float, default=10,
                    help="Messages per second per client")

    sub.add_parser("scaling", help="Run a sweep showing latency vs load")

    args = parser.parse_args()

    if args.cmd == "connections":
        asyncio.run(test_connections(args.url, args.target, args.ramp_rate, args.hold))
    elif args.cmd == "messages":
        asyncio.run(test_messages(args.url, args.clients, args.msgs, args.rate))
    elif args.cmd == "scaling":
        asyncio.run(test_scaling(args.url))


if __name__ == "__main__":
    main()