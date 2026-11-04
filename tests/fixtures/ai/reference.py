#!/usr/bin/env python3
"""Reference implementation of NotchMeow's AI contract.

Runs every fixture in tests/fixtures/ai/ against a small, obviously-correct
Python model of the spec. Exit status 1 if any case fails. Both apps implement
the same behaviour natively; this file is the tie-breaker when they disagree.
"""
import json
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def check(label, got, expected):
    global FAILURES
    if got == expected:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}\n    got:      {got!r}\n    expected: {expected!r}")
        FAILURES += 1


def check_catalog():
    print("providers.json")
    cat = load("providers.json")
    ids = [p["id"] for p in cat["providers"]]
    check("provider ids", ids, ["anthropic", "openai", "google", "ollama", "lmstudio",
                                "llamacpp", "jan", "apple", "custom", "claudeCode", "codexPlan"])
    ports = {p["id"]: p.get("port") for p in cat["providers"] if p.get("port")}
    check("local ports", ports, {"ollama": 11434, "lmstudio": 1234, "llamacpp": 8080, "jan": 1337})
    check("cloud order", cat["cloudOrder"], ["anthropic", "openai", "google"])
    check("web search tools", (cat["webSearch"]["anthropic"]["type"], cat["webSearch"]["openai"]["type"]),
          ("web_search_20260209", "web_search"))
    ws = cat["webSearch"]["anthropic"]

    def anthropic_web_search_type(model):
        legacy = any(model.startswith(p) for p in ws["legacyModelPrefixes"])
        return ws["legacyType"] if legacy else ws["type"]

    check("sonnet 5.5 gets the new tool", anthropic_web_search_type("claude-sonnet-5-5"), "web_search_20260209")
    check("haiku 4.5 gets the legacy tool", anthropic_web_search_type("claude-haiku-4-5-20251001"), "web_search_20250305")
    check("timeouts ms", cat["timeoutsMs"], {"probe": 300, "connectLocal": 5000, "connectCloud": 10000,
                                              "firstTokenLocal": 60000, "firstTokenCloud": 30000})
    custom = next(p for p in cat["providers"] if p["id"] == "custom")
    check("custom placement and key prefix", (custom["placement"], custom["keychainKey"]),
          ("computed", "custom-server-key"))
    check("max file bytes", cat["limits"]["maxFileBytes"], 25 * 1024 * 1024)
    check("reply length by placement", cat["maxOutputTokens"], {"cloud": 16000, "network": 4096, "local": 4096})


TEMPORARY = {"offline", "unreachable", "timeout", "server", "rate_limited", "overloaded"}
COUNTDOWN = {"rate_limited", "overloaded"}
BILLING_CODES = {"insufficient_quota", "credit_balance_exhausted", "organization_usage_limit_exceeded",
                 "billing_error"}
CLOUD = {"anthropic", "openai", "google", "claudeCode", "codexPlan"}


def _cloud_choice(inp):
    order = [inp["preferredCloud"]] + [p for p in ("claudeCode", "anthropic", "openai") if p != inp["preferredCloud"]] + ["google"]
    for p in order:
        if p in inp["keys"]:
            return p
    return None


def _local_choice(inp):
    """Returns (provider, placement) or None: last used if ready, else first ready, else Apple."""
    ready = inp["localReady"]
    last = inp["lastUsedLocal"]
    if last:
        for r in ready:
            if r["provider"] == last["provider"] and r["model"] == last["model"]:
                return r["provider"], r["placement"]
    if ready:
        return ready[0]["provider"], ready[0]["placement"]
    if inp["appleReady"]:
        return "apple", "local"
    return None


def _placement(inp, provider):
    if provider in CLOUD:
        return "cloud"
    if provider == "apple":
        return "local"
    for r in inp["localReady"]:
        if r["provider"] == provider:
            return r["placement"]
    return "local"


def route(inp):
    auto = inp["setting"] == "auto"
    if auto:
        cloud = _cloud_choice(inp)
        local = _local_choice(inp)
        if cloud and (inp["online"] or not local):
            primary = cloud
        elif local:
            primary = local[0]
        else:
            return {"primary": None, "outcome": "empty_state", "answeredBy": None, "label": None, "errorKind": None}
    else:
        primary = inp["setting"]["provider"]
        local = None

    failure = inp["failure"]
    if failure is None:
        return {"primary": primary, "outcome": "ok", "answeredBy": primary,
                "label": _placement(inp, primary), "errorKind": None}
    if failure == "cancelled":
        return {"primary": primary, "outcome": "cancelled", "answeredBy": None, "label": None, "errorKind": None}
    if failure == "interrupted":
        return {"primary": primary, "outcome": "interrupted", "answeredBy": primary,
                "label": _placement(inp, primary), "errorKind": "interrupted"}
    if failure in TEMPORARY and auto and primary in CLOUD and local:
        return {"primary": primary, "outcome": "fallback", "answeredBy": local[0],
                "label": local[1], "errorKind": failure}
    if failure in COUNTDOWN:
        return {"primary": primary, "outcome": "retry_countdown", "answeredBy": None, "label": None, "errorKind": failure}
    return {"primary": primary, "outcome": "error", "answeredBy": None, "label": None, "errorKind": failure}


def check_router():
    print("router-cases.json")
    data = load("router-cases.json")
    for case in data["cases"]:
        inp = dict(data["defaults"])
        inp.update(case["input"])
        check(case["name"], route(inp), case["expect"])


def _is_billing(v):
    return isinstance(v, str) and (v in BILLING_CODES or v.endswith("_spend_limit_exceeded"))


def _first_dict(v):
    """`v` itself if a dict, its first element if a list (Google wraps errors in a list), else {}."""
    if isinstance(v, list):
        v = v[0] if v else None
    return v if isinstance(v, dict) else {}


def classify_http(status, body, headers):
    err = _first_dict(_first_dict(body).get("error"))
    message = err.get("message")
    retry = None
    for k, v in (headers or {}).items():
        if k.lower() == "retry-after" and re.fullmatch(r"[0-9]+", str(v).strip()):
            retry = int(str(v).strip()) or None
    if (_is_billing(err.get("code")) or _is_billing(err.get("type")) or status == 402
            or (isinstance(message, str) and "credit balance" in message.lower())):
        return "billing", retry
    if status in (401, 403):
        return "auth", retry
    if status in (400, 404, 413, 422):
        return "bad_request", retry
    if status == 429:
        return "rate_limited", retry
    if status in (503, 529):
        return "overloaded", retry
    if 500 <= status < 600:
        return "server", retry
    return "bad_request", retry


STREAM_KINDS = {
    "rate_limited": ("rate_limit_exceeded", "rate_limit_error"),
    "overloaded": ("server_is_overloaded", "slow_down", "overloaded_error"),
    "server": ("server_error", "api_error", "timeout_error", "vector_store_timeout"),
    "refusal": ("invalid_prompt", "image_content_policy_violation", "content_policy_violation", "content_filter"),
    "auth": ("authentication_error", "invalid_api_key", "permission_error"),
}


def stream_error_kind(code_or_type):
    """Kind of a mid-stream error (OpenAI `error.code`, Anthropic `error.type`). Unknown is bad_request: never falls back."""
    if _is_billing(code_or_type):
        return "billing"
    for kind, codes in STREAM_KINDS.items():
        if code_or_type in codes:
            return kind
    return "bad_request"


def check_http():
    print("http-errors.json")
    for case in load("http-errors.json")["cases"]:
        got = classify_http(case["status"], case["body"], case["headers"])
        check(f"{case['status']} → {case['kind']}", got, (case["kind"], case["retryAfter"]))


def budget(placement, context_tokens, text):
    limits = load("providers.json")["limits"]
    ctx = context_tokens
    if ctx is None and placement != "cloud":
        ctx = limits["defaultLocalContextTokens"]
    chars = int(ctx * limits["budgetFractionOfContext"] * limits["charsPerToken"]) if ctx else None
    if placement == "cloud":
        cap = limits["cloudTextCapChars"]
        chars = cap if chars is None else min(chars, cap)
    if len(text) <= chars:  # Python len() counts Unicode scalars
        return {"keptChars": len(text), "keptLines": text.count("\n") + (0 if text.endswith("\n") or not text else 1),
                "notice": None}
    kept, lines = 0, 0
    for line in re.findall(r"[^\n]*\n|[^\n]+", text):  # lines end at \n only
        if kept + len(line) > chars:
            break
        kept += len(line)
        lines += 1
    if lines == 0:
        return {"keptChars": chars, "keptLines": 0, "notice": "I read the first part of this file."}
    notice = "I read the first line." if lines == 1 else f"I read the first {lines} lines."
    return {"keptChars": kept, "keptLines": lines, "notice": notice}


def check_budget():
    print("budget-cases.json")
    for case in load("budget-cases.json")["cases"]:
        fill = case.get("fill", "a")
        text = (fill * (case["lineLength"] - 1) + "\n") * case["lineCount"]
        check(case["name"], budget(case["placement"], case["contextTokens"], text), case["expect"])


def _est_tokens(scalars):
    """ceil(scalars / 3.5), as integers so no language rounds differently."""
    return -(-scalars * 2 // 7)


def trim_history(placement, context_tokens, system_chars, turn_chars):
    """How many of the oldest turns to drop so a chat fits a small model.

    `turn_chars`: each turn's size in Unicode scalars, oldest first. Returns {dropped, notice}.
    """
    rule = load("history-cases.json")["rule"]
    if placement == "cloud":
        return {"dropped": 0, "notice": None}
    limits = load("providers.json")["limits"]
    ctx = limits["defaultLocalContextTokens"] if context_tokens is None else context_tokens
    budget = ctx - ctx // rule["reservedOutputDivisor"]
    total = system_chars + sum(turn_chars)
    dropped = 0
    while _est_tokens(total) > budget and len(turn_chars) - dropped > 1:
        step = min(2, len(turn_chars) - dropped - 1)
        total -= sum(turn_chars[dropped:dropped + step])
        dropped += step
    return {"dropped": dropped, "notice": rule["notice"] if dropped else None}


def _spec_chars(spec):
    return len(spec["fill"] * spec["count"])  # Python len() counts Unicode scalars


def _turn_chars(turn, rule):
    total = _spec_chars(turn["text"])
    for f in turn.get("files", []):
        total += _spec_chars(f["text"]) if f["kind"] == "text" else rule["binaryAttachmentChars"]
    return total


def check_history():
    print("history-cases.json")
    data = load("history-cases.json")
    rule = data["rule"]
    limits = load("providers.json")["limits"]
    check("rule constants", (rule["reservedOutputDivisor"], rule["binaryAttachmentChars"], limits["charsPerToken"]),
          (4, 1000, 3.5))
    for case in data["cases"]:
        sizes = [_turn_chars(t, rule) for t in case["turns"]]
        got = trim_history(case["placement"], case["contextTokens"], _spec_chars(case["system"]), sizes)
        check(case["name"], got, case["expect"])


def classify_file(path, rules):
    if os.path.getsize(path) > rules["maxFileBytes"]:
        return "rejected", "size"
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    if ext == "pdf":
        return "pdf", None
    if ext in rules["imageExtensions"]:
        return "image", None
    if ext in ("docx", "rtf"):
        return ext, None
    if ext in ("html", "htm"):
        return "html", None
    if ext in rules["rejectExtensions"]:
        return "rejected", "type"
    with open(path, "rb") as f:
        head = f.read(8192)
    if b"\x00" in head:
        return "rejected", "type"
    try:
        head.decode("utf-8")
    except UnicodeDecodeError as e:
        if e.start < len(head) - 3:  # only a multi-byte char cut at the very end is allowed
            return "rejected", "type"
    return "text", None


def check_attachments():
    print("attachment-cases.json")
    rules = load("attachment-cases.json")
    with tempfile.TemporaryDirectory() as d:
        subprocess.run([sys.executable, os.path.join(HERE, "make_attachments.py"), d], check=True)
        for case in rules["cases"]:
            kind, reason = classify_file(os.path.join(d, case["file"]), rules)
            expected_kind = "pdf" if case["kind"] in ("pdf_text", "pdf_scanned") else case["kind"]
            check(f"{case['file']} → {case['kind']}", (kind, reason), (expected_kind, case.get("reason")))


import glob

THINK = re.compile(r"<think>.*?</think>", re.DOTALL)


def _events(sse_text):
    """Yields parsed JSON payloads; skips comments, pings, blanks and non-JSON data."""
    for line in sse_text.split("\n"):  # lines end at \n only; one trailing \r (CRLF) is dropped
        line = line[:-1] if line.endswith("\r") else line
        if not line.startswith("data:"):
            continue
        payload = line[5:].strip()
        if payload == "[DONE]":
            yield "[DONE]"
            continue
        try:
            yield json.loads(payload)
        except ValueError:
            continue


def _result(text="", tools=None, cites=None, refusal=None, finish=None, error=None):
    seen, uniq = set(), []
    for c in cites or []:
        if c["url"] not in seen:
            seen.add(c["url"])
            uniq.append(c)
    return {"text": text, "toolCalls": tools or [], "citations": uniq, "refusal": refusal,
            "finish": None if error else finish, "error": error}


def agg_openai_chat(sse_text):
    text, tools, finish, done = "", {}, None, False
    for ev in _events(sse_text):
        if ev == "[DONE]":
            done = True
            continue
        for ch in ev.get("choices", []):
            d = ch.get("delta") or {}
            if isinstance(d.get("content"), str):
                text += d["content"]
            for tc in d.get("tool_calls") or []:
                slot = tools.setdefault(tc["index"], {"id": "", "name": "", "arguments": ""})
                slot["id"] = tc.get("id") or slot["id"]
                fn = tc.get("function") or {}
                slot["name"] = fn.get("name") or slot["name"]
                slot["arguments"] += fn.get("arguments") or ""
            if ch.get("finish_reason"):
                finish = {"content_filter": "refusal"}.get(ch["finish_reason"], ch["finish_reason"])
    text = THINK.sub("", text)
    refusal = "" if finish == "refusal" else None
    return _result(text, [tools[k] for k in sorted(tools)], [], refusal, finish,
                   None if done else "interrupted")


def agg_openai_responses(sse_text):
    text, calls, cites, refusal, finish, error, terminal = "", {}, [], None, None, None, False
    for ev in _events(sse_text):
        if ev == "[DONE]":
            continue
        t = ev.get("type")
        if t == "response.output_text.delta":
            text += ev["delta"]
        elif t == "response.output_item.added" and ev["item"].get("type") == "function_call":
            it = ev["item"]
            calls[it["id"]] = {"id": it["call_id"], "name": it["name"], "arguments": it.get("arguments", "")}
        elif t == "response.function_call_arguments.delta":
            calls[ev["item_id"]]["arguments"] += ev["delta"]
        elif t == "response.function_call_arguments.done":
            calls[ev["item_id"]]["arguments"] = ev["arguments"]
        elif t == "response.output_text.annotation.added" and ev["annotation"].get("type") == "url_citation":
            cites.append({"url": ev["annotation"]["url"], "title": ev["annotation"].get("title", "")})
        elif t == "response.refusal.done":
            refusal = ev["refusal"]
        elif t == "response.completed":
            terminal = True
            finish = "refusal" if refusal is not None else ("tool_calls" if calls else "stop")
        elif t == "response.incomplete":
            terminal = True
            reason = (ev["response"].get("incomplete_details") or {}).get("reason")
            finish = "refusal" if reason == "content_filter" else "length"
        elif t == "response.failed":
            terminal = True
            error = stream_error_kind((ev["response"].get("error") or {}).get("code"))
        elif t == "error":
            error = stream_error_kind(ev.get("code"))
    if not terminal and not error:
        error = "interrupted"
    return _result(text, list(calls.values()), cites, refusal, finish, error)


def agg_anthropic(sse_text):
    text, blocks, cites, finish, error, stopped = "", {}, [], None, None, False
    for ev in _events(sse_text):
        if ev == "[DONE]":
            continue
        t = ev.get("type")
        if t == "content_block_start":
            blocks[ev["index"]] = dict(ev["content_block"], _args="")
        elif t == "content_block_delta":
            d = ev["delta"]
            if d["type"] == "text_delta":
                text += d["text"]
            elif d["type"] == "input_json_delta":
                blocks[ev["index"]]["_args"] += d["partial_json"]
            elif d["type"] == "citations_delta":
                cites.append({"url": d["citation"]["url"], "title": d["citation"].get("title", "")})
        elif t == "message_delta":
            sr = ev["delta"].get("stop_reason")
            finish = {"end_turn": "stop", "max_tokens": "length", "tool_use": "tool_calls",
                      "refusal": "refusal", "stop_sequence": "stop"}.get(sr, finish)
        elif t == "message_stop":
            stopped = True
        elif t == "error":
            error = stream_error_kind(ev["error"]["type"])
    tools = [{"id": b["id"], "name": b["name"], "arguments": b["_args"]}
             for _, b in sorted(blocks.items()) if b["type"] == "tool_use"]
    refusal = None
    if finish == "refusal":
        refusal, text = text, ""
    if not stopped and not error:
        error = "interrupted"
    return _result(text, tools, cites, refusal, finish, error)


AGGREGATORS = {"openai-chat": agg_openai_chat, "openai-responses": agg_openai_responses, "anthropic": agg_anthropic}


def check_sse():
    print("sse/")
    for fmt, fn in AGGREGATORS.items():
        for path in sorted(glob.glob(os.path.join(HERE, "sse", fmt, "*.txt"))):
            with open(path, encoding="utf-8") as f:
                got = fn(f.read())
            with open(path[:-4] + ".expected.json", encoding="utf-8") as f:
                expected = json.load(f)
            check(f"{fmt}/{os.path.basename(path)}", got, expected)


CHECKS = [check_catalog, check_router, check_http, check_budget, check_history, check_attachments, check_sse]


def main():
    for fn in CHECKS:
        fn()
    if FAILURES:
        print(f"\n{FAILURES} failure(s)")
        sys.exit(1)
    print("\nAll AI contract checks passed")


if __name__ == "__main__":
    main()
