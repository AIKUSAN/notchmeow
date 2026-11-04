import Foundation

@main
@MainActor
enum AIRouterTests {
    static func main() {
        catalogMatchesProvidersJSON()
        logsStayInTheTestFolder()
        contractNames()
        routerCases()
        httpErrorCases()
        T.finish()
    }

    // MARK: - providers.json

    static func catalogMatchesProvidersJSON() {
        T.section("providers.json ↔ AICatalog")
        let json = T.fixture("providers.json")
        let rows = json["providers"] as! [[String: Any]]
        T.check("provider ids", rows.map { $0["id"] as! String }, AICatalog.providers.map(\.id.rawValue))
        T.check("enum covers every id", AIProviderID.allCases.map(\.rawValue), rows.map { $0["id"] as! String })
        for row in rows {
            let id = AIProviderID(rawValue: row["id"] as! String)!
            let p = AICatalog.info(id)
            T.check("\(id.rawValue) name", p.name, row["name"] as! String)
            T.check("\(id.rawValue) placement", p.placement, row["placement"] as! String)
            T.check("\(id.rawValue) api", p.api.rawValue, row["api"] as! String)
            T.check("\(id.rawValue) baseURL", p.baseURL, row["baseURL"] as? String)
            T.check("\(id.rawValue) chatPath", p.chatPath, row["chatPath"] as? String)
            T.check("\(id.rawValue) modelsPath", p.modelsPath, row["modelsPath"] as? String)
            T.check("\(id.rawValue) port", p.port, row["port"] as? Int)
            T.check("\(id.rawValue) probePath", p.probePath, row["probePath"] as? String)
            T.check("\(id.rawValue) keychainKey", p.keychainKey, row["keychainKey"] as? String)
            T.check("\(id.rawValue) defaultModel", p.defaultModel, row["defaultModel"] as? String)
        }
        T.check("cloud order", AICatalog.cloudOrder.map(\.rawValue), json["cloudOrder"] as! [String])
        T.check("Claude Code counts as cloud, and its default model is an alias", [AIProviderID.claudeCode.isCloud, AICatalog.info(.claudeCode).defaultModel == ClaudeCodeModel.sonnet.rawValue], [true, true])
        T.check("the OpenAI plan counts as cloud, has no key and no default model", [AIProviderID.codexPlan.isCloud, AICatalog.info(.codexPlan).keychainKey == nil, AICatalog.info(.codexPlan).defaultModel == nil], [true, true, true])
        T.check("Claude Code's model aliases", ClaudeCodeModel.allCases.map(\.rawValue), ["sonnet", "opus", "haiku"])
        let web = json["webSearch"] as? [String: [String: Any]] ?? [:]
        let claude = web["anthropic"] ?? [:]
        T.check("anthropic web search type", AICatalog.WebSearch.anthropicType, claude["type"] as? String)
        T.check("anthropic web search name", AICatalog.WebSearch.anthropicName, claude["name"] as? String)
        T.check("anthropic web search max_uses", AICatalog.WebSearch.anthropicMaxUses, claude["max_uses"] as? Int)
        T.check("anthropic legacy web search type", AICatalog.WebSearch.anthropicLegacyType, claude["legacyType"] as? String)
        T.check("anthropic legacy model prefixes", AICatalog.WebSearch.anthropicLegacyModelPrefixes,
                claude["legacyModelPrefixes"] as? [String] ?? [])
        T.check("openai web search type", AICatalog.WebSearch.openAIType, web["openai"]?["type"] as? String)

        let filters = json["modelFilters"] as! [String: [String: [String]]]
        T.check("local exclude", AICatalog.Filters.localExclude, filters["local"]!["exclude"]!)
        T.check("google exclude", AICatalog.Filters.googleExclude, filters["google"]!["exclude"]!)
        T.check("openai include", AICatalog.Filters.openAIIncludePrefixes, filters["openai"]!["includePrefixes"]!)
        T.check("openai exclude", AICatalog.Filters.openAIExclude, filters["openai"]!["exclude"]!)

        let ms = json["timeoutsMs"] as! [String: Int]
        T.check("probe timeout", Int(AICatalog.Timeouts.probe * 1000), ms["probe"]!)
        T.check("connect local", Int(AICatalog.Timeouts.connectLocal * 1000), ms["connectLocal"]!)
        T.check("connect cloud", Int(AICatalog.Timeouts.connectCloud * 1000), ms["connectCloud"]!)
        T.check("first token local", Int(AICatalog.Timeouts.firstTokenLocal * 1000), ms["firstTokenLocal"]!)
        T.check("first token cloud", Int(AICatalog.Timeouts.firstTokenCloud * 1000), ms["firstTokenCloud"]!)

        let limits = json["limits"] as! [String: Any]
        T.check("max file bytes", AICatalog.Limits.maxFileBytes, limits["maxFileBytes"] as! Int)
        T.check("cloud text cap", AICatalog.Limits.cloudTextCapChars, limits["cloudTextCapChars"] as! Int)
        T.check("budget fraction", AICatalog.Limits.budgetFractionOfContext, limits["budgetFractionOfContext"] as! Double)
        T.check("chars per token", AICatalog.Limits.charsPerToken, limits["charsPerToken"] as! Double)
        T.check("default local context", AICatalog.Limits.defaultLocalContextTokens, limits["defaultLocalContextTokens"] as! Int)

        T.section("Reply length")
        let caps = json["maxOutputTokens"] as! [String: Int]
        T.check("reply cap placements", Set(caps.keys), Set(["cloud", "network", "local"]))
        T.check("cloud reply cap", AICatalog.maxOutputTokens(for: .cloud), caps["cloud"]!)
        T.check("network reply cap", AICatalog.maxOutputTokens(for: .network), caps["network"]!)
        T.check("local reply cap", AICatalog.maxOutputTokens(for: .local), caps["local"]!)
        // Pinned on purpose: a cap changed in the fixture and the catalog together still stops here, so it is a decision.
        T.check("pinned reply caps (cloud 16,000, local 4,096)",
                [AICatalog.maxOutputTokens(for: .cloud), AICatalog.maxOutputTokens(for: .local)], [16_000, 4096])

        T.section("AICatalog helpers")
        T.check("localhost is local", AICatalog.placement(forHost: "localhost"), .local)
        T.check("::1 is local", AICatalog.placement(forHost: "[::1]"), .local)
        T.check("LAN host is network", AICatalog.placement(forHost: "studio-pc.local"), .network)
        T.check("local filter drops embeddings",
                AICatalog.filterModels(["llama3.2", "nomic-embed-text", "bge-m3"], for: .ollama), ["llama3.2"])
        T.check("google strips models/ and filters",
                AICatalog.filterModels(["models/gemini-3-flash", "models/text-embedding-005"], for: .google),
                ["gemini-3-flash"])
        T.check("openai keeps chat families only",
                AICatalog.filterModels(["gpt-6.1-sol", "whisper-1", "o5-mini", "gpt-6-search-preview", "dall-e-3"], for: .openai),
                ["gpt-6.1-sol", "o5-mini"])
        T.check("google default prefers flash",
                AICatalog.defaultModel(for: .google, available: ["gemini-3-pro", "gemini-3-flash"]), "gemini-3-flash")
        T.check("anthropic default is fixed",
                AICatalog.defaultModel(for: .anthropic, available: []), "claude-sonnet-5-5")

        T.section("Anthropic web search tool per model")
        T.check("Sonnet 5.5 gets the current tool", AICatalog.anthropicWebSearchType(model: "claude-sonnet-5-5"),
                "web_search_20260209")
        T.check("Haiku 4.5 gets the legacy tool", AICatalog.anthropicWebSearchType(model: "claude-haiku-4-5-20251001"),
                "web_search_20250305")
        T.check("Claude 3 models get the legacy tool", AICatalog.anthropicWebSearchType(model: "claude-3-5-sonnet-latest"),
                "web_search_20250305")
        T.check("any other model gets the current tool", AICatalog.anthropicWebSearchType(model: "claude-opus-5-5"),
                "web_search_20260209")
    }

    // MARK: - Logs

    /// The AI log goes through `appendAppLog`; with `NM_LOG_DIR` set it must land in the temp folder.
    static func logsStayInTheTestFolder() {
        T.section("Test logs")
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NM_LOG_DIR"]!, isDirectory: true)
        T.check("appLogDirectory follows NM_LOG_DIR", appLogDirectory().path, dir.path)
        appendAppLog("nm.log", "probe line from AIRouterTests")
        let written = (try? String(contentsOf: dir.appendingPathComponent("nm.log"), encoding: .utf8)) ?? ""
        T.checkTrue("a log line lands in the temp folder", written.contains("probe line from AIRouterTests"))
    }

    // MARK: - Names shared with the Windows/Linux app

    /// The exact error kinds and router outcomes of E1-0's Global Constraints.
    static func contractNames() {
        T.section("Contract names")
        T.check("error kinds", AIErrorKind.allCases.map(\.rawValue),
                ["offline", "unreachable", "timeout", "server", "rate_limited", "overloaded", "auth", "bad_request",
                 "billing", "refusal", "cancelled", "interrupted"])
        T.check("router outcomes",
                [RouteOutcome.ok, .fallback, .error, .retryCountdown, .emptyState, .interrupted, .cancelled].map(\.rawValue),
                ["ok", "fallback", "error", "retry_countdown", "empty_state", "interrupted", "cancelled"])
    }

    // MARK: - router-cases.json

    static func candidate(_ d: [String: Any]) -> LocalCandidate {
        LocalCandidate(provider: AIProviderID(rawValue: d["provider"] as! String)!,
                       model: d["model"] as! String,
                       placement: AIPlacement(rawValue: d["placement"] as! String)!)
    }

    static func routeInput(_ d: [String: Any]) -> RouteInput {
        var input = RouteInput()
        if let s = d["setting"] as? [String: Any] {
            input.setting = .explicit(ModelRef(provider: AIProviderID(rawValue: s["provider"] as! String)!,
                                               model: s["model"] as! String))
        }
        input.preferredCloud = AIProviderID(rawValue: d["preferredCloud"] as! String)!
        input.keys = Set((d["keys"] as! [String]).map { AIProviderID(rawValue: $0)! })
        input.online = d["online"] as! Bool
        input.localReady = (d["localReady"] as! [[String: Any]]).map(candidate)
        if let last = d["lastUsedLocal"] as? [String: Any] {
            input.lastUsedLocal = ModelRef(provider: AIProviderID(rawValue: last["provider"] as! String)!,
                                           model: last["model"] as! String)
        }
        input.appleReady = d["appleReady"] as! Bool
        input.failure = (d["failure"] as? String).map { AIErrorKind(rawValue: $0)! }
        return input
    }

    static func expected(_ d: [String: Any]) -> RouteDecision {
        RouteDecision(primary: (d["primary"] as? String).flatMap(AIProviderID.init(rawValue:)),
                      outcome: RouteOutcome(rawValue: d["outcome"] as! String)!,
                      answeredBy: (d["answeredBy"] as? String).flatMap(AIProviderID.init(rawValue:)),
                      label: (d["label"] as? String).flatMap(AIPlacement.init(rawValue:)),
                      errorKind: (d["errorKind"] as? String).flatMap(AIErrorKind.init(rawValue:)))
    }

    static func routerCases() {
        T.section("router-cases.json")
        let data = T.fixture("router-cases.json")
        let defaults = data["defaults"] as! [String: Any]
        for c in data["cases"] as! [[String: Any]] {
            let merged = defaults.merging(c["input"] as! [String: Any]) { _, new in new }
            T.check(c["name"] as! String, ModelRouter.route(routeInput(merged)), expected(c["expect"] as! [String: Any]))
        }

        T.section("ModelRouter.plan (app-side shape)")
        var input = RouteInput()
        input.keys = [.anthropic]
        input.localReady = [LocalCandidate(provider: .ollama, model: "qwen3.5:2b", placement: .local)]
        let plan = ModelRouter.plan(input)
        T.check("cloud primary keeps a local fallback", plan?.fallback?.model, "qwen3.5:2b")
        input.setting = .explicit(ModelRef(provider: .anthropic, model: "claude-opus-5-5"))
        T.check("explicit choice has no fallback", ModelRouter.plan(input)?.fallback, nil)
        T.check("explicit choice keeps its model", ModelRouter.plan(input)?.model, "claude-opus-5-5")

        T.section("ModelRouter.plan for the OpenAI plan")
        var codex = RouteInput()
        codex.setting = .explicit(ModelRef(provider: .codexPlan, model: ""))
        let explicit = ModelRouter.plan(codex)
        T.check("an explicit OpenAI plan has no fallback", explicit?.fallback, nil)
        T.checkTrue("and it is not Auto", explicit?.isAuto == false)
        T.check("and it runs in the cloud", explicit?.placement, .cloud)
        var auto = RouteInput()
        auto.keys = Set(AICatalog.cloudOrder)
        auto.localReady = [LocalCandidate(provider: .ollama, model: "qwen3.5:2b", placement: .local)]
        let never = AICatalog.cloudOrder.allSatisfy { preferred in
            var input = auto
            input.preferredCloud = preferred
            return ModelRouter.plan(input)?.primary != .codexPlan
        }
        T.checkTrue("Auto never picks the OpenAI plan, with every cloud key and a local server", never)
    }

    // MARK: - http-errors.json

    static func httpErrorCases() {
        T.section("http-errors.json")
        for c in T.fixture("http-errors.json")["cases"] as! [[String: Any]] {
            let status = c["status"] as! Int
            // A body is an object, a list, a string or null; `.fragmentsAllowed` keeps all of them.
            let body = (c["body"] as Any?).flatMap { $0 is NSNull ? nil : try! JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
            let headers = c["headers"] as! [String: String]
            let got = HTTPErrorRules.classify(status: status, body: body, headers: headers)
            let kind = AIErrorKind(rawValue: c["kind"] as! String)!
            T.check("\(status) → \(kind.rawValue)", "\(got.kind.rawValue) \(got.retryAfter.map(String.init) ?? "nil")",
                    "\(kind.rawValue) \((c["retryAfter"] as? Int).map(String.init) ?? "nil")")
        }

        T.section("HTTPErrorRules.classify never crashes")
        for raw in ["", "not json", "[]", "[1, 2]", "\"boom\"", "null", "{\"error\": []}", "{\"error\": 5}", "{\"error\": null}",
                    "{\"error\": [\"x\"]}", "{\"error\": {\"code\": 402, \"type\": [1], \"message\": {}}}"] {
            T.check("odd body \(raw.isEmpty ? "(empty)" : raw)", HTTPErrorRules.classify(status: 500, body: Data(raw.utf8), headers: [:]).kind, .server)
        }
        T.check("Retry-After: 0 is no value", HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": "0"]).retryAfter, nil)
        T.check("Retry-After: ² is no value", HTTPErrorRules.classify(status: 429, body: nil, headers: ["retry-after": "²"]).retryAfter, nil)
        T.check("Retry-After: ١٢ (Arabic-Indic) is no value", HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": "١٢"]).retryAfter, nil)
        T.check("Retry-After: +5 is no value (Int(\"+5\") alone would accept it)",
                HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": "+5"]).retryAfter, nil)
        T.check("Retry-After: 12 counts", HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": " 12 "]).retryAfter, 12)

        T.section("HTTPErrorRules.error")
        let body = try! JSONSerialization.data(withJSONObject:
            ["error": ["type": "insufficient_quota", "code": "insufficient_quota", "message": "quota"]])
        let e = HTTPErrorRules.error(status: 429, body: body, headers: ["x-request-id": "req_123"])
        T.check("billing keeps its code", e.code, "insufficient_quota")
        T.check("request id captured", e.requestID, "req_123")
        T.check("spend limit is spotted", HTTPErrorRules.isSpendLimit("project_spend_limit_exceeded"), true)
        T.check("quota is not a spend limit", HTTPErrorRules.isSpendLimit("insufficient_quota"), false)
        T.check("a user spend limit is spotted too", HTTPErrorRules.isSpendLimit("user_spend_limit_exceeded"), true)

        T.section("HTTPErrorRules.streamErrorKind (reference.py stream_error_kind)")
        let table: [(AIErrorKind, [String])] = [
            (.rateLimited, ["rate_limit_exceeded", "rate_limit_error"]),
            (.overloaded, ["server_is_overloaded", "slow_down", "overloaded_error"]),
            (.server, ["server_error", "api_error", "timeout_error", "vector_store_timeout"]),
            (.billing, ["insufficient_quota", "credit_balance_exhausted", "organization_usage_limit_exceeded", "billing_error",
                        "project_spend_limit_exceeded", "user_spend_limit_exceeded"]),
            (.refusal, ["invalid_prompt", "image_content_policy_violation", "content_policy_violation", "content_filter"]),
            (.auth, ["authentication_error", "invalid_api_key", "permission_error"]),
            (.badRequest, ["invalid_request_error", "context_length_exceeded", "something_new", "", "SERVER_ERROR"]),
        ]
        for (kind, codes) in table {
            for code in codes { T.check("\(code.isEmpty ? "(empty)" : code) → \(kind.rawValue)", HTTPErrorRules.streamErrorKind(code), kind) }
        }
        T.check("a missing code is bad_request, never server", HTTPErrorRules.streamErrorKind(nil), .badRequest)
        T.checkTrue("only known temporary codes may fall back",
                    ["something_new", "invalid_prompt", "context_length_exceeded", "insufficient_quota"]
                        .allSatisfy { !HTTPErrorRules.streamErrorKind($0).isTemporary })

        T.section("HTTPErrorRules.transportKind")
        T.check("offline", HTTPErrorRules.transportKind(URLError(.notConnectedToInternet)), .offline)
        T.check("refused", HTTPErrorRules.transportKind(URLError(.cannotConnectToHost)), .unreachable)
        T.check("dns", HTTPErrorRules.transportKind(URLError(.cannotFindHost)), .unreachable)
        T.check("timed out", HTTPErrorRules.transportKind(URLError(.timedOut)), .timeout)
        T.check("cancelled", HTTPErrorRules.transportKind(CancellationError()), .cancelled)
    }
}
