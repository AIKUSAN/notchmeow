#!/usr/bin/env python3
"""A stand-in for NotchMeow's socket, for the kitten tests: records every JSON line it is sent, in order, one per connection, and answers like the app does
(`{"ok":true}`, and for a PermissionRequest an immediate allow, as if the card had been answered). Usage: kitten_socket_server.py SOCKET RECEIVED.jsonl"""
import json, os, socket, sys

path, out = sys.argv[1], sys.argv[2]
if os.path.exists(path):
    os.unlink(path)
srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
srv.bind(path)
srv.listen(8)
open(out, "w").close()
while True:
    conn, _ = srv.accept()
    with conn:
        raw = b""
        while not raw.endswith(b"\n"):
            chunk = conn.recv(4096)
            if not chunk:
                break
            raw += chunk
        try:
            payload = json.loads(raw)
        except ValueError:
            payload = {}
        with open(out, "a") as f:
            f.write(json.dumps(payload, sort_keys=True) + "\n")
        reply = '{"permissionDecision":"allow"}' if payload.get("hook_event_name") == "PermissionRequest" else '{"ok":true}'
        conn.sendall((reply + "\n").encode())
