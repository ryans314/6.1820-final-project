# load_test.py
import asyncio
import argparse
import csv
import json
import statistics
import time
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

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
async def test_connections(base_url: str, target: int, ramp_rate: int,
                           hold_seconds: int, output_dir: str = "."):
    results_rows = []
    stop = asyncio.Event()

    async def one_client(i):
        pid = f"loadtest-{i}-{uuid.uuid4().hex[:6]}"
        t_start = time.perf_counter()
        try:
            uri = f"{base_url}/phone/{pid}"
            async with websockets.connect(uri, ping_interval=None,
                                          open_timeout=10) as ws:
                await ws.send(json.dumps({"type": "identify", "username": pid}))
                await ws.recv()
                t_ack = time.perf_counter()
                results_rows.append({
                    "index": i, "ramp_rate": ramp_rate,
                    "t_start": t_start, "t_ack": t_ack,
                    "latency_ms": (t_ack - t_start) * 1000,
                    "success": True, "error": "",
                })
                # Drain incoming broadcasts while holding the connection
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
            results_rows.append({
                "index": i, "ramp_rate": ramp_rate,
                "t_start": t_start, "t_ack": None,
                "latency_ms": None,
                "success": False, "error": f"{type(e).__name__}: {e}",
            })

    print(f"\n=== Ramp rate {ramp_rate}/s, target {target} ===")
    print(f"Ramping up {target} connections at {ramp_rate}/s...")
    tasks = []
    start = time.perf_counter()
    for i in range(target):
        tasks.append(asyncio.create_task(one_client(i)))
        if (i + 1) % ramp_rate == 0:
            await asyncio.sleep(1)

    # Wait for ramp to finish: every client should have either acked or errored
    # Give it up to (target/ramp_rate) + 30 seconds extra for slow ones
    deadline = time.perf_counter() + (target / ramp_rate) + 30
    while time.perf_counter() < deadline:
        if len(results_rows) >= target:
            break
        await asyncio.sleep(0.5)

    successes = sum(1 for r in results_rows if r["success"])
    failures = len(results_rows) - successes
    ramp_time = time.perf_counter() - start
    print(f"Ramp complete in {ramp_time:.1f}s | "
          f"connected={successes} failed={failures}")

    print(f"Holding for {hold_seconds}s...")
    await asyncio.sleep(hold_seconds)
    stop.set()
    await asyncio.gather(*tasks, return_exceptions=True)

    # Write CSV
    output_path = Path(output_dir) / f"results_rate{ramp_rate}.csv"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=results_rows[0].keys())
        writer.writeheader()
        writer.writerows(results_rows)
    print(f"Saved {output_path}")

    return {"rate": ramp_rate, "target": target,
            "successes": successes, "failures": failures}
# ---------------------------------------------------------------------------
# Test 2: message throughput + latency (requires `ping`/`pong` handler)
# ---------------------------------------------------------------------------
async def test_messages(base_url: str, n_clients: int, msgs_per_client: int,
                        rate_per_client: float, output_dir: str = "."):
    """
    Connects n_clients phones, each sends msgs_per_client pings at
    rate_per_client msgs/sec. Records per-message latency to CSV.
    """
    results_rows = []
    errors = 0
    barrier = asyncio.Event()

    async def one_client(i):
        nonlocal errors
        pid = f"msgtest-{i}-{uuid.uuid4().hex[:6]}"
        try:
            async with phone_client(base_url, pid, pid) as ws:
                await barrier.wait()
                interval = 1.0 / rate_per_client if rate_per_client > 0 else 0
                for msg_i in range(msgs_per_client):
                    t0 = time.perf_counter()
                    try:
                        await ws.send(json.dumps({"type": "ping", "ts": t0}))
                        # Skip any broadcast messages, wait for our pong
                        while True:
                            raw = await asyncio.wait_for(ws.recv(), timeout=10)
                            parsed = json.loads(raw)
                            if parsed.get("type") == "pong":
                                results_rows.append({
                                    "client_index": i,
                                    "message_index": msg_i,
                                    "n_clients": n_clients,
                                    "msgs_per_client": msgs_per_client,
                                    "rate_per_client": rate_per_client,
                                    "latency_ms": (time.perf_counter() - t0) * 1000,
                                    "success": True,
                                    "error": "",
                                })
                                break
                        if interval:
                            await asyncio.sleep(interval)
                    except Exception as e:
                        results_rows.append({
                            "client_index": i,
                            "message_index": msg_i,
                            "n_clients": n_clients,
                            "msgs_per_client": msgs_per_client,
                            "rate_per_client": rate_per_client,
                            "latency_ms": None,
                            "success": False,
                            "error": f"{type(e).__name__}: {e}",
                        })
                        errors += 1
        except Exception as e:
            # Connection-level failure — all messages for this client are lost
            errors += msgs_per_client
            if errors <= msgs_per_client * 3:
                print(f"  client {pid} failed to connect: {e}")

    print(f"\n=== Messages: {n_clients} clients, "
          f"{msgs_per_client} msgs @ {rate_per_client}/s ===")
    print(f"Connecting {n_clients} clients...")
    tasks = [asyncio.create_task(one_client(i)) for i in range(n_clients)]
    # Allow all connections to establish before starting message phase
    await asyncio.sleep(min(5 + n_clients * 0.01, 30))

    print("Starting message phase...")
    t_start = time.perf_counter()
    barrier.set()
    await asyncio.gather(*tasks, return_exceptions=True)
    elapsed = time.perf_counter() - t_start

    # Compute stats from successful rows only
    latencies = sorted(
        r["latency_ms"] for r in results_rows if r["success"]
    )
    total = len(latencies)
    throughput = total / elapsed if elapsed > 0 else 0

    print(f"Completed: {total} | Errors: {errors} | "
          f"Throughput: {throughput:.1f} msg/s")

    if latencies:
        q = statistics.quantiles(latencies, n=100) if len(latencies) >= 100 else None
        p50 = statistics.median(latencies)
        p95 = q[94] if q else max(latencies)
        p99 = q[98] if q else max(latencies)
        print(f"Latency ms: min={latencies[0]:.2f} p50={p50:.2f} "
              f"p95={p95:.2f} p99={p99:.2f} max={latencies[-1]:.2f}")
    else:
        p50 = p95 = p99 = None
        print("  No successful messages recorded.")

    # Write CSV
    if results_rows:
        output_path = Path(output_dir) / f"results_messages_clients{n_clients}.csv"
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=results_rows[0].keys())
            writer.writeheader()
            writer.writerows(results_rows)
        print(f"Saved {output_path}")

    return {
        "n_clients": n_clients,
        "total": total,
        "errors": errors,
        "throughput": throughput,
        "p50": p50, "p95": p95, "p99": p99,
    }


async def sweep_messages(base_url: str, client_counts: list[int],
                         msgs_per_client: int, rate_per_client: float,
                         cooldown: int, output_dir: str):
    """
    Run test_messages at each client count in client_counts.
    msgs_per_client and rate_per_client are held fixed across runs.
    """
    summary = []
    for i, n_clients in enumerate(client_counts):
        if i > 0:
            print(f"\nCooling down for {cooldown}s...")
            await asyncio.sleep(cooldown)

        result = await test_messages(
            base_url=base_url,
            n_clients=n_clients,
            msgs_per_client=msgs_per_client,
            rate_per_client=rate_per_client,
            output_dir=output_dir,
        )
        summary.append(result)

    # Print final summary table
    print(f"\n\n{'='*78}")
    print(f"{'MESSAGE SWEEP SUMMARY':^78}")
    print(f"{'='*78}")
    print(f"{'clients':>8} {'completed':>10} {'errors':>7} {'msg/s':>9} "
          f"{'p50 ms':>9} {'p95 ms':>9} {'p99 ms':>9}")
    print("-" * 78)
    for r in summary:
        def fmt(v):
            return f"{v:9.2f}" if v is not None else f"{'N/A':>9}"
        print(f"{r['n_clients']:>8} {r['total']:>10} {r['errors']:>7} "
              f"{r['throughput']:>9.1f} {fmt(r['p50'])} "
              f"{fmt(r['p95'])} {fmt(r['p99'])}")
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

async def run_sweep(base_url: str, target: int, hold_seconds: int,
                    rates: list[int], cooldown: int, output_dir: str):
    """
    Run test_connections at each ramp rate in `rates`, with `cooldown`
    seconds between runs to let the server fully clean up.
    """
    summary = []
    for i, rate in enumerate(rates):
        if i > 0:
            print(f"\nCooling down for {cooldown}s before next run...")
            await asyncio.sleep(cooldown)

        result = await test_connections(
            base_url=base_url,
            target=target,
            ramp_rate=rate,
            hold_seconds=hold_seconds,
            output_dir=output_dir,
        )
        summary.append(result)

    # Print final summary table
    print(f"\n\n{'='*60}")
    print(f"{'SWEEP SUMMARY':^60}")
    print(f"{'='*60}")
    print(f"{'rate':>10} {'target':>10} {'successes':>12} {'failures':>10}")
    print("-" * 60)
    for r in summary:
        print(f"{r['rate']:>10} {r['target']:>10} "
              f"{r['successes']:>12} {r['failures']:>10}")
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
    p4 = sub.add_parser("sweep", help="Run connection test at multiple ramp rates")
    p4.add_argument("--target", type=int, default=1000,
                    help="Connections per run (default: 1000)")
    p4.add_argument("--hold", type=int, default=5,
                    help="Hold time per run in seconds (default: 5)")
    p4.add_argument("--rates", type=int, nargs="+",
                    default=[10, 25, 50, 75, 100, 150, 200],
                    help="Ramp rates to test (default: 10 25 50 75 100 150 200)")
    p4.add_argument("--cooldown", type=int, default=10,
                    help="Seconds between runs (default: 10)")
    p4.add_argument("--output-dir", default="results",
                    help="Where to write CSVs (default: results/)")
    args = parser.parse_args()

    p5 = sub.add_parser("sweep-messages",
                        help="Run message latency test at multiple client counts")
    p5.add_argument("--clients", type=int, nargs="+",
                    default=[10, 50, 100, 250, 500, 1000],
                    help="Client counts to test "
                        "(default: 10 50 100 250 500 1000)")
    p5.add_argument("--msgs", type=int, default=20,
                    help="Messages per client per run (default: 20)")
    p5.add_argument("--rate", type=float, default=5.0,
                    help="Messages per second per client (default: 5)")
    p5.add_argument("--cooldown", type=int, default=10,
                    help="Seconds between runs (default: 10)")
    p5.add_argument("--output-dir", default="results",
                    help="Where to write CSVs (default: results/)")
    
    if args.cmd == "connections":
        asyncio.run(test_connections(args.url, args.target, args.ramp_rate, args.hold))
    elif args.cmd == "messages":
        asyncio.run(test_messages(args.url, args.clients, args.msgs, args.rate))
    elif args.cmd == "scaling":
        asyncio.run(test_scaling(args.url))
    elif args.cmd == "sweep":
        asyncio.run(run_sweep(
            args.url, args.target, args.hold,
            args.rates, args.cooldown, args.output_dir,
        ))
    elif args.cmd == "sweep-messages":
        asyncio.run(sweep_messages(
            args.url, args.clients, args.msgs,
            args.rate, args.cooldown, args.output_dir,
        ))
if __name__ == "__main__":
    main()