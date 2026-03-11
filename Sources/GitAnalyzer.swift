// GitAnalyzer.swift
// Parses git log output to extract commit data for ROI analysis

import Foundation

// MARK: - Data models

struct GitCommit {
    let hash: String
    let date: Date
    let message: String
    let linesAdded: Int
    let linesDeleted: Int
    let projectPath: String

    var totalLinesChanged: Int { linesAdded + linesDeleted }
}

struct ProjectROI: Identifiable {
    let id = UUID()
    let projectName: String
    let totalCost: Double
    let assistedCommits: Int
    let totalLinesChanged: Int
    let costPerCommit: Double
    let costPerLine: Double
    let modelBreakdown: [(model: String, cost: Double, commits: Int)]
}

struct ROIStats {
    let period: Int
    let totalCost: Double
    let totalAssistedCommits: Int
    let totalLinesChanged: Int
    let costPerCommit: Double
    let costPerLine: Double
    let byProject: [ProjectROI]
    let dailyTrend: [(date: Date, cost: Double, commits: Int)]
    let byModel: [(model: String, cost: Double, avgCostPerCommit: Double)]

    static let empty = ROIStats(
        period: 30, totalCost: 0, totalAssistedCommits: 0,
        totalLinesChanged: 0, costPerCommit: 0, costPerLine: 0,
        byProject: [], dailyTrend: [], byModel: []
    )
}

// MARK: - Git analyzer

enum GitAnalyzer {

    /// Check if git is available on the system
    static func isGitAvailable() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["git"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    /// Get the user's git email for filtering commits
    static func userEmail(in repoPath: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repoPath, "config", "user.email"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Convert a Claude projects directory name to an actual filesystem path
    /// e.g. "-Users-lucascharvolin-Projects-BeeTime" -> "/Users/lucascharvolin/Projects/BeeTime"
    static func actualPath(from dirName: String) -> String {
        let cleaned = dirName.hasPrefix("-") ? String(dirName.dropFirst()) : dirName
        return "/" + cleaned.replacingOccurrences(of: "-", with: "/")
    }

    /// Find the git root for a given path (walks up to find .git)
    static func gitRoot(for path: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path, "rev-parse", "--show-toplevel"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    /// Parse git log for a repository over the last N days
    static func commits(in repoPath: String, sinceDaysAgo days: Int = 30) -> [GitCommit] {
        guard let email = userEmail(in: repoPath) else {
            print("[ClaudeGod] Could not get git email for \(repoPath)")
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = [
            "-C", repoPath, "log",
            "--author=\(email)",
            "--since=\(days) days ago",
            "--format=COMMIT_START%H|%aI|%s",
            "--numstat"
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return [] }
        } catch {
            return []
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let output = String(data: data, encoding: .utf8), !output.isEmpty else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var commits: [GitCommit] = []
        var currentHash = ""
        var currentDate: Date?
        var currentMessage = ""
        var currentAdded = 0
        var currentDeleted = 0

        output.enumerateLines { line, _ in
            if line.hasPrefix("COMMIT_START") {
                // Save previous commit if exists
                if !currentHash.isEmpty, let date = currentDate {
                    commits.append(GitCommit(
                        hash: currentHash, date: date, message: currentMessage,
                        linesAdded: currentAdded, linesDeleted: currentDeleted,
                        projectPath: repoPath
                    ))
                }
                let content = String(line.dropFirst("COMMIT_START".count))
                let parts = content.split(separator: "|", maxSplits: 2)
                guard parts.count >= 2 else { return }
                currentHash = String(parts[0])
                currentDate = isoFormatter.date(from: String(parts[1]))
                currentMessage = parts.count >= 3 ? String(parts[2]) : ""
                currentAdded = 0
                currentDeleted = 0
            } else if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                // numstat line: "added\tdeleted\tfilename"
                let fields = line.split(separator: "\t")
                if fields.count >= 2 {
                    currentAdded += Int(fields[0]) ?? 0
                    currentDeleted += Int(fields[1]) ?? 0
                }
            }
        }
        // Don't forget last commit
        if !currentHash.isEmpty, let date = currentDate {
            commits.append(GitCommit(
                hash: currentHash, date: date, message: currentMessage,
                linesAdded: currentAdded, linesDeleted: currentDeleted,
                projectPath: repoPath
            ))
        }

        return commits
    }

    /// Fetch commits from all known Claude project directories
    static func allCommits(sinceDaysAgo days: Int = 30) -> [GitCommit] {
        let fm = FileManager.default
        guard let projectDirs = try? fm.contentsOfDirectory(
            at: SessionAnalyzer.projectsDir,
            includingPropertiesForKeys: nil
        ) else { return [] }

        var seenRoots = Set<String>()
        var allCommits: [GitCommit] = []

        for projectDir in projectDirs {
            let dirName = projectDir.lastPathComponent
            let path = actualPath(from: dirName)

            guard fm.fileExists(atPath: path),
                  let root = gitRoot(for: path),
                  !seenRoots.contains(root)
            else { continue }

            seenRoots.insert(root)
            allCommits.append(contentsOf: commits(in: root, sinceDaysAgo: days))
        }

        return allCommits
    }
}
