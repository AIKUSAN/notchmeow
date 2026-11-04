#!/usr/bin/env python3
"""Sends the hook events of a Claude Code session in a terminal through NotchMeow's socket, the way the nm-hook relay does, so a running Debug build shows it.

  python3 scripts/fake-terminal-events.py                              Apple Terminal: a session, a prompt, one step, a stop
  python3 scripts/fake-terminal-events.py --term-program iTerm.app --bundle-id com.googlecode.iterm2
  python3 scripts/fake-terminal-events.py --approval                   also a permission request, held open until you answer the card in the island
  python3 scripts/fake-terminal-events.py --print                      print the payloads instead of sending them
  python3 scripts/fake-terminal-events.py --sock /path/nm.sock         another socket (the App Store build's is ~/Library/Containers/<id>/Data/nm.sock)

This is for the owner's check on a real build, and it never runs `claude`: the tests send it to a socket of their own (scripts/test-fake-terminal-events.sh) and never to the app.
Each event is one connection, newline-delimited JSON, as the relay sends it.
"""
import argparse, json, os, socket, sys, time

DEFAULT_SOCK = os.path.expanduser("~/Library/Application Support/NotchMeow/nm.sock")


def events(term_program, bundle_id, approval):
    common = {"session_id": "fake-term-1", "cwd": "/tmp/notchmeow-fake-terminal", "term_program": term_program, "bundle_id": bundle_id}
    steps = [
        ("the session starts: the Claude Code pill appears", {"hook_event_name": "SessionStart", "source": "startup"}),
        ("a prompt: the cat thinks", {"hook_event_name": "UserPromptSubmit", "prompt": "NM-FAKE: say hello"}),
        ("a step: the cat works, the step row reads Runs · echo NM-FAKE step", {"hook_event_name": "PreToolUse", "tool_name": "Bash", "tool_input": {"command": "echo NM-FAKE step"}}),
        ("the step is done", {"hook_event_name": "PostToolUse", "tool_name": "Bash", "tool_input": {"command": "echo NM-FAKE step"}}),
    ]
    if approval:
        steps.append(("a permission request: the card opens and the app waits for your click", {"hook_event_name": "PermissionRequest", "tool_name": "Bash", "tool_input": {"command": "echo NM-FAKE-APPROVAL"}}))
    steps.append(("the turn ends", {"hook_event_name": "Stop", "last_assistant_message": "NM-FAKE done."}))
    return [(say, {**common, **event}) for say, event in steps]


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
    ap.add_argument("--term-program", default="Apple_Terminal")
    ap.add_argument("--bundle-id", default="com.apple.Terminal")
    ap.add_argument("--approval", action="store_true")
    ap.add_argument("--sock", default=DEFAULT_SOCK)
    ap.add_argument("--print", dest="dry", action="store_true", help="print the payloads, send nothing")
    ap.add_argument("--speed", type=float, default=1.0, help="2 waits half as long between events")
    ap.add_argument("--permission-timeout", type=float, default=120.0)
    a = ap.parse_args()
    if a.speed <= 0:
        ap.error("--speed must be more than 0 (2 waits half as long, 0.5 twice as long)")
    for say, payload in events(a.term_program, a.bundle_id, a.approval):
        print("-", say, flush=True)
        if a.dry:
            print("  " + json.dumps(payload, sort_keys=True))
            continue
        try:
            reply = send(a.sock, payload, a.permission_timeout)
        except OSError as e:
            print(f"  could not reach {a.sock}: {e}", file=sys.stderr)
            return 1
        print("  ->", reply or "(closed)", flush=True)
        time.sleep(1.5 / a.speed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
