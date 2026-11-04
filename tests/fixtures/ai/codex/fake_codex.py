#!/usr/bin/env python3
"""A stand-in for the `codex` program, for tests. It never contacts anything and never reads a login.

It records what it was started with, then plays back a transcript chosen by the test. The Codex engine's tests run
against it, so the Mac and Windows/Linux engines are held to the same command lines and the same transcripts.

What it understands (everything is controlled by environment variables, so a test can pass a clean one):
  codex --version                  prints NM_FAKE_CODEX_VERSION (default: the recorded version, recorded/v.txt)
  codex login status               prints NM_FAKE_CODEX_LOGIN_STDOUT (default "Logged in using ChatGPT") on stdout,
                                   or on stderr when NM_FAKE_CODEX_LOGIN_STREAM=stderr, and exits
                                   NM_FAKE_CODEX_LOGIN_EXIT (default 0)
  codex exec ...                   a turn: reads stdin to its end (so a caller that forgets to close it hangs), then
                                   replays NM_FAKE_CODEX_TRANSCRIPT line by line and exits NM_FAKE_CODEX_EXIT
                                   (default 0). Pictures are --image=<path> each; the bare --image form and a
                                   picture named - exit 2 (recorded first, so the log still shows the argv)
  anything else                    exits 2 with a line on stderr

  NM_FAKE_CODEX_LOG           append one JSON line per run: {"argv", "env", "cwd", "stdin", "pid"}
  NM_FAKE_CODEX_TRANSCRIPT    path of a .jsonl transcript. __ID_1__ becomes thread_id (the scrubber renamed that key,
                              because its prefix matched); every other __ID_n__ becomes a fresh uuid, one per n and
                              run; __CWD__ becomes the working folder
  NM_FAKE_CODEX_STDERR        text written to stderr before the transcript
  NM_FAKE_CODEX_EXIT          exit status after the transcript
  NM_FAKE_CODEX_HANG_AFTER    after this many transcript lines, stay alive until a signal (a turn that never ends)
  NM_FAKE_CODEX_CHILD_PIDFILE when hanging, start a child process and write its pid here (the tree must die too)
  NM_FAKE_CODEX_TRY_WRITE     with --sandbox read-only: try to create this file in the working folder, then log
                              {"write": "refused"} when the folder refuses it, or {"write": "made"} when it does not
  NM_FAKE_CODEX_PIDFILE       write this process's pid here
"""
import json
import os
import re
import signal
import subprocess
import sys
import time
import uuid

HERE = os.path.dirname(os.path.abspath(__file__))
ID_TOKEN = re.compile(r"__ID_(\d+)__")


def record(argv, stdin_text=""):
    path = os.environ.get("NM_FAKE_CODEX_LOG")
    if not path:
        return
    entry = {"argv": argv, "env": dict(os.environ), "cwd": os.getcwd(), "stdin": stdin_text, "pid": os.getpid()}
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


def record_write(outcome):
    path = os.environ.get("NM_FAKE_CODEX_LOG")
    if path:
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps({"write": outcome}) + "\n")


def picture_refusal(argv):
    """The pictures this fake takes are one `--image=<path>` each. The bare `--image <path>` form lets the real CLI
    read the final `-` as a second picture, and a picture named `-` would be the prompt, so both are refused."""
    for arg in argv:
        if arg == "--image":
            return "pictures go as --image=<path>, not as the bare --image form"
        if arg == "--image=-":
            return "a picture named - is refused: the prompt is read from stdin"
    return None


def read_only(argv):
    if "--sandbox" not in argv:
        return False
    at = argv.index("--sandbox") + 1
    return at < len(argv) and argv[at] == "read-only"


def try_write(name):
    """Try to create the file in this folder: a refusal by the folder's mode is the read-only sandbox's answer."""
    try:
        with open(os.path.join(os.getcwd(), name), "x", encoding="utf-8"):
            pass
    except OSError:
        record_write("refused")
    else:
        record_write("made")


def fill(line, ids, cwd):
    """One transcript line with its placeholders filled for this run."""
    def pick(match):
        n = match.group(1)
        if n == "1":
            return "thread_id"
        if n not in ids:
            ids[n] = str(uuid.uuid4())
        return ids[n]

    cwd_text = json.dumps(cwd, ensure_ascii=False)[1:-1]
    return ID_TOKEN.sub(pick, line).replace("__CWD__", cwd_text)


def hang():
    child = None
    pidfile = os.environ.get("NM_FAKE_CODEX_CHILD_PIDFILE")

    def stop(*_):
        if child is not None:
            child.kill()
        os._exit(130)

    # Handlers go in BEFORE the child is spawned, and signals are blocked while it spawns, so a signal that arrives
    # in between is delivered after child is set and the child is killed too.
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
    for stream in (sys.stdin, sys.stdout, sys.stderr):
        if hasattr(stream, "reconfigure"):
            stream.reconfigure(encoding="utf-8")
    if env.get("NM_FAKE_CODEX_PIDFILE"):
        with open(env["NM_FAKE_CODEX_PIDFILE"], "w", encoding="utf-8") as f:
            f.write(str(os.getpid()))
    if argv[:1] == ["--version"]:
        record(argv)
        with open(os.path.join(HERE, "recorded", "v.txt"), encoding="utf-8") as f:
            print(env.get("NM_FAKE_CODEX_VERSION", f.read().strip()))
        return 0
    if argv[:2] == ["login", "status"]:
        record(argv)
        stream = sys.stderr if env.get("NM_FAKE_CODEX_LOGIN_STREAM") == "stderr" else sys.stdout
        print(env.get("NM_FAKE_CODEX_LOGIN_STDOUT", "Logged in using ChatGPT"), file=stream)
        return int(env.get("NM_FAKE_CODEX_LOGIN_EXIT", "0"))
    if argv[:1] != ["exec"]:
        sys.stderr.write("the fake codex does not know these arguments\n")
        return 2

    stdin_text = sys.stdin.read()
    record(argv, stdin_text)
    refusal = picture_refusal(argv)
    if refusal:
        sys.stderr.write(f"the fake codex refuses these arguments: {refusal}\n")
        return 2
    if env.get("NM_FAKE_CODEX_TRY_WRITE") and read_only(argv):
        try_write(env["NM_FAKE_CODEX_TRY_WRITE"])
    if env.get("NM_FAKE_CODEX_STDERR"):
        sys.stderr.write(env["NM_FAKE_CODEX_STDERR"])
        sys.stderr.flush()
    hang_after = env.get("NM_FAKE_CODEX_HANG_AFTER")
    path = env.get("NM_FAKE_CODEX_TRANSCRIPT")
    if path:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
        ids, cwd = {}, os.getcwd()
        for number, line in enumerate(lines, start=1):
            sys.stdout.write(fill(line, ids, cwd) + "\n")
            sys.stdout.flush()
            if hang_after is not None and number >= int(hang_after):
                hang()
    elif hang_after is not None:
        hang()
    return int(env.get("NM_FAKE_CODEX_EXIT", "0"))


if __name__ == "__main__":
    sys.exit(main())
