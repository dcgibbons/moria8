#!/usr/bin/env python3
import socket
import sys
import time
import re
import argparse
from pathlib import Path

class ViceMonitor:
    def __init__(self, host="127.0.0.1", port=6502):
        self.host = host
        self.port = port
        self.sock = None

    def connect(self, debug=False):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.settimeout(5.0)
        if debug: print(f"Connecting to {self.host}:{self.port}...")
        self.sock.connect((self.host, self.port))
        if debug: print("Connected! Reading initial greeting...")
        # Consume initial greeting
        greeting = self.read_until_prompt()
        if debug: print(f"Greeting: {greeting}")

    def close(self):
        if self.sock:
            self.sock.close()

    def send_command(self, cmd, debug=False):
        if not cmd.endswith("\n"):
            cmd += "\n"
        if debug: print(f"Sending: {cmd.strip()}")
        self.sock.sendall(cmd.encode("ascii"))
        resp = self.read_until_prompt()
        if debug: print(f"Received: {resp}")
        return resp

    def read_until_prompt(self):
        data = b""
        while True:
            try:
                chunk = self.sock.recv(4096)
            except socket.timeout:
                break
            if not chunk:
                break
            data += chunk
            # Monitor prompt usually ends with (C:$XXXX) or similar
            if b"(C:" in data and data.endswith(b") "):
                break
            if b"READY." in data:
                break
        return data.decode("ascii", errors="ignore")

def normalize_addr(addr):
    addr = addr.strip().upper()
    if addr.startswith("$"):
        addr = addr[1:]
    return addr.zfill(4)

def run_test(args):
    vm = ViceMonitor(host=args.host, port=args.port)
    debug = args.verbose
    try:
        vm.connect(debug=debug)
    except Exception as e:
        print(f"Error connecting to VICE monitor: {e}")
        return 1

    # 1. Reset and initialize hardware invariants
    # Clear ZP
    vm.send_command("f 0000 00ff 00", debug=debug)
    # Set MMU to Bank 0 RAM/IO
    vm.send_command("> ff00 3e", debug=debug)
    # Set Common RAM invariant ($D506 = $07)
    vm.send_command("> d506 07", debug=debug)

    # 2. Inject binary
    prg_path = Path(args.prg).resolve()
    # Use 'load' since 'binload' might not be available.
    # Device 0 is the host file system.
    vm.send_command(f'load "{prg_path}" 0', debug=debug)

    # 3. Set breakpoints
    # We clear old breakpoints first
    vm.send_command("del", debug=debug)
    
    vm.send_command(f"break {args.pass_addr}", debug=debug)
    if args.fail_addr:
        vm.send_command(f"break {args.fail_addr}", debug=debug)

    # 4. Execute
    vm.send_command(f"g {args.start_addr}", debug=debug)

    # 5. Wait for stop
    start_time = time.time()
    passed = False
    error = ""
    
    while time.time() - start_time < args.timeout:
        # Check if stopped
        status = vm.send_command("", debug=False) # Empty command to get prompt/state
        if f"C:${args.pass_addr}" in status:
            passed = True
            break
        if args.fail_addr and f"C:${args.fail_addr}" in status:
            passed = False
            error = f"Reached test_fail label at ${args.fail_addr}"
            break
        if "JAM" in status or "Invalid opcode" in status:
            passed = False
            error = "CPU JAM"
            break
        time.sleep(0.01) # Faster poll
    else:
        passed = False
        error = f"Timeout after {args.timeout}s"

    vm.close()

    if passed:
        print(f"PASS: {args.name}")
        return 0
    else:
        print(f"FAIL: {args.name} ({error})")
        return 2

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="VICE Test Runner")
    parser.add_argument("--name", required=True)
    parser.add_argument("--prg", required=True)
    parser.add_argument("--start-addr", required=True)
    parser.add_argument("--pass-addr", required=True)
    parser.add_argument("--fail-addr")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=6502)
    parser.add_argument("--timeout", type=float, default=5.0)
    parser.add_argument("-v", "--verbose", action="store_true")

    args = parser.parse_args()
    args.start_addr = normalize_addr(args.start_addr)
    args.pass_addr = normalize_addr(args.pass_addr)
    if args.fail_addr:
        args.fail_addr = normalize_addr(args.fail_addr)

    sys.exit(run_test(args))
