import SwiftUI

/// Settings → AI → Add server…: a URL and an optional key, checked before it is saved.
struct AddServerSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (_ name: String, _ baseURL: String, _ key: String?) -> Void

    @State private var url = ""
    @State private var key = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a server").font(.headline)
            Text("An OpenAI-compatible server on this Mac or your network (Ollama, LM Studio, llama.cpp…).")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("http://studio-pc.local:1234", text: $url)
                .textFieldStyle(.roundedBorder)
            SecureField("API key (optional)", text: $key)
                .textFieldStyle(.roundedBorder)
            if let error {
                Text(error).font(.system(size: 11)).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button(checking ? "Checking…" : "Add") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(checking || url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func add() {
        let base = AIURL.normalise(url)
        guard let parsed = URL(string: base), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = parsed.host else {
            error = "Use an http:// or https:// address."
            return
        }
        checking = true
        error = nil
        let apiKey = key.isEmpty ? nil : key
        let target = ProbeTarget(serverID: "new", provider: .custom, name: host, baseURL: base, apiKey: apiKey)
        Task {
            let found = await Discovery.probe(target, installed: true, timeout: AICatalog.Timeouts.connectLocal,
                                              session: .shared)
            checking = false
            if case .running = found.status {
                onAdd(host, base, apiKey)
                isPresented = false
            } else {
                error = "Couldn't reach a model server at \(base)."
            }
        }
    }
}
