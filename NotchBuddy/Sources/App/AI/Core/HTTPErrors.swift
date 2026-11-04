import Foundation

/// HTTP status + body → error kind, exactly as `tests/fixtures/ai/reference.py` `classify_http`.
enum HTTPErrorRules {
    static let billingCodes: Set<String> = [
        "insufficient_quota", "credit_balance_exhausted", "organization_usage_limit_exceeded", "billing_error",
    ]

    /// A billing code: the set above, or any `*_spend_limit_exceeded` (organization, project, user…).
    static func isBilling(_ code: String?) -> Bool {
        guard let code else { return false }
        return billingCodes.contains(code) || code.hasSuffix("_spend_limit_exceeded")
    }

    /// Rules in order: billing marker or 402, 401/403, 400/404/413/422, 429, 503/529, other 5xx, anything else.
    static func classify(status: Int, body: Data?, headers: [String: String]) -> (kind: AIErrorKind, retryAfter: Int?) {
        let err = errorObject(body)
        let message = (err["message"] as? String ?? "").lowercased()
        let retry = retryAfter(headers)
        if isBilling(err["code"] as? String) || isBilling(err["type"] as? String) || status == 402
            || message.contains("credit balance") {
            return (.billing, retry)
        }
        switch status {
        case 401, 403: return (.auth, retry)
        case 400, 404, 413, 422: return (.badRequest, retry)
        case 429: return (.rateLimited, retry)
        case 503, 529: return (.overloaded, retry)
        case 500..<600: return (.server, retry)
        default: return (.badRequest, retry)
        }
    }

    /// The full error: kind, Retry-After, code, message and request ID.
    static func error(status: Int, body: Data?, headers: [String: String]) -> AIError {
        let (kind, retry) = classify(status: status, body: body, headers: headers)
        let err = errorObject(body)
        let code = (err["code"] as? String) ?? (err["type"] as? String)
        return AIError(kind: kind, status: status, retryAfter: retry, code: code,
                       message: err["message"] as? String,
                       requestID: header("x-request-id", in: headers) ?? header("request-id", in: headers))
    }

    /// OpenAI's spend and usage caps (as opposed to running out of credit).
    static func isSpendLimit(_ code: String?) -> Bool {
        guard let code else { return false }
        return code.hasSuffix("_spend_limit_exceeded") || code == "organization_usage_limit_exceeded"
    }

    private static let streamKinds: [String: AIErrorKind] = [
        "rate_limit_exceeded": .rateLimited, "rate_limit_error": .rateLimited,
        "server_is_overloaded": .overloaded, "slow_down": .overloaded, "overloaded_error": .overloaded,
        "server_error": .server, "api_error": .server, "timeout_error": .server, "vector_store_timeout": .server,
        "invalid_prompt": .refusal, "image_content_policy_violation": .refusal,
        "content_policy_violation": .refusal, "content_filter": .refusal,
        "authentication_error": .auth, "invalid_api_key": .auth, "permission_error": .auth,
    ]

    /// Kind of a mid-stream error: an OpenAI `error.code` or an Anthropic `error.type`.
    /// Only the codes above may be temporary; everything else, a missing code included, is `bad_request`.
    static func streamErrorKind(_ codeOrType: String?) -> AIErrorKind {
        guard let code = codeOrType else { return .badRequest }
        if isBilling(code) { return .billing }
        return streamKinds[code] ?? .badRequest
    }

    /// Network failures before any HTTP status.
    static func transportKind(_ error: Error) -> AIErrorKind {
        if error is CancellationError { return .cancelled }
        guard let url = error as? URLError else { return .unreachable }
        switch url.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .offline
        case .timedOut: return .timeout
        case .cancelled: return .cancelled
        default: return .unreachable
        }
    }

    static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.lowercased() == name }?.value
    }

    /// ASCII digits only (`²` and Arabic-Indic digits are not), and more than 0; otherwise nil.
    private static func retryAfter(_ headers: [String: String]) -> Int? {
        guard let raw = header("retry-after", in: headers)?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
              let seconds = Int(raw), seconds > 0 else { return nil }
        return seconds
    }

    /// `v` itself if an object, its first element if a list (Google wraps errors in a list), else empty.
    private static func firstObject(_ v: Any?) -> [String: Any] {
        if let list = v as? [Any] { return list.first as? [String: Any] ?? [:] }
        return v as? [String: Any] ?? [:]
    }

    /// The body's `error` object; a string, a number, `null` or bad JSON gives an empty one.
    private static func errorObject(_ body: Data?) -> [String: Any] {
        guard let body, let json = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else { return [:] }
        return firstObject(firstObject(json)["error"])
    }
}
