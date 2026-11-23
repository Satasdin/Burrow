import CryptoKit
import Foundation

/// A conversation's working memory on a llama.cpp server, kept on the shelf between runs (D-118). After each reply the
/// slot is saved; when the conversation, or a session resumed from CAMR's archive, is opened again, the slot is loaded
/// and the model reads only the new message. Measured on Qwen3 4B with an 8,600-token history: 7.32 s to the first word
/// reading it all again, 0.49 s with the cache loaded in 0.04 s.
///
/// A cache only fits the model that made it, so each is filed under the model the server reports. It is a speed-up only:
/// a cache that can't be loaded is skipped and the history is read as text, as it would be without CAMR.
extension KVShelf {
    public static func chatKey(conversation: String) -> String {
        let clean = conversation.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
        return "chat-" + String(String(String.UnicodeScalarView(clean)).prefix(40))
    }

    /// Loads the conversation's saved cache into the server's slot, when there is one for the server's model. Returns how
    /// many tokens were loaded and how long it took, or nil when there was none to load.
    public func restoreChat(conversation: String, server: URL, slot: Int = 0) async -> (tokens: Int, seconds: Double)? {
        let llama = LlamaServer(base: server, slotID: slot)
        guard let model = try? await llama.model() else { return nil }
        let key = Self.chatKey(conversation: conversation)
        guard var entry = entries().first(where: { $0.key == key && $0.model == model }),
              FileManager.default.fileExists(atPath: folder.appendingPathComponent(entry.file).path) else { return nil }
        let started = Date()
        guard let out = try? await llama.call("/slots/\(slot)?action=restore", ["filename": entry.file]) else { return nil }
        entry.lastUsed = Date()
        try? write(entries().filter { !($0.key == key && $0.model == model) } + [entry])
        return (out["n_restored"] as? Int ?? entry.tokens, Date().timeIntervalSince(started))
    }

    /// Saves the slot as the conversation's cache, replacing the one before, and trims the shelf to its limit.
    @discardableResult
    public func saveChat(conversation: String, server: URL, slot: Int = 0, limitBytes: Int = 12_000_000_000) async -> Entry? {
        let llama = LlamaServer(base: server, slotID: slot)
        guard let model = try? await llama.model() else { return nil }
        let key = Self.chatKey(conversation: conversation)
        let file = key + "-" + SHA256.hash(data: Data(model.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined() + ".bin"
        let started = Date()
        guard let out = try? await llama.call("/slots/\(slot)?action=save", ["filename": file]) else { return nil }
        let bytes = (try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(file).path)[.size] as? Int) ?? (out["n_written"] as? Int ?? 0)
        let entry = Entry(key: key, model: model, file: file, sources: [:], tokens: out["n_saved"] as? Int ?? 0, bytes: bytes,
                          buildSeconds: Date().timeIntervalSince(started), created: Date(), lastUsed: Date())
        try? write(entries().filter { !($0.key == key && $0.model == model) } + [entry])
        _ = try? trim(toBytes: limitBytes, keeping: [key])
        return entry
    }
}
