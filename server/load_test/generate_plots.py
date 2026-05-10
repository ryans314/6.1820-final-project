"""
generate_plots.py

Reads results_rate{N}.csv files produced by the load test and generates
a success-rate-vs-ramp-rate plot.

Usage:
    python generate_plots.py
    python generate_plots.py --target 1000 --pattern "results_rate*.csv"
    python generate_plots.py --output success_rate.png
"""

import argparse
import csv
import glob
import re
import sys
from pathlib import Path

import matplotlib.pyplot as plt
import statistics


def parse_ramp_rate(filename: str) -> int | None:
    """Extract the ramp rate from a filename like 'results_rate50.csv'."""
    match = re.search(r"rate(\d+)", filename)
    return int(match.group(1)) if match else None


def load_results(pattern: str) -> dict[int, dict]:
    """
    Load all CSV files matching pattern. Returns a dict mapping
    ramp_rate -> {"total": N, "successes": M}.
    """
    files = sorted(glob.glob(pattern))
    if not files:
        print(f"ERROR: No files matched pattern '{pattern}'", file=sys.stderr)
        sys.exit(1)

    data: dict[int, dict] = {}
    for filepath in files:
        rate = parse_ramp_rate(Path(filepath).name)
        if rate is None:
            print(f"  Skipping {filepath} (could not parse ramp rate)")
            continue

        total = 0
        successes = 0
        with open(filepath, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                total += 1
                # CSV booleans come in as strings — handle both common forms
                if str(row.get("success", "")).strip().lower() in ("true", "1"):
                    successes += 1

        data[rate] = {"total": total, "successes": successes}
        print(f"  Loaded {filepath}: {successes}/{total} successes "
              f"at {rate} conn/s")

    return data


def make_plot(data: dict[int, dict], target: int, output: str) -> None:
    """Generate the success-rate-vs-ramp-rate line plot. Only works when rate==target"""
    rates = sorted(data.keys())
    success_pct = [data[r]["successes"] / r * 100 for r in rates]

    fig, ax = plt.subplots(figsize=(8, 5))
    ax.plot(rates, success_pct, marker="o", linewidth=2,
            markersize=8, color="#2E86AB")

    # Annotate each point with the raw number of successes
    # for rate, pct in zip(rates, success_pct):
    #     print(rate, pct)
    #     ax.annotate(f"{pct:.1f}%",
    #                 xy=(rate, pct),
    #                 xytext=(0, 10), textcoords="offset points",
    #                 ha="center", fontsize=9, color="#555")
    
    # Annotate each point with the success percentage
    for rate, pct in zip(rates, success_pct):
        print(rate, pct)
        ax.annotate(f"{pct:.1f}%",
                    xy=(rate, pct),
                    xytext=(10, 10), textcoords="offset points",
                    ha="center", fontsize=9, color="#555")

    ax.set_xlabel("Target", fontsize=11)
    ax.set_ylabel("Success rate (%)", fontsize=11)
    ax.set_title(f"Connection success rate vs. number of connections", fontsize=12)
    ax.set_ylim(0, 110)
    ax.grid(alpha=0.3)
    ax.axhline(100, color="green", linestyle=":", alpha=0.4,
               label="100% (all connections succeed)")
    ax.legend(loc="lower left")

    plt.tight_layout()
    plt.savefig(output, dpi=150)
    print(f"\nPlot saved to {output}")

# TEST 2 PLOTS
def load_message_results(pattern: str) -> dict[float, dict]:
    """
    Load message CSVs matching pattern. Returns a dict mapping
    rate_per_client -> {"p50": ..., "p95": ..., "p99": ..., "total": ...}
    """
    files = sorted(glob.glob(pattern),
                   key=lambda f: float(re.search(r"rate([\d.]+)", 
                                                  Path(f).name).group(1))
                   if re.search(r"rate([\d.]+)", Path(f).name) else 0)

    if not files:
        print(f"ERROR: No files matched pattern '{pattern}'", file=sys.stderr)
        sys.exit(1)

    data = {}
    for filepath in files:
        match = re.search(r"rate([\d.]+)", Path(filepath).name)
        if not match:
            print(f"  Skipping {filepath} (could not parse rate)")
            continue
        rate = float(match.group(1))

        latencies = []
        with open(filepath, newline="") as f:
            reader = csv.DictReader(f)
            for row in reader:
                if str(row.get("success", "")).strip().lower() in ("true", "1"):
                    try:
                        latencies.append(float(row["latency_ms"]))
                    except (ValueError, KeyError):
                        pass

        if not latencies:
            print(f"  {filepath}: no successful rows, skipping")
            continue

        latencies.sort()
        total = len(latencies)
        q = statistics.quantiles(latencies, n=100) if total >= 100 else None

        data[rate] = {
            "p50": statistics.median(latencies),
            "p95": q[94] if q else max(latencies),
            "p99": q[98] if q else max(latencies),
            "total": total,
        }
        print(f"  Loaded {filepath}: {total} messages, "
              f"p50={data[rate]['p50']:.2f}ms")

    return data


def make_latency_plot(data: dict[float, dict], output: str) -> None:
    """
    Plot p50/p95/p99 round-trip latency vs message rate per client.
    Linear y-axis.
    """
    rates = sorted(data.keys())
    p50s = [data[r]["p50"] for r in rates]
    p95s = [data[r]["p95"] for r in rates]
    p99s = [data[r]["p99"] for r in rates]

    fig, ax = plt.subplots(figsize=(8, 5))

    ax.plot(rates, p50s, marker="o", linewidth=2, markersize=8,
            color="#2E86AB", label="p50")
    ax.plot(rates, p95s, marker="s", linewidth=2, markersize=8,
            color="#E63946", label="p95")
    ax.plot(rates, p99s, marker="^", linewidth=2, markersize=8,
            color="#F4A261", label="p99")

    # Annotate final value of each line
    for values, color in [(p50s, "#2E86AB"), (p95s, "#E63946"), (p99s, "#F4A261")]:
        ax.annotate(f"{values[-1]:.1f}ms",
                    xy=(rates[-1], values[-1]),
                    xytext=(8, 0), textcoords="offset points",
                    va="center", fontsize=9, color=color)

    ax.set_xlabel("Message rate per client (msgs/sec)", fontsize=12)
    ax.set_ylabel("Round-trip latency (ms)", fontsize=12)
    ax.set_title("Round-trip latency vs. message rate", fontsize=13)
    ax.legend(fontsize=11)
    ax.set_ylim(bottom=0)
    ax.grid(alpha=0.3)
    plt.tight_layout()
    plt.savefig(output, dpi=150)
    print(f"\nPlot saved to {output}")

def main():
    # parser = argparse.ArgumentParser(
    #     description="Plot connection success rate vs. ramp-up speed.")
    # parser.add_argument("--pattern", default="results/results_rate*.csv",
    #                     help="Glob pattern for CSV files "
    #                          "(default: results/results_rate*.csv)")
    # parser.add_argument("--target", type=int, default=1000,
    #                     help="Target connection count per run "
    #                          "(default: 1000)")
    # parser.add_argument("--output", default="success_rate.png",
    #                     help="Output image filename "
    #                          "(default: success_rate.png)")
    # args = parser.parse_args()

    # print(f"Loading CSV files matching '{args.pattern}'...")
    # data = load_results(args.pattern)

    # if not data:
    #     print("ERROR: No usable data found.", file=sys.stderr)
    #     sys.exit(1)

    # make_plot(data, args.target, args.output)

    parser = argparse.ArgumentParser(
        description="Generate load test plots.")
    parser.add_argument("--plot", choices=["connections", "latency", "both"],
                        default="both",
                        help="Which plot to generate (default: both)")
    parser.add_argument("--pattern-connections", default="results/results_rate*.csv")
    parser.add_argument("--pattern-messages",
                        default="results/results_messages_rate*.csv")
    parser.add_argument("--target", type=int, default=1000,
                        help="Connection target for success rate plot")
    parser.add_argument("--output-connections", default="success_rate.png")
    parser.add_argument("--output-latency", default="latency.png")
    args = parser.parse_args()

    if args.plot in ("connections", "both"):
        print(f"\nLoading connection CSVs...")
        conn_data = load_results(args.pattern_connections)
        if conn_data:
            make_plot(conn_data, args.target, args.output_connections)

    if args.plot in ("latency", "both"):
        print(f"\nLoading message CSVs...")
        msg_data = load_message_results(args.pattern_messages)
        if msg_data:
            make_latency_plot(msg_data, args.output_latency)


if __name__ == "__main__":
    main()