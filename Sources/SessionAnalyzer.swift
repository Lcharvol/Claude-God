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

    static func price(for model: String) -> Price {
        // https://docs.anthropic.com/en/docs/about-claude/models
        if model.contains("opus") {
            return Price(input: 15.0 / 1_000_000, output: 75.0 / 1_000_000,
                         cacheCreation: 18.75 / 1_000_000, cacheRead: 1.50 / 1_000_000)
        }
        if model.contains("sonnet") {
            return Price(input: 3.0 / 1_000_000, output: 15.0 / 1_000_000,
                         cacheCreation: 3.75 / 1_000_000, cacheRead: 0.30 / 1_000_000)
        }
        if model.contains("haiku") {
            return Price(input: 0.80 / 1_000_000, output: 4.0 / 1_000_000,
                         cacheCreation: 1.0 / 1_000_000, cacheRead: 0.08 / 1_000_000)
        }
        // Default to Sonnet pricing
        return Price(input: 3.0 / 1_000_000, output: 15.0 / 1_000_000,
                     cacheCreation: 3.75 / 1_000_000, cacheRead: 0.30 / 1_000_000)
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
        if model.contains("opus") { return "Opus" }
        if model.contains("sonnet") { return "Sonnet" }
        if model.contains("haiku") { return "Haiku" }
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
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
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
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        for projectDir in projectDirs {
            guard let files = try? fm.contentsOfDirectory(at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                // Skip files older than our window (quick check via modification date)
                if let attrs = try? fm.attributesOfItem(atPath: file.path),
                   let modDate = attrs[.modificationDate] as? Date,
                   modDate < since {
                    continue
                }

                guard let data = try? Data(contentsOf: file) else { continue }
                guard let content = String(data: data, encoding: .utf8) else { continue }

                for line in content.components(separatedBy: .newlines) {
                    guard !line.isEmpty,
                          let lineData = line.data(using: .utf8),
                          let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any]
                    else { continue }

                    guard json["type"] as? String == "assistant",
                          let message = json["message"] as? [String: Any],
                          let usage = message["usage"] as? [String: Any],
                          let model = message["model"] as? String,
                          model != "<synthetic>"
                    else { continue }

                    // Parse timestamp
                    guard let timestampStr = json["timestamp"] as? String,
                          let timestamp = isoFormatter.date(from: timestampStr)
                              ?? isoFormatterNoFrac.date(from: timestampStr)
                    else { continue }

                    // Filter by date range
                    guard timestamp >= since, timestamp <= until else { continue }

                    // Parse token counts
                    let inputTokens = usage["input_tokens"] as? Int ?? 0
                    let outputTokens = usage["output_tokens"] as? Int ?? 0
                    let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
                    let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0

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
                    let dayKey = dateFormatter.string(from: timestamp)
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
