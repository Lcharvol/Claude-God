// SessionAnalyzer.swift
// Parse les fichiers JSONL de Claude Code pour calculer l'utilisation et les coûts

import Foundation

// MARK: - Pricing ($/token)

enum ModelPricing {
    struct Price {
        let input: Double
        let output: Double
        let cacheCreation: Double
        let cacheRead: Double
    }

    // Pricing as of 2025 — covers Claude 3.x, 3.5, and 4.x families
    // Model strings use contains() matching so "opus" matches both claude-3-opus and claude-opus-4
    static func price(for model: String) -> Price {
        let m = model.lowercased()
        if m.contains("opus") {
            return Price(input: 15.0 / 1_000_000, output: 75.0 / 1_000_000,
                         cacheCreation: 18.75 / 1_000_000, cacheRead: 1.50 / 1_000_000)
        }
        if m.contains("sonnet") {
            return Price(input: 3.0 / 1_000_000, output: 15.0 / 1_000_000,
                         cacheCreation: 3.75 / 1_000_000, cacheRead: 0.30 / 1_000_000)
        }
        if m.contains("haiku") {
            return Price(input: 0.80 / 1_000_000, output: 4.0 / 1_000_000,
                         cacheCreation: 1.0 / 1_000_000, cacheRead: 0.08 / 1_000_000)
        }
        // Default to Sonnet pricing for unknown models
        return Price(input: 3.0 / 1_000_000, output: 15.0 / 1_000_000,
                     cacheCreation: 3.75 / 1_000_000, cacheRead: 0.30 / 1_000_000)
    }
}

// MARK: - JSONL Codable models

private struct JSONLEntry: Decodable {
    let type: String?
    let timestamp: String?
    let message: JSONLMessage?
}

private struct JSONLMessage: Decodable {
    let model: String?
    let usage: JSONLUsage?
}

private struct JSONLUsage: Decodable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?
    let cacheReadInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }
}

// MARK: - Data models

struct TokenUsage {
    var inputTokens: Int = 0
    var outputTokens: Int = 0
    var cacheCreationTokens: Int = 0
    var cacheReadTokens: Int = 0

    var totalTokens: Int { inputTokens + outputTokens + cacheCreationTokens + cacheReadTokens }

    mutating func add(_ other: TokenUsage) {
        inputTokens += other.inputTokens
        outputTokens += other.outputTokens
        cacheCreationTokens += other.cacheCreationTokens
        cacheReadTokens += other.cacheReadTokens
    }
}

struct ModelUsage: Identifiable {
    let id = UUID()
    let model: String
    var tokens: TokenUsage
    var cost: Double

    var shortName: String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return model
    }
}

struct DailyUsage: Identifiable {
    let id = UUID()
    let date: Date
    var tokens: TokenUsage
    var cost: Double
    var messageCount: Int

    var dateLabel: String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return SessionAnalyzer.dayLabelFormatter.string(from: date)
    }
}

struct UsageStats {
    var totalCost: Double = 0
    var totalTokens: TokenUsage = TokenUsage()
    var totalMessages: Int = 0
    var byModel: [ModelUsage] = []
    var daily: [DailyUsage] = []
}

// MARK: - Analyzer

class SessionAnalyzer {

    // Static formatters (avoid recreating per call)
    static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let jsonDecoder: JSONDecoder = {
        JSONDecoder()
    }()

    private static let projectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    /// Analyse tous les fichiers JSONL pour une période donnée
    static func analyze(since: Date, until: Date = Date()) -> UsageStats {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else {
            print("[ClaudeGod] No projects directory found")
            return UsageStats()
        }

        var modelAgg: [String: (tokens: TokenUsage, cost: Double)] = [:]
        var dailyAgg: [String: (date: Date, tokens: TokenUsage, cost: Double, count: Int)] = [:]
        var totalMessages = 0

        let cal = Calendar.current

        for projectDir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                // Skip files older than our window (quick check via modification date)
                if let attrs = try? fm.attributesOfItem(atPath: file.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < since {
                    continue
                }

                guard let data = try? Data(contentsOf: file),
                      let content = String(data: data, encoding: .utf8)
                else { continue }

                // Use enumerateLines for memory-efficient line-by-line processing
                content.enumerateLines { line, _ in
                    guard !line.isEmpty,
                          let lineData = line.data(using: .utf8),
                          let entry = try? jsonDecoder.decode(JSONLEntry.self, from: lineData)
                    else { return }

                    guard entry.type == "assistant",
                          let message = entry.message,
                          let usage = message.usage,
                          let model = message.model,
                          model != "<synthetic>"
                    else { return }

                    // Parse timestamp
                    guard let timestampStr = entry.timestamp,
                          let timestamp = isoFormatter.date(from: timestampStr)
                              ?? isoFormatterNoFrac.date(from: timestampStr)
                    else { return }

                    // Filter by date range
                    guard timestamp >= since, timestamp <= until else { return }

                    // Parse token counts
                    let inputTokens = usage.inputTokens ?? 0
                    let outputTokens = usage.outputTokens ?? 0
                    let cacheCreation = usage.cacheCreationInputTokens ?? 0
                    let cacheRead = usage.cacheReadInputTokens ?? 0

                    let tokens = TokenUsage(
                        inputTokens: inputTokens,
                        outputTokens: outputTokens,
                        cacheCreationTokens: cacheCreation,
                        cacheReadTokens: cacheRead
                    )

                    // Calculate cost
                    let price = ModelPricing.price(for: model)
                    let cost = Double(inputTokens) * price.input
                        + Double(outputTokens) * price.output
                        + Double(cacheCreation) * price.cacheCreation
                        + Double(cacheRead) * price.cacheRead

                    // Aggregate by model
                    var existing = modelAgg[model] ?? (tokens: TokenUsage(), cost: 0)
                    existing.tokens.add(tokens)
                    existing.cost += cost
                    modelAgg[model] = existing

                    // Aggregate by day
                    let dayKey = dayKeyFormatter.string(from: timestamp)
                    let dayStart = cal.startOfDay(for: timestamp)
                    var dayExisting = dailyAgg[dayKey] ?? (date: dayStart, tokens: TokenUsage(), cost: 0, count: 0)
                    dayExisting.tokens.add(tokens)
                    dayExisting.cost += cost
                    dayExisting.count += 1
                    dailyAgg[dayKey] = dayExisting

                    totalMessages += 1
                }
            }
        }

        // Build results
        let byModel = modelAgg.map { ModelUsage(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.cost > $1.cost }

        let daily = dailyAgg.values
            .map { DailyUsage(date: $0.date, tokens: $0.tokens, cost: $0.cost, messageCount: $0.count) }
            .sorted { $0.date > $1.date }

        var totalTokens = TokenUsage()
        for m in modelAgg.values { totalTokens.add(m.tokens) }
        let totalCost = modelAgg.values.reduce(0) { $0 + $1.cost }

        return UsageStats(
            totalCost: totalCost,
            totalTokens: totalTokens,
            totalMessages: totalMessages,
            byModel: byModel,
            daily: daily
        )
    }
}
