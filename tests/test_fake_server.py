#!/usr/bin/env python3
"""Tests for tests/fake_local_llm.py (standard library only)."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(ROOT, "fake_local_llm.py")
FIX = os.path.join(ROOT, "fixtures", "ai")


class Server:
    def __init__(self, *flags):
        self.tmp = tempfile.TemporaryDirectory()
        self.port_file = os.path.join(self.tmp.name, "port")
        self.log = os.path.join(self.tmp.name, "log.jsonl")
        self.proc = subprocess.Popen([sys.executable, SERVER, self.port_file, "--log", self.log, *flags])
        for _ in range(300):
            if os.path.exists(self.port_file) and os.path.getsize(self.port_file):
                break
            time.sleep(0.01)
        else:
            self.proc.kill()
            self.proc.wait()
            self.tmp.cleanup()
            raise AssertionError("fake server never wrote its port file")
        with open(self.port_file) as f:
            self.base = f"http://127.0.0.1:{f.read().strip()}"

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as r:
            return r.status, r.read().decode()

    def post(self, path, body, timeout=10, headers=None):
        req = urllib.request.Request(self.base + path, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json", **(headers or {})})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, dict(r.headers), r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read().decode()

    def requests(self):
        with open(self.log) as f:
            return [json.loads(line) for line in f]

    def close(self):
        self.proc.kill()
        self.proc.wait()
        self.tmp.cleanup()


def fixture(*parts):
    with open(os.path.join(FIX, "sse", *parts), encoding="utf-8") as f:
        return f.read()


class FakeServerTests(unittest.TestCase):
    def test_generic_keeps_old_models_route(self):
        s = Server()
        try:
            status, body = self.get_ok(s, "/v1/models")
            self.assertEqual([m["id"] for m in json.loads(body)["data"]], ["llama3.2", "nomic-embed-text"])
        finally:
            s.close()

    def test_query_strings_are_ignored(self):
        s = Server()
        try:
            status, body = self.get_ok(s, "/v1/models?limit=100")
            self.assertEqual(json.loads(body)["data"][0]["id"], "llama3.2")
        finally:
            s.close()

    def test_ollama_persona_has_version(self):
        s = Server("--persona", "ollama")
        try:
            status, body = self.get_ok(s, "/api/version")
            self.assertIn("version", json.loads(body))
        finally:
            s.close()

    def test_llamacpp_persona_has_health_and_generic_does_not(self):
        s = Server("--persona", "llamacpp")
        g = Server()
        try:
            self.assertEqual(self.get_ok(s, "/health")[0], 200)
            with self.assertRaises(urllib.error.HTTPError):
                g.get("/health")
        finally:
            s.close()
            g.close()

    def test_responses_route_streams_fixture(self):
        s = Server()
        try:
            status, _, body = s.post("/v1/responses", {"model": "gpt-6.1-sol", "input": "hi", "store": False})
            self.assertEqual(status, 200)
            self.assertEqual(body, fixture("openai-responses", "text-citations.txt"))
            self.assertIs(s.requests()[0]["body"]["store"], False)
        finally:
            s.close()

    def test_messages_route_with_tools_streams_tool_use(self):
        s = Server()
        try:
            _, _, body = s.post("/v1/messages", {"model": "claude-sonnet-5-5", "tools": [{"name": "get_status"}]})
            self.assertEqual(body, fixture("anthropic", "tool-use.txt"))
        finally:
            s.close()

    def test_hosted_web_search_alone_still_streams_text(self):
        s = Server()
        try:
            _, _, body = s.post("/v1/responses", {"model": "gpt-6.1-sol", "tools": [{"type": "web_search"}]})
            self.assertEqual(body, fixture("openai-responses", "text-citations.txt"))
            _, _, body = s.post("/v1/messages", {"model": "claude-sonnet-5-5",
                                                 "tools": [{"type": "web_search_20250305", "name": "web_search"}]})
            self.assertEqual(body, fixture("anthropic", "text-websearch.txt"))
        finally:
            s.close()

    def test_429_has_retry_after(self):
        s = Server("--fail", "429")
        try:
            status, headers, body = s.post("/v1/responses", {"model": "x"})
            self.assertEqual(status, 429)
            self.assertEqual(headers.get("Retry-After"), "2")
            self.assertEqual(json.loads(body)["error"]["code"], "slow_down")
        finally:
            s.close()

    def test_billing_is_429_insufficient_quota(self):
        s = Server("--fail", "billing")
        try:
            status, _, body = s.post("/v1/responses", {"model": "x"})
            self.assertEqual((status, json.loads(body)["error"]["code"]), (429, "insufficient_quota"))
        finally:
            s.close()

    def test_overloaded_is_529_on_messages(self):
        s = Server("--fail", "overloaded")
        try:
            self.assertEqual(s.post("/v1/messages", {"model": "x"})[0], 529)
            self.assertEqual(s.post("/v1/responses", {"model": "x"})[0], 503)
        finally:
            s.close()

    def test_cut_sends_partial_stream(self):
        s = Server("--fail", "cut")
        try:
            _, _, body = s.post("/v1/messages", {"model": "x"})
            full = fixture("anthropic", "text-websearch.txt")
            self.assertTrue(full.startswith(body) and len(body) < len(full))
            self.assertNotIn("message_stop", body)
        finally:
            s.close()

    def test_timeout_delays_headers(self):
        s = Server("--fail", "timeout", "--delay", "2")
        try:
            with self.assertRaises(Exception):
                s.post("/v1/chat/completions", {"model": "llama3.2"}, timeout=0.5)
        finally:
            s.close()

    def test_log_records_origin_header(self):
        s = Server()
        try:
            s.post("/v1/chat/completions", {"model": "llama3.2"}, headers={"Origin": "http://tauri.localhost"})
            self.assertEqual(s.requests()[0]["origin"], "http://tauri.localhost")
        finally:
            s.close()

    def get_ok(self, s, path):
        status, body = s.get(path)
        self.assertEqual(status, 200)
        return status, body


if __name__ == "__main__":
    unittest.main(verbosity=2)
