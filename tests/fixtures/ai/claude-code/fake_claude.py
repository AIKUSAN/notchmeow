#!/usr/bin/env python3
"""A stand-in for the `claude` program, for tests. It never contacts anything and never reads a login.

It records what it was started with, then plays back a transcript chosen by the test. Both apps' tests run
against it, so the Mac and Windows/Linux engines are held to the same command lines and the same transcripts.

What it understands (everything is controlled by environment variables, so a test can pass a clean one):
  claude --version                       prints NM_FAKE_CLAUDE_VERSION (default "2.1.211 (Claude Code)")
  claude auth status                     prints NM_FAKE_CLAUDE_AUTH_JSON (default {"authMethod":"claude.ai"}),
                                         exits NM_FAKE_CLAUDE_AUTH_EXIT (default 0)
  claude auth login                      records the call, exits 0
  claude -p ...                          a turn: reads stdin to its end (so a caller that forgets to close it hangs),
                                         then replays NM_FAKE_CLAUDE_TRANSCRIPT line by line and exits
                                         NM_FAKE_CLAUDE_EXIT (default 0)

  NM_FAKE_CLAUDE_LOG          append one JSON line per call: argv, env, cwd, stdin, pid
  NM_FAKE_CLAUDE_TRANSCRIPT   path of a .jsonl transcript; __SESSION_ID__ and __CWD__ are replaced
  NM_FAKE_CLAUDE_STDERR       text written to stderr before the transcript
  NM_FAKE_CLAUDE_EXIT         exit status after the transcript
  NM_FAKE_CLAUDE_HANG_AFTER   after this many transcript lines, stay alive until killed (a tool step that never ends)
  NM_FAKE_CLAUDE_CHILD_PIDFILE  when hanging, start a child process and write its pid here (the tree must die too)
  NM_FAKE_CLAUDE_STUBBORN     when hanging, ignore SIGINT and SIGTERM (only SIGKILL stops it)
  NM_FAKE_CLAUDE_PIDFILE      write this process's pid here
  NM_FAKE_CLAUDE_ASK_SOCKET   a Unix socket path (NotchMeow's nm.sock): after the first transcript line, send a
                              PermissionRequest hook payload for this run's session id, as the hook relay does, wait for
                              the one-line reply and record it in the log as {"permission": <reply>}. For checking the
                              approval card by hand against a Debug build; no test depends on it
"""
import json
import os
import signal
import socket
import subprocess
import sys
import time


def record(argv, stdin_text=""):
    path = os.environ.get("NM_FAKE_CLAUDE_LOG")
    if not path:
        return
    entry = {"argv": argv, "env": dict(os.environ), "cwd": os.getcwd(), "stdin": stdin_text, "pid": os.getpid()}
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def session_id(argv):
    for flag in ("--session-id", "--resume"):
        if flag in argv and argv.index(flag) + 1 < len(argv):
            return argv[argv.index(flag) + 1]
    return "00000000-0000-4000-8000-000000000000"


def ask_permission(path, sid, env):
    """What the hook relay does for a PermissionRequest: send one JSON line, read one line back."""
    payload = {"hook_event_name": "PermissionRequest", "session_id": sid, "tool_name": "Bash",
               "tool_input": {"command": "echo asked-by-the-fake"}, "cwd": os.getcwd()}
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
        s.settimeout(130)
        s.connect(path)
        s.sendall((json.dumps(payload) + "\n").encode("utf-8"))
        reply = s.makefile("r", encoding="utf-8").readline().strip()
    log = env.get("NM_FAKE_CLAUDE_LOG")
    if log:
        with open(log, "a", encoding="utf-8") as f:
            f.write(json.dumps({"permission": reply}) + "\n")


def hang(env):
    child = None
    pidfile = env.get("NM_FAKE_CLAUDE_CHILD_PIDFILE")

    def stop(*_):
        if child is not None:
            child.kill()
        os._exit(130)

    # Install signal handlers BEFORE spawning the child to close the race window.
    if env.get("NM_FAKE_CLAUDE_STUBBORN"):
        signal.signal(signal.SIGINT, signal.SIG_IGN)
        signal.signal(signal.SIGTERM, signal.SIG_IGN)
    else:
        signal.signal(signal.SIGINT, stop)
        signal.signal(signal.SIGTERM, stop)

    if pidfile:
        try:
            signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGINT, signal.SIGTERM})
            child = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(600)"],
                                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            with open(pidfile, "w", encoding="utf-8") as f:
                f.write(str(child.pid))
        finally:
            signal.pthread_sigmask(signal.SIG_UNBLOCK, {signal.SIGINT, signal.SIGTERM})

    while True:
        time.sleep(0.05)


def main():
    argv = sys.argv[1:]
    env = os.environ
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
        sys.stderr.reconfigure(encoding="utf-8")
    if env.get("NM_FAKE_CLAUDE_PIDFILE"):
        with open(env["NM_FAKE_CLAUDE_PIDFILE"], "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    if argv[:1] == ["--version"]:
        record(argv)
        print(env.get("NM_FAKE_CLAUDE_VERSION", "2.1.211 (Claude Code)"))
        return 0
    if argv[:2] == ["auth", "status"]:
        record(argv)
        print(env.get("NM_FAKE_CLAUDE_AUTH_JSON", '{"authMethod":"claude.ai"}'))
        return int(env.get("NM_FAKE_CLAUDE_AUTH_EXIT", "0"))
    if argv[:2] == ["auth", "login"]:
        record(argv)
        return 0

    stdin_text = sys.stdin.read()
    record(argv, stdin_text)
    if env.get("NM_FAKE_CLAUDE_STDERR"):
        sys.stderr.write(env["NM_FAKE_CLAUDE_STDERR"])
        sys.stderr.flush()
    hang_after = env.get("NM_FAKE_CLAUDE_HANG_AFTER")
    path = env.get("NM_FAKE_CLAUDE_TRANSCRIPT")
    if path:
        sid, cwd = session_id(argv), os.getcwd()
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        for number, line in enumerate(lines, start=1):
            sys.stdout.write(line.replace("__SESSION_ID__", sid).replace("__CWD__", json.dumps(cwd, ensure_ascii=False)[1:-1]) + "\n")
            sys.stdout.flush()
            if number == 1 and env.get("NM_FAKE_CLAUDE_ASK_SOCKET"):
                ask_permission(env["NM_FAKE_CLAUDE_ASK_SOCKET"], sid, env)
            if hang_after is not None and number >= int(hang_after):
                hang(env)
    elif hang_after is not None:
        hang(env)
    return int(env.get("NM_FAKE_CLAUDE_EXIT", "0"))


if __name__ == "__main__":
    sys.exit(main())
