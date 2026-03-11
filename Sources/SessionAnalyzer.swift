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

struct ProjectUsage: Identifiable {
    let id = UUID()
    let projectName: String
    let directoryName: String
    var totalCost: Double
    var totalMessages: Int
    var sessionCount: Int
}

struct SessionInfo: Identifiable {
    let id = UUID()
    let projectName: String
    let topic: String
    let startTime: Date
    let duration: TimeInterval
    let cost: Double
    let messageCount: Int
    let primaryModel: String

    var durationLabel: String {
        let minutes = Int(duration) / 60
        if minutes < 1 { return "<1m" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "\(hours)h \(mins)m"
    }

    var timeLabel: String {
        SessionAnalyzer.timeLabelFormatter.string(from: startTime)
    }
}

struct UsageStats {
    var totalCost: Double = 0
    var totalTokens: TokenUsage = TokenUsage()
    var totalMessages: Int = 0
    var sessionCount: Int = 0
    var byModel: [ModelUsage] = []
    var daily: [DailyUsage] = []
    var byProject: [ProjectUsage] = []

    /// Derive a sub-period from the full analysis (avoids re-scanning files)
    func filtered(since: Date) -> UsageStats {
        let sinceDay = Calendar.current.startOfDay(for: since)
        let filteredDaily = daily.filter { $0.date >= sinceDay }
        return UsageStats(
            totalCost: filteredDaily.reduce(0) { $0 + $1.cost },
            totalTokens: filteredDaily.reduce(into: TokenUsage()) { $0.add($1.tokens) },
            totalMessages: filteredDaily.reduce(0) { $0 + $1.messageCount },
            sessionCount: 0,
            byModel: [],
            daily: filteredDaily,
            byProject: []
        )
    }
}

// MARK: - Analyzer

class SessionAnalyzer {

    // Static formatters (avoid recreating per call)
    static let dayLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    static let timeLabelFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let dayKeyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    static let isoFormatterNoFrac: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let jsonDecoder: JSONDecoder = {
        JSONDecoder()
    }()

    static let projectsDir: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects")
    }()

    static func parseISO(_ string: String) -> Date? {
        isoFormatter.date(from: string) ?? isoFormatterNoFrac.date(from: string)
    }

    /// Extract a short project name from the encoded directory name
    static func projectName(from dirName: String) -> String {
        // Directory names are like: -Users-lucas-Projects-myapp
        // Try to find the last meaningful segment after "Projects-" or similar
        let name = dirName.hasPrefix("-") ? String(dirName.dropFirst()) : dirName
        if let range = name.range(of: "-Projects-", options: [.backwards, .caseInsensitive]) {
            return String(name[range.upperBound...])
        }
        if let range = name.range(of: "-projects-", options: [.backwards, .caseInsensitive]) {
            return String(name[range.upperBound...])
        }
        // Fallback: last segment
        let parts = name.split(separator: "-")
        if parts.count >= 2 {
            return parts.suffix(2).joined(separator: "-")
        }
        return name
    }

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
        var projectAgg: [String: (name: String, cost: Double, messages: Int, sessions: Int)] = [:]
        var totalMessages = 0
        var sessionFiles = Set<String>()

        let cal = Calendar.current

        for projectDir in projectDirs {
            let dirName = projectDir.lastPathComponent
            let projName = projectName(from: dirName)

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

                var fileHadMatch = false
                var fileMessages = 0
                var fileCost: Double = 0

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

                    guard let timestampStr = entry.timestamp,
                          let timestamp = isoFormatter.date(from: timestampStr)
                              ?? isoFormatterNoFrac.date(from: timestampStr)
                    else { return }

                    guard timestamp >= since, timestamp <= until else { return }

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

                    let price = ModelPricing.price(for: model)
                    let cost = Double(inputTokens) * price.input
                        + Double(outputTokens) * price.output
                        + Double(cacheCreation) * price.cacheCreation
                        + Double(cacheRead) * price.cacheRead

                    var existing = modelAgg[model] ?? (tokens: TokenUsage(), cost: 0)
                    existing.tokens.add(tokens)
                    existing.cost += cost
                    modelAgg[model] = existing

                    let dayKey = dayKeyFormatter.string(from: timestamp)
                    let dayStart = cal.startOfDay(for: timestamp)
                    var dayExisting = dailyAgg[dayKey] ?? (date: dayStart, tokens: TokenUsage(), cost: 0, count: 0)
                    dayExisting.tokens.add(tokens)
                    dayExisting.cost += cost
                    dayExisting.count += 1
                    dailyAgg[dayKey] = dayExisting

                    totalMessages += 1
                    fileHadMatch = true
                    fileMessages += 1
                    fileCost += cost
                }

                if fileHadMatch {
                    sessionFiles.insert(file.lastPathComponent)

                    var projExisting = projectAgg[dirName] ?? (name: projName, cost: 0, messages: 0, sessions: 0)
                    projExisting.cost += fileCost
                    projExisting.messages += fileMessages
                    projExisting.sessions += 1
                    projectAgg[dirName] = projExisting
                }
            }
        }

        let byModel = modelAgg.map { ModelUsage(model: $0.key, tokens: $0.value.tokens, cost: $0.value.cost) }
            .sorted { $0.cost > $1.cost }

        let daily = dailyAgg.values
            .map { DailyUsage(date: $0.date, tokens: $0.tokens, cost: $0.cost, messageCount: $0.count) }
            .sorted { $0.date > $1.date }

        let byProject = projectAgg.map {
            ProjectUsage(projectName: $0.value.name, directoryName: $0.key,
                         totalCost: $0.value.cost, totalMessages: $0.value.messages,
                         sessionCount: $0.value.sessions)
        }.sorted { $0.totalCost > $1.totalCost }

        var totalTokens = TokenUsage()
        for m in modelAgg.values { totalTokens.add(m.tokens) }
        let totalCost = modelAgg.values.reduce(0) { $0 + $1.cost }

        return UsageStats(
            totalCost: totalCost,
            totalTokens: totalTokens,
            totalMessages: totalMessages,
            sessionCount: sessionFiles.count,
            byModel: byModel,
            daily: daily,
            byProject: byProject
        )
    }

    /// Recent sessions with topic, duration, cost
    static func recentSessions(limit: Int = 15) -> [SessionInfo] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: projectsDir, includingPropertiesForKeys: nil
        ) else { return [] }

        // Collect all JSONL files with their modification dates
        var allFiles: [(url: URL, modDate: Date, projectName: String)] = []

        for projectDir in projectDirs {
            let projName = projectName(from: projectDir.lastPathComponent)
            guard let files = try? fm.contentsOfDirectory(
                at: projectDir, includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for file in files where file.pathExtension == "jsonl" {
                if let attrs = try? fm.attributesOfItem(atPath: file.path),
                   let modDate = attrs[.modificationDate] as? Date {
                    allFiles.append((url: file, modDate: modDate, projectName: projName))
                }
            }
        }

        // Sort by most recent first, take top N
        allFiles.sort { $0.modDate > $1.modDate }
        let filesToParse = allFiles.prefix(limit)

        var sessions: [SessionInfo] = []

        for fileInfo in filesToParse {
            guard let data = try? Data(contentsOf: fileInfo.url),
                  let content = String(data: data, encoding: .utf8)
            else { continue }

            var topic = ""
            var firstTimestamp: Date?
            var lastTimestamp: Date?
            var cost: Double = 0
            var messageCount = 0
            var modelCounts: [String: Int] = [:]

            content.enumerateLines { line, stop in
                guard !line.isEmpty,
                      let lineData = line.data(using: .utf8)
                else { return }

                // Try to parse user messages for topic
                if topic.isEmpty,
                   let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                   let type = json["type"] as? String, type == "human",
                   let message = json["message"] as? [String: Any] {
                    if let contentStr = message["content"] as? String {
                        topic = String(contentStr.prefix(100))
                    } else if let contentArr = message["content"] as? [[String: Any]],
                              let first = contentArr.first(where: { $0["type"] as? String == "text" }),
                              let text = first["text"] as? String {
                        topic = String(text.prefix(100))
                    }
                }

                // Parse assistant messages for cost
                if let entry = try? jsonDecoder.decode(JSONLEntry.self, from: lineData),
                   entry.type == "assistant",
                   let message = entry.message,
                   let usage = message.usage,
                   let model = message.model, model != "<synthetic>" {

                    if let ts = entry.timestamp, let date = parseISO(ts) {
                        if firstTimestamp == nil { firstTimestamp = date }
                        lastTimestamp = date
                    }

                    let input = usage.inputTokens ?? 0
                    let output = usage.outputTokens ?? 0
                    let cacheCr = usage.cacheCreationInputTokens ?? 0
                    let cacheRd = usage.cacheReadInputTokens ?? 0

                    let price = ModelPricing.price(for: model)
                    cost += Double(input) * price.input
                        + Double(output) * price.output
                        + Double(cacheCr) * price.cacheCreation
                        + Double(cacheRd) * price.cacheRead

                    messageCount += 1
                    modelCounts[model, default: 0] += 1
                }
            }

            guard messageCount > 0, let start = firstTimestamp else { continue }
            let end = lastTimestamp ?? start
            let primaryModel = modelCounts.max(by: { $0.value < $1.value })?.key ?? ""

            // Clean topic
            let cleanTopic = topic
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            let displayTopic = cleanTopic.isEmpty ? "Untitled session" : cleanTopic

            sessions.append(SessionInfo(
                projectName: fileInfo.projectName,
                topic: displayTopic,
                startTime: start,
                duration: end.timeIntervalSince(start),
                cost: cost,
                messageCount: messageCount,
                primaryModel: ModelPricing.shortName(for: primaryModel)
            ))
        }

        return sessions.sorted { $0.startTime > $1.startTime }
    }
}

// MARK: - Model short name helper

extension ModelPricing {
    static func shortName(for model: String) -> String {
        let m = model.lowercased()
        if m.contains("opus") { return "Opus" }
        if m.contains("sonnet") { return "Sonnet" }
        if m.contains("haiku") { return "Haiku" }
        return model
    }
}
