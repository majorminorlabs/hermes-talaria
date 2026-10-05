import Foundation

nonisolated struct BotDraft: Sendable {
    var changes: ProfileChanges
}
nonisolated struct BotChoice: Identifiable, Hashable, Sendable {
    var id: String
    var enabled: Bool
}
nonisolated struct BotProvider: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var models: [ModelRef]
}
nonisolated struct BotInventory: Sendable {
    var available: Set<String>
    var providers: [BotProvider]
    var skills: [BotChoice]
    var toolsets: [BotChoice]
    var mcpServers: [BotChoice]
    init(_ j: BridgeJSON) {
        available = Set(j["availability"].object.filter { $0.value.bool == true }.map(\.key))
        providers = j["providers"].array.filter { $0["available"].bool != false }.compactMap { p in
            guard let id = p["id"].string else { return nil }
            return BotProvider(id: id, name: p["name"].string ?? id, models: p["models"].array.compactMap { m in
                guard let model = m["id"].string else { return nil }
                return ModelRef(id: model, displayName: m["name"].string ?? model, provider: id)
            })
        }
        func choices(_ key: String) -> [BotChoice] { j[key].array.compactMap { c in c["name"].string.map { BotChoice(id: $0, enabled: c["enabled"].bool ?? false) } } }
        skills = choices("skills"); toolsets = choices("toolsets"); mcpServers = choices("mcp_servers")
    }
}
