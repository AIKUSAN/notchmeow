#!/usr/bin/env python3
"""Sends the hook events of a made-up Claude Code session through NotchMeow's socket, the way the nm-hook relay does, so a running Debug build shows the sidekick at work.

  python3 scripts/fake-sidekick-events.py                      the loop: a session, then the same step four times: a "going in circles" nudge
  python3 scripts/fake-sidekick-events.py --scenario risk      a high-risk permission request (rm -rf ~/NM-FAKE-build), held open until you answer the card: the grey line, the High risk badge
  python3 scripts/fake-sidekick-events.py --scenario waiting   a permission request, held open: open another view of the island within a minute (the chat, say), and the nudge says it is still waiting
  python3 scripts/fake-sidekick-events.py --scenario away      LOCK YOUR MAC when it says so; the script keeps an agent busy for a few minutes; unlock when it says: the recap
  python3 scripts/fake-sidekick-events.py --scenario quiet     a session that starts a step and then says nothing: the nudge comes after 15 minutes (5 after a finished step; use --finish for that)
  python3 scripts/fake-sidekick-events.py --scenario all       risk, then the loop (the quick ones)
  python3 scripts/fake-sidekick-events.py --scenario end       end the fake session
  python3 scripts/fake-sidekick-events.py --print              print the payloads instead of sending them
  python3 scripts/fake-sidekick-events.py --sock /path/nm.sock another socket (the App Store build's is ~/Library/Containers/<id>/Data/nm.sock)

This is for the owner's check on a real Debug build, and it never runs `claude`: the tests send it to a socket of their own (scripts/test-fake-sidekick-events.sh) and never to the app. Each event is one
connection, newline-delimited JSON, as the relay sends it. Every payload carries a session id that starts with `fake-sidekick` and the cwd `/tmp/notchmeow-fake-sidekick` (so the project the sidekick names is `notchmeow-fake-sidekick`); the prompt, the loop commands and the stop message also carry NM-FAKE, so what it shows is easy to tell from real work.
"""
import argparse, json, os, socket, sys, time

DEFAULT_SOCK = os.path.expanduser("~/Library/Application Support/NotchMeow/nm.sock")
COMMON = {"session_id": "fake-sidekick-1", "cwd": "/tmp/notchmeow-fake-sidekick", "term_program": "Apple_Terminal", "bundle_id": "com.apple.Terminal"}


def ev(say, name, **extra):
    return (say, {**COMMON, "hook_event_name": name, **extra})


def bash(command, name="PostToolUse"):
    return {"hook_event_name": name, "tool_name": "Bash", "tool_input": {"command": command}}


def start():
    return [ev("the session starts: the Claude Code pill appears", "SessionStart", source="startup"),
            ev("a prompt: the cat thinks", "UserPromptSubmit", prompt="NM-FAKE: do the thing")]


def scenario(name, minutes, finish):
    steps = start()
    if name == "loop":
        for i in range(4):
            steps.append(("the same step, time %d of 4%s" % (i + 1, ": the nudge shows now" if i == 3 else ""), {**COMMON, **bash("echo NM-FAKE loop")}))
    elif name == "risk":
        steps.append(("a high-risk request: the card has a grey line and a High risk badge, the cat jumps; it is held open until you answer",
                      {**COMMON, **bash("rm -rf ~/NM-FAKE-build", "PermissionRequest")}))
    elif name == "waiting":
        steps.append(("a request: leave its card, open the chat, and wait a minute; the island says Claude Code is still waiting for your OK",
                      {**COMMON, **bash("git push origin main", "PermissionRequest")}))
    elif name == "away":
        for i in range(int(minutes * 3)):
            steps.append(("work while you are away (%d of %d)" % (i + 1, int(minutes * 3)), {**COMMON, "hook_event_name": "PostToolUse", "tool_name": "Edit",
                          "tool_input": {"file_path": "/tmp/notchmeow-fake-sidekick/file%d.txt" % (i % 3), "old_string": "a", "new_string": "b"}}))
        steps.append(("the turn ends: unlock your Mac now; the recap shows once", {**COMMON, "hook_event_name": "Stop", "last_assistant_message": "NM-FAKE done."}))
    elif name == "end":
        steps = [ev("the fake session ends", "SessionEnd")]
    elif name == "quiet":
        steps.append(("a step begins and never ends: the nudge comes 15 minutes later", {**COMMON, **bash("sleep 3600", "PreToolUse")}))
        if finish:
            steps[-1] = ("a step ends and nothing follows: the nudge comes 5 minutes later", {**COMMON, **bash("echo NM-FAKE")})
    return steps


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
    ap.add_argument("--scenario", default="loop", choices=["loop", "risk", "waiting", "away", "quiet", "all", "end"])
    ap.add_argument("--minutes", type=float, default=3.0, help="how long the away scenario keeps an agent busy (the recap needs more than 2)")
    ap.add_argument("--finish", action="store_true", help="the quiet scenario: end a step instead of starting one")
    ap.add_argument("--sock", default=DEFAULT_SOCK)
    ap.add_argument("--print", dest="dry", action="store_true", help="print the payloads, send nothing")
    ap.add_argument("--speed", type=float, default=1.0, help="2 waits half as long between events")
    ap.add_argument("--permission-timeout", type=float, default=120.0)
    a = ap.parse_args()
    if a.speed <= 0:
        ap.error("--speed must be more than 0 (2 waits half as long, 0.5 twice as long)")
    if a.minutes <= 0:
        ap.error("--minutes must be more than 0")
    names = ["risk", "loop"] if a.scenario == "all" else [a.scenario]
    gap = 20.0 if a.scenario == "away" else 2.0
    for name in names:
        for say, payload in scenario(name, a.minutes, a.finish):
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
            time.sleep(gap / a.speed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
