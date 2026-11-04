#!/usr/bin/env python3
"""Minimal fake Ollama / LM Studio server for CI testing.

Usage: python3 fake_local_llm.py <port-file> [--persona P] [--fail F] [--delay S] [--log PATH]
  Writes the bound port to <port-file>, then serves until killed.
  --persona: generic (default), ollama, lmstudio, llamacpp, jan, ollama-ctx, lmstudio-ctx.
             The two -ctx personas also report context sizes (see CONTEXT_* below).
  --fail: none (default), timeout, 500, 429, 401, billing, overloaded, cut, slow-first-token, refuse, slow-models.
  --delay: seconds for timeout, slow-first-token and slow-models (default 3).
           slow-models: GET /v1/models answers only after the delay (a sleepy LAN server).
  --log: appends one JSON line per request: {"method", "path", "origin", "body"}.

Routes:
  GET  /v1/models              → two models (one embed, should be filtered out)
  POST /v1/chat/completions    → SSE stream with <think> block, reasoning-only
                                  deltas (content=null), and Markdown answer
  POST /v1/chat/completions    → 404 when model == "unknown-model"
  POST /v1/responses           → streams openai-responses fixtures
  POST /v1/messages            → streams anthropic fixtures
  GET  /api/version            → ollama only
  GET  /health                 → llamacpp only
  GET  /api/tags               → ollama only
  POST /api/show               → ollama-ctx only: parameters / model_info per model name
  GET  /api/v0/models          → lmstudio-ctx only: loaded_context_length / max_context_length per model
"""

import argparse
import json
import os
import sys
import socket
import socketserver
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

# Two models; "nomic-embed-text" must be filtered by the Swift client
MODELS_RESPONSE = {
    "data": [
        {"id": "llama3.2",         "object": "model"},
        {"id": "nomic-embed-text", "object": "model"},
    ]
}

# Context sizes, for the -ctx personas. Ollama's /api/show reports the context a model runs at in the
# `parameters` text (`num_ctx`) and its trained maximum in `model_info["<arch>.context_length"]`;
# LM Studio's /api/v0/models reports `loaded_context_length` (only while loaded) and `max_context_length`.
CONTEXT_OLLAMA = {
    "ctx-runtime":       {"parameters": "stop \"<|eot|>\"\nnum_ctx                        8192",
                          "model_info": {"general.architecture": "llama", "llama.context_length": 131072}},
    "ctx-trained-big":   {"parameters": "stop \"<|eot|>\"",
                          "model_info": {"general.architecture": "llama", "llama.context_length": 131072}},
    "ctx-trained-small": {"model_info": {"general.architecture": "gemma3", "gemma3.context_length": 2048}},
    "ctx-none":          {"capabilities": ["completion"]},
    "ctx-zero":          {"parameters": "num_ctx 0",
                          "model_info": {"general.architecture": "llama", "llama.context_length": 0}},
}
CONTEXT_LMSTUDIO = {
    "data": [
        {"id": "lm-loaded",      "type": "llm", "loaded_context_length": 16384, "max_context_length": 131072},
        {"id": "lm-max-big",     "type": "llm", "max_context_length": 131072},
        {"id": "lm-max-small",   "type": "llm", "max_context_length": 2048},
        {"id": "lm-none",        "type": "llm"},
        {"id": "lm-zero",        "type": "llm", "loaded_context_length": 0, "max_context_length": 0},
    ]
}

# SSE events that make up the streamed reply:
#  - events 0-2: a <think> block split over two chunks (should be hidden from UI)
#  - event 3: a delta with reasoning_content only (content is null → ignored)
#  - events 4-7: real Markdown answer
SSE_EVENTS = [
    {"choices": [{"delta": {"content": "<think>\nstep "}}]},
    {"choices": [{"delta": {"content": "one\n</think>"}}]},
    # reasoning-only delta: content key present but value is null
    {"choices": [{"delta": {"content": None, "reasoning_content": "internal"}}]},
    {"choices": [{"delta": {"content": "## Answer\n\n"}}]},
    {"choices": [{"delta": {"content": "Here is the result:\n\n"}}]},
    {"choices": [{"delta": {"content": "- **item 1**\n"}}]},
    {"choices": [{"delta": {"content": "- item 2\n\n"}}]},
    {"choices": [{"delta": {"content": "```python\nprint('hello')\n```"}}]},
]

EXPECTED_RESPONSE = "## Answer\n\nHere is the result:\n\n- **item 1**\n- item 2\n\n```python\nprint('hello')\n```"

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "ai", "sse")
OPTS = argparse.Namespace(persona="generic", fail="none", delay=3.0, log=None)

ERROR_BODIES = {
    "500": (500, {}, {"type": "error", "error": {"type": "api_error", "message": "Internal server error"}}),
    "429": (429, {"Retry-After": "2"}, {"error": {"type": "rate_limit_error", "code": "slow_down", "message": "Slow down"}}),
    "401": (401, {}, {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}),
    "billing": (429, {}, {"error": {"type": "insufficient_quota", "code": "insufficient_quota", "message": "You exceeded your current quota"}}),
}


def has_client_tools(fmt, tools):
    """True when the request carries a client-side function tool.

    Hosted tools don't count: Anthropic `{"type": "web_search_20250305", ...}` and
    Responses `{"type": "web_search"}`. Claude and OpenAI requests always carry web
    search, and must still get a text stream.
    """
    for t in tools or []:
        ttype = t.get("type", "")
        if fmt == "anthropic":
            if not ttype.startswith("web_search"):  # custom tools: name + input_schema, no server type
                return True
        elif ttype == "function":
            return True
    return False


def read_fixture(fmt, name):
    with open(os.path.join(FIXTURES, fmt, name), encoding="utf-8") as f:
        return f.read()


class FakeLLMHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress request logging

    def _send_json(self, status, payload, headers=None):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _log(self, body):
        if OPTS.log:
            with open(OPTS.log, "a") as f:
                f.write(json.dumps({"method": self.command, "path": self.path,
                                    "origin": self.headers.get("Origin"), "body": body}) + "\n")

    def do_GET(self):
        self._log(None)
        persona_routes = {
            ("ollama", "/api/version"): {"version": "0.35.1"},
            ("ollama", "/api/tags"): {"models": [{"name": "qwen3.5:2b"}, {"name": "nomic-embed-text"}]},
            ("llamacpp", "/health"): {"status": "ok"},
            ("ollama-ctx", "/api/version"): {"version": "0.35.1"},
            ("lmstudio-ctx", "/api/v0/models"): CONTEXT_LMSTUDIO,
        }
        path = self.path.split("?", 1)[0]  # real APIs take queries such as ?limit=100
        if path == "/v1/models":
            if OPTS.fail == "slow-models":
                time.sleep(OPTS.delay)
            self._send_json(200, MODELS_RESPONSE)
        elif (OPTS.persona, path) in persona_routes:
            self._send_json(200, persona_routes[(OPTS.persona, path)])
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            req_body = json.loads(raw)
        except Exception:
            req_body = {}
        self._log(req_body)

        if OPTS.persona == "ollama-ctx" and self.path.split("?", 1)[0] == "/api/show":
            details = CONTEXT_OLLAMA.get(req_body.get("model", ""))
            if details is None:
                self._send_json(404, {"error": "model not found"})
            else:
                self._send_json(200, details)
            return

        routes = {"/v1/chat/completions": "openai-chat", "/v1/responses": "openai-responses",
                  "/v1/messages": "anthropic"}
        fmt = routes.get(self.path.split("?", 1)[0])
        if fmt is None:
            self.send_response(404)
            self.end_headers()
            return

        model = req_body.get("model", "")
        if fmt == "openai-chat" and model == "unknown-model":
            self._send_json(404, {"error": {"message": f"model '{model}' not found, try pulling it first",
                                            "type": "not_found"}})
            return

        if OPTS.fail == "timeout":
            time.sleep(OPTS.delay)
        if OPTS.fail in ERROR_BODIES:
            status, headers, payload = ERROR_BODIES[OPTS.fail]
            self._send_json(status, payload, headers)
            return
        if OPTS.fail == "overloaded":
            if fmt == "anthropic":
                self._send_json(529, {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}})
            else:
                self._send_json(503, {"error": {"type": "service_unavailable_error", "code": "server_is_overloaded",
                                                "message": "Busy"}}, {"Retry-After": "7"})
            return

        client_tools = has_client_tools(fmt, req_body.get("tools"))
        if fmt == "openai-chat" and not client_tools and OPTS.fail != "cut":
            text = "".join("data: " + json.dumps(e) + "\n\n" for e in SSE_EVENTS) + "data: [DONE]\n\n"
        else:
            name = {"openai-chat": "text-think.txt", "openai-responses": "text-citations.txt",
                    "anthropic": "text-websearch.txt"}[fmt]
            if client_tools:
                name = {"openai-chat": "tool-call.txt", "openai-responses": "tool-call.txt",
                        "anthropic": "tool-use.txt"}[fmt]
            if OPTS.fail == "refuse" and fmt != "openai-chat":
                name = "refusal.txt"
            text = read_fixture(fmt, name)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if OPTS.fail == "slow-first-token":
            self.wfile.flush()
            time.sleep(OPTS.delay)
        if OPTS.fail == "cut":
            # Exactly the first half of the lines, in one write, so the client sees a prefix
            # of the full stream with no terminal event.
            lines = text.splitlines(keepends=True)
            self.wfile.write("".join(lines[: len(lines) // 2]).encode())
            self.wfile.flush()
        else:
            for chunk in text.split("\n\n"):
                if chunk:
                    self.wfile.write((chunk + "\n\n").encode())
                    self.wfile.flush()
                    time.sleep(0.005)
        self.close_connection = True


class FastBindHTTPServer(HTTPServer):
    """HTTPServer that skips the reverse-DNS lookup in server_bind.

    The default HTTPServer.server_bind calls socket.getfqdn(), which triggers
    a reverse-DNS lookup for the bound address.  On some CI runners this can
    block for several seconds and cause the port-file handshake to time out.
    We bypass it by calling TCPServer.server_bind directly and hard-coding
    server_name to the loopback address we already know we are binding to.
    """

    def server_bind(self):
        socketserver.TCPServer.server_bind(self)
        self.server_name = "127.0.0.1"
        self.server_port = self.server_address[1]


def find_free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("port_file", nargs="?")
    parser.add_argument("--persona", default="generic", choices=["generic", "ollama", "lmstudio", "llamacpp", "jan",
                                                                        "ollama-ctx", "lmstudio-ctx"])
    parser.add_argument("--fail", default="none", choices=["none", "timeout", "500", "429", "401", "billing",
                                                           "overloaded", "cut", "slow-first-token", "refuse", "slow-models"])
    parser.add_argument("--delay", type=float, default=3.0)
    parser.add_argument("--log")
    args = parser.parse_args()
    OPTS.persona, OPTS.fail, OPTS.delay, OPTS.log = args.persona, args.fail, args.delay, args.log

    port = find_free_port()
    server = FastBindHTTPServer(("127.0.0.1", port), FakeLLMHandler)

    # Write port to the file passed as argv[1] so the caller can read it
    if args.port_file:
        with open(args.port_file, "w") as f:
            f.write(str(port))
            f.flush()

    server.serve_forever()
