#!/usr/bin/env python3
"""Sends the owner's scripted Projects run through NotchMeow's socket, the way the nm-hook relay does, so a running Debug build shows its projects.

  python3 scripts/fake-projects-events.py --list                        the scenarios
  python3 scripts/fake-projects-events.py                               send two-projects (the default) to the app's socket
  python3 scripts/fake-projects-events.py --scenario all                send all five, in file order
  python3 scripts/fake-projects-events.py --scenario end --print        print the payloads instead of sending them
  python3 scripts/fake-projects-events.py --speed 2 --sock /path/nm.sock   twice as fast, another socket (the App Store build's is ~/Library/Containers/<id>/Data/nm.sock)

The scenarios are tests/fixtures/mac/projects-scenarios.json (the same file the tests use). `wait_ms` is the pause since the previous step. A cwd that starts
with `~` is expanded with os.path.expanduser (this machine's home, not the fixture's `home`). A step with `event: null` is a time-only step: printed, nothing sent.
A step with `waitIn` is printed with a note: the focus-awareness feature, not this script, decides a step-back, so its payload is sent unchanged. Each event is one
connection, newline-delimited JSON, as the relay sends it; a PermissionRequest is held open by the app until the card is answered (or --permission-timeout runs
out), like Claude Code's own. This is for the owner's check on a real build: the tests send it to a socket of their own and never to the app.

The socket it sends to is printed first (`sending to <path>`), so you can see which app you are talking to. A printed reply does NOT prove the event registered: the app answers
`{"ok":true}` for a payload it ignores too (a path it could not read, a session it did not file). Look at the island, not at the replies. Exit codes: 0 sent, 1 the socket could
not be reached, 2 a bad argument, 3 a PermissionRequest was never answered in time (the app WAS reached: its card is still waiting for you; the run stops there).
"""
import argparse, copy, json, os, socket, sys, time

HERE = os.path.dirname(os.path.abspath(__file__))
SCENARIOS = os.path.join(HERE, "..", "tests", "fixtures", "mac", "projects-scenarios.json")
DEFAULT_SOCK = os.path.expanduser("~/Library/Application Support/NotchMeow/nm.sock")
WAIT_IN_NOTE = "  [waitIn: the focus-awareness feature, not this script, decides a step-back; sent unchanged]"


def steps(data, name):
    """(say, payload or None, wait_ms) per step, in order. Each payload is a copy with a cwd starting with ~ expanded; the fixture is never changed."""
    out = []
    for step in data["scenarios"][name]["steps"]:
        wait = step.get("wait_ms", 0)
        if step.get("event") is None:
            out.append((step["say"] + "  [time only: the app does this by itself]", None, wait))
            continue
        payload = copy.deepcopy(step["event"])
        cwd = payload.get("cwd")
        if isinstance(cwd, str) and cwd.startswith("~"):
            payload["cwd"] = os.path.expanduser(cwd)
        say = step["say"] + (WAIT_IN_NOTE if "waitIn" in step else "")
        out.append((say, payload, wait))
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
    ap.add_argument("--scenario", default="two-projects", help="one of the scenarios from --list, or all")
    ap.add_argument("--sock", default=DEFAULT_SOCK)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--print", dest="dry", action="store_true", help="print the payloads, send nothing")
    ap.add_argument("--speed", type=float, default=1.0, help="2 waits half as long between events")
    ap.add_argument("--permission-timeout", type=float, default=120.0)
    a = ap.parse_args()
    if a.speed <= 0:
        ap.error("--speed must be more than 0 (2 waits half as long, 0.5 twice as long)")
    with open(SCENARIOS) as f:
        data = json.load(f)
    if a.list:
        for name, sc in data["scenarios"].items():
            print(f"{name:16s} {len(sc['steps']):2d} steps  {sc['about']}")
        return 0
    names = list(data["scenarios"]) if a.scenario == "all" else [a.scenario]
    if any(n not in data["scenarios"] for n in names):
        print(f"no scenario {a.scenario!r}: try --list", file=sys.stderr)
        return 2
    if not a.dry:
        print(f"sending to {a.sock}", flush=True)
    for name in names:
        if len(names) > 1:
            print(f"== {name}", flush=True)
        for say, payload, wait in steps(data, name):
            if not a.dry:
                time.sleep(wait / 1000 / a.speed)
            print("-", say, flush=True)
            if payload is None:
                continue
            if a.dry:
                print("  " + json.dumps(payload, sort_keys=True))
                continue
            try:
                reply = send(a.sock, payload, a.permission_timeout)
            except socket.timeout:
                # a timeout is an OSError too, so this comes first: the connection worked, the card is just still waiting for a click
                print(f"  card still waiting for an answer, stopping (the app at {a.sock} was reached)", file=sys.stderr)
                return 3
            except OSError as e:
                print(f"  could not reach {a.sock}: {e}", file=sys.stderr)
                return 1
            print("  ->", reply or "(closed)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
