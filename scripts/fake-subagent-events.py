#!/usr/bin/env python3
"""Sends scripted subagent hook events through NotchMeow's socket, the way the nm-hook relay does, so a running Debug build shows its kittens.

  python3 scripts/fake-subagent-events.py --list                      the scenarios
  python3 scripts/fake-subagent-events.py --scenario life             send one (default: life) to the app's socket
  python3 scripts/fake-subagent-events.py --scenario life --print     print the payloads instead of sending them
  python3 scripts/fake-subagent-events.py --sock /path/nm.sock        another socket (the App Store build's is ~/Library/Containers/<id>/Data/nm.sock)

The scenarios are tests/fixtures/mac/subagent-scenarios.json (the same file the tests and the contact sheets use). This is for the owner's check on a real build: the
tests send it to a socket of their own and never to the app. Each event is one connection, newline-delimited JSON, as the relay sends it; a PermissionRequest is held
open by the app until the card is answered (or --permission-timeout runs out), like Claude Code's own.
"""
import argparse, json, os, socket, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = os.path.join(HERE, "..", "tests", "fixtures", "mac", "subagent-scenarios.json")
DEFAULT_SOCK = os.path.expanduser("~/Library/Application Support/NotchMeow/nm.sock")


def payloads(data, name):
    """The payloads of one scenario in order: the common fields, then the step's event, with what to say and how long to wait."""
    out = []
    for step in data["scenarios"][name]["steps"]:
        if "event" in step:
            out.append((step["say"], {**data["common"], **step["event"]}, step.get("wait_ms", 600)))
        else:
            out.append((step["say"] + "  [the app does this by itself: " + json.dumps(step.get("internal")) + "]", None, step.get("wait_ms", 600)))
    return out


def send(sock_path, payload, permission_timeout):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(permission_timeout if payload.get("hook_event_name") == "PermissionRequest" else 5)
    try:
        s.connect(sock_path)
        s.sendall((json.dumps(payload) + "\n").encode())
        reply = b""
        while not reply.endswith(b"\n"):
            chunk = s.recv(4096)
            if not chunk:
                break
            reply += chunk
        return reply.decode().strip()
    finally:
        s.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--scenario", default="life")
    ap.add_argument("--sock", default=DEFAULT_SOCK)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--print", dest="dry", action="store_true", help="print the payloads, send nothing")
    ap.add_argument("--speed", type=float, default=1.0, help="2 waits half as long between events")
    ap.add_argument("--permission-timeout", type=float, default=120.0)
    a = ap.parse_args()
    data = json.load(open(SCENARIOS))
    if a.list:
        for name, sc in data["scenarios"].items():
            print(f"{name:14s} {len(sc['steps']):2d} steps  {sc['about']}")
        return 0
    if a.scenario not in data["scenarios"]:
        print(f"no scenario {a.scenario!r}: try --list", file=sys.stderr)
        return 2
    for say, payload, wait in payloads(data, a.scenario):
        print("-", say, flush=True)
        if payload is not None:
            if a.dry:
                print("  " + json.dumps(payload, sort_keys=True))
            else:
                try:
                    reply = send(a.sock, payload, a.permission_timeout)
                except OSError as e:
                    print(f"  could not reach {a.sock}: {e}", file=sys.stderr)
                    return 1
                print("  ->", reply or "(closed)", flush=True)
        if not a.dry:
            time.sleep(wait / 1000 / a.speed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
