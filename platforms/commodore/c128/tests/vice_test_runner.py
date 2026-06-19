#!/usr/bin/env python3
import argparse
import sys

from vice_connector import VICEConnector, normalize_addr, run_test_case

def run_test(args):
    vm = VICEConnector(host=args.host, port=args.port, timeout=args.socket_timeout)
    debug = args.verbose
    try:
        vm.connect(debug=debug)
    except Exception as e:
        print(f"Error connecting to VICE monitor: {e}")
        return 1

    try:
        result = run_test_case(
            vm,
            prg_path=args.prg,
            start_addr=args.start_addr,
            pass_addr=args.pass_addr,
            fail_addr=args.fail_addr,
            timeout=args.timeout,
        )
    finally:
        vm.close()

    if result.passed:
        print(f"PASS: {args.name}")
        return 0

    print(f"FAIL: {args.name} ({result.reason})")
    return result.exit_code

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VICE Test Runner")
    parser.add_argument("--name", required=True)
    parser.add_argument("--prg", required=True)
    parser.add_argument("--start-addr", required=True)
    parser.add_argument("--pass-addr", required=True)
    parser.add_argument("--fail-addr")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6510)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("--socket-timeout", type=float, default=0.5)
    parser.add_argument("-v", "--verbose", action="store_true")

    args = parser.parse_args()
    args.start_addr = normalize_addr(args.start_addr)
    args.pass_addr = normalize_addr(args.pass_addr)
    if args.fail_addr:
        args.fail_addr = normalize_addr(args.fail_addr)

    sys.exit(run_test(args))
