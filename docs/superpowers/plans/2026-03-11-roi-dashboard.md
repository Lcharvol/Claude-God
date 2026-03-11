# ROI Dashboard Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 4th "ROI" tab that correlates Claude spending with Git commit productivity.

**Architecture:** New `GitAnalyzer.swift` with static functions to parse git log output. Correlation logic in `UsageManager` crosses timeline sessions with git commits. New ROI view section in `MenuBarView`. Popover width increased globally.

**Tech Stack:** Swift, SwiftUI, Process (subprocess for git), existing SessionAnalyzer/UsageManager patterns.

---

## Chunk 1: GitAnalyzer + Data Models

### Task 1: Create GitAnalyzer with data models

**Files:**
- Create: `Sources/GitAnalyzer.swift`

- [ ] **Step 1: Create `Sources/GitAnalyzer.swift` with data models and git log parsing**

```swift
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
    /// Uses --numstat for lines added/deleted and a custom format for structured parsing
    static func commits(in repoPath: String, sinceDaysAgo days: Int = 30) -> [GitCommit] {
        guard let email = userEmail(in: repoPath) else {
            print("[ClaudeGod] Could not get git email for \(repoPath)")
            return []
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        // Format: COMMIT_START<hash>|<iso-date>|<subject>\n<numstat lines>
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
                // Parse new commit header
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

        // Deduplicate git roots (multiple Claude dirs may share the same repo)
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `xcodegen generate && xcodebuild -scheme ClaudeGod -configuration Release build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/GitAnalyzer.swift
git commit -m "feat: add GitAnalyzer with git log parsing and data models"
```

## Chunk 2: ROI Correlation Logic in UsageManager

### Task 2: Add ROI state and correlation logic

**Files:**
- Modify: `Sources/UsageManager.swift` (Tab enum, published state, correlation method)

- [ ] **Step 1: Add `roi` case to Tab enum (line ~219)**

Change:
```swift
enum Tab: Int { case usage, analytics, timeline }
```
To:
```swift
enum Tab: Int { case usage, analytics, timeline, roi }
```

- [ ] **Step 2: Add ROI published state near other timeline state (~line 275)**

Add after `isLoadingTimeline`:
```swift
@Published var roiStats: ROIStats = .empty
@Published var isLoadingROI = false
@Published var isGitAvailable = false
```

- [ ] **Step 3: Add git availability check in `startMonitoring()` or init**

Add in the `startMonitoring()` method:
```swift
isGitAvailable = GitAnalyzer.isGitAvailable()
```

- [ ] **Step 4: Add `refreshROI()` method after the Timeline section (~line 628)**

```swift
// MARK: - ROI

func refreshROI() {
    guard isGitAvailable else { return }
    isLoadingROI = true
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        let stats = Self.computeROI()
        DispatchQueue.main.async {
            self?.roiStats = stats
            self?.isLoadingROI = false
        }
    }
}

private static let assistedWindowSeconds: TimeInterval = 2 * 60 * 60 // 2 hours

private static func computeROI() -> ROIStats {
    let days = 30
    let cal = Calendar.current
    guard let since = cal.date(byAdding: .day, value: -days, to: Date()) else { return .empty }

    // Get all commits and all sessions for the period
    let allCommits = GitAnalyzer.allCommits(sinceDaysAgo: days)
    guard !allCommits.isEmpty else { return .empty }

    // Get all sessions for the last 30 days (one day at a time)
    var allSessions: [TimelineSession] = []
    for dayOffset in 0..<days {
        guard let date = cal.date(byAdding: .day, value: -dayOffset, to: Date()) else { continue }
        allSessions.append(contentsOf: SessionAnalyzer.timelineSessions(for: date))
    }

    // Determine which commits are Claude-assisted
    // A commit is assisted if it falls within session.startTime...session.endTime+2h
    // and the commit's repo path matches the session's project
    let assistedCommits = allCommits.filter { commit in
        allSessions.contains { session in
            let windowEnd = session.endTime.addingTimeInterval(assistedWindowSeconds)
            let inTimeWindow = commit.date >= session.startTime && commit.date <= windowEnd
            // Match project: commit.projectPath should contain the session project name
            let projectMatch = commit.projectPath.lowercased().contains(session.projectName.lowercased())
            return inTimeWindow && projectMatch
        }
    }

    let totalCost = allSessions.reduce(0.0) { $0 + $1.cost }
    let totalLines = assistedCommits.reduce(0) { $0 + $1.totalLinesChanged }
    let costPerCommit = assistedCommits.isEmpty ? 0 : totalCost / Double(assistedCommits.count)
    let costPerLine = totalLines == 0 ? 0 : totalCost / Double(totalLines)

    // By project
    let commitsByProject = Dictionary(grouping: assistedCommits, by: { $0.projectPath })
    let sessionsByProject = Dictionary(grouping: allSessions, by: { $0.projectName.lowercased() })

    let byProject: [ProjectROI] = commitsByProject.map { (path, commits) in
        let projectName = path.split(separator: "/").last.map(String.init) ?? path
        let projectSessions = sessionsByProject.first { path.lowercased().contains($0.key) }?.value ?? []
        let projCost = projectSessions.reduce(0.0) { $0 + $1.cost }
        let projLines = commits.reduce(0) { $0 + $1.totalLinesChanged }

        // Model breakdown from sessions
        var modelMap: [String: (cost: Double, commits: Int)] = [:]
        for session in projectSessions {
            for msg in session.messages {
                let model = msg.model.contains("opus") ? "Opus" :
                           msg.model.contains("sonnet") ? "Sonnet" :
                           msg.model.contains("haiku") ? "Haiku" : msg.model
                modelMap[model, default: (0, 0)].cost += msg.cost
            }
        }
        // Distribute commits proportionally across models
        let totalModelCost = modelMap.values.reduce(0.0) { $0 + $1.cost }
        let breakdown = modelMap.map { (model, data) in
            let proportion = totalModelCost > 0 ? data.cost / totalModelCost : 0
            return (model: model, cost: data.cost, commits: Int(Double(commits.count) * proportion))
        }

        return ProjectROI(
            projectName: projectName,
            totalCost: projCost,
            assistedCommits: commits.count,
            totalLinesChanged: projLines,
            costPerCommit: commits.isEmpty ? 0 : projCost / Double(commits.count),
            costPerLine: projLines == 0 ? 0 : projCost / Double(projLines),
            modelBreakdown: breakdown
        )
    }.sorted { $0.totalCost > $1.totalCost }

    // Daily trend
    let dailyTrend: [(date: Date, cost: Double, commits: Int)] = (0..<days).compactMap { offset in
        guard let date = cal.date(byAdding: .day, value: -offset, to: Date()) else { return nil }
        let dayStart = cal.startOfDay(for: date)
        guard let dayEnd = cal.date(byAdding: .day, value: 1, to: dayStart) else { return nil }
        let dayCost = allSessions.filter { $0.startTime >= dayStart && $0.startTime < dayEnd }
            .reduce(0.0) { $0 + $1.cost }
        let dayCommits = assistedCommits.filter { $0.date >= dayStart && $0.date < dayEnd }.count
        return (date: dayStart, cost: dayCost, commits: dayCommits)
    }.reversed()

    // By model
    var globalModelMap: [String: (cost: Double, commits: Double)] = [:]
    for proj in byProject {
        for bd in proj.modelBreakdown {
            globalModelMap[bd.model, default: (0, 0)].cost += bd.cost
            globalModelMap[bd.model, default: (0, 0)].commits += Double(bd.commits)
        }
    }
    let byModel = globalModelMap.map { (model, data) in
        let avgCPC = data.commits > 0 ? data.cost / data.commits : 0
        return (model: model, cost: data.cost, avgCostPerCommit: avgCPC)
    }.sorted { $0.cost > $1.cost }

    return ROIStats(
        period: days,
        totalCost: totalCost,
        totalAssistedCommits: assistedCommits.count,
        totalLinesChanged: totalLines,
        costPerCommit: costPerCommit,
        costPerLine: costPerLine,
        byProject: byProject,
        dailyTrend: Array(dailyTrend),
        byModel: byModel
    )
}
```

- [ ] **Step 5: Build to verify compilation**

Run: `xcodegen generate && xcodebuild -scheme ClaudeGod -configuration Release build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageManager.swift
git commit -m "feat: add ROI correlation logic — crosses git commits with Claude sessions"
```

## Chunk 3: ROI View + Popover Resize

### Task 3: Widen popover globally

**Files:**
- Modify: `Sources/MenuBarView.swift` (line ~86)

- [ ] **Step 1: Change popover width**

Change line 86:
```swift
.frame(width: manager.compactMode && !manager.showSettings && manager.selectedTab == .usage ? 280 : 340)
```
To:
```swift
.frame(width: manager.compactMode && !manager.showSettings && manager.selectedTab == .usage ? 280 : 380)
```

- [ ] **Step 2: Commit**

```bash
git add Sources/MenuBarView.swift
git commit -m "feat: widen popover from 340px to 380px for all tabs"
```

### Task 4: Add ROI tab button and keyboard shortcut

**Files:**
- Modify: `Sources/MenuBarView.swift`

- [ ] **Step 1: Add ROI tab button after the Timeline tab (~line 161)**

After:
```swift
SHTab(label: "Timeline", isActive: manager.selectedTab == .timeline) {
    manager.selectedTab = .timeline
}
```
Add:
```swift
SHTab(label: "ROI", isActive: manager.selectedTab == .roi) {
    manager.selectedTab = .roi
    if manager.roiStats.totalAssistedCommits == 0 {
        manager.refreshROI()
    }
}
```

- [ ] **Step 2: Add ROI view in the main body conditional (~line 56-58)**

After:
```swift
} else if manager.selectedTab == .timeline {
```
Add the ROI case:
```swift
} else if manager.selectedTab == .roi {
    roiView
```

- [ ] **Step 3: Update keyboard shortcut hint (~line 467)**

Change:
```swift
Text("⌥⌘C Toggle · ⌘R Refresh · ⌘1 Usage · ⌘2 Analytics · ⌘3 Timeline")
```
To:
```swift
Text("⌥⌘C Toggle · ⌘R Refresh · ⌘1 Usage · ⌘2 Analytics · ⌘3 Timeline · ⌘4 ROI")
```

- [ ] **Step 4: Add ⌘4 keyboard shortcut**

Find where ⌘1/⌘2/⌘3 shortcuts are handled and add ⌘4:
```swift
.keyboardShortcut("4", modifiers: .command)
// handler: manager.selectedTab = .roi; manager.refreshROI()
```

- [ ] **Step 5: Commit**

```bash
git add Sources/MenuBarView.swift
git commit -m "feat: add ROI tab button with ⌘4 shortcut"
```

### Task 5: Build the ROI view

**Files:**
- Modify: `Sources/MenuBarView.swift`

- [ ] **Step 1: Add the `roiView` computed property**

Add as a new `@ViewBuilder` computed property in the main view struct:

```swift
// MARK: - ROI View

@ViewBuilder
private var roiView: some View {
    if !manager.isGitAvailable {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 24))
                .foregroundColor(.orange)
            Text("Git not found")
                .font(.system(size: 13, weight: .semibold))
            Text("Install Git to see your ROI metrics.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    } else if manager.isLoadingROI {
        VStack(spacing: 8) {
            ProgressView()
            Text("Analyzing git history...")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    } else if manager.roiStats.totalAssistedCommits == 0 {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
            Text("No data yet")
                .font(.system(size: 13, weight: .semibold))
            Text("Use Claude Code and commit to see your ROI.\nCommits within 2h of a session are tracked.")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    } else {
        roiContent
    }
}

@ViewBuilder
private var roiContent: some View {
    let stats = manager.roiStats
    VStack(alignment: .leading, spacing: 12) {
        // Header stat cards
        HStack(spacing: 8) {
            SHStatCard(label: "Cost (30d)", value: formatCostCompact(stats.totalCost), sub: "\(stats.period) days")
            SHStatCard(label: "Commits", value: "\(stats.totalAssistedCommits)", sub: "\(stats.totalLinesChanged) lines")
            SHStatCard(label: "$/commit", value: formatCostCompact(stats.costPerCommit), sub: formatCostCompact(stats.costPerLine) + "/line")
        }

        // Daily trend sparkline (bars = commits, conceptual)
        if !stats.dailyTrend.isEmpty {
            SHCard {
                VStack(alignment: .leading, spacing: 6) {
                    SHLabel("30-day trend")
                    roiSparkline(data: stats.dailyTrend)
                }
            }
        }

        // By project
        if !stats.byProject.isEmpty {
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Projects")
                    ForEach(stats.byProject.prefix(5)) { project in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Theme.accent)
                                .frame(width: 3, height: 20)
                            Text(project.projectName)
                                .font(.system(size: 11, weight: .medium))
                                .lineLimit(1)
                            Spacer()
                            Text("\(project.assistedCommits) commits")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(formatCostCompact(project.costPerCommit) + "/c")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .fixedSize()
                        }
                    }
                }
            }
        }

        // By model
        if !stats.byModel.isEmpty {
            SHCard {
                VStack(alignment: .leading, spacing: 8) {
                    SHLabel("Model efficiency")
                    ForEach(Array(stats.byModel.enumerated()), id: \.offset) { _, entry in
                        HStack {
                            Circle()
                                .fill(modelColor(entry.model))
                                .frame(width: 8, height: 8)
                            Text(entry.model)
                                .font(.system(size: 11, weight: .medium))
                                .frame(width: 50, alignment: .leading)
                            Spacer()
                            Text(formatCostCompact(entry.cost))
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Text(formatCostCompact(entry.avgCostPerCommit) + "/commit")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .fixedSize()
                        }
                    }
                }
            }
        }

        // Trend summary
        roiTrendSummary(stats: stats)
    }
}

private func roiSparkline(data: [(date: Date, cost: Double, commits: Int)]) -> some View {
    let maxCommits = data.map(\.commits).max() ?? 1
    return HStack(alignment: .bottom, spacing: 1) {
        ForEach(Array(data.enumerated()), id: \.offset) { _, entry in
            let height = maxCommits > 0 ? CGFloat(entry.commits) / CGFloat(maxCommits) : 0
            RoundedRectangle(cornerRadius: 1)
                .fill(entry.commits > 0 ? Theme.accent.opacity(0.7) : Color.clear)
                .frame(height: max(2, height * 40))
        }
    }
    .frame(height: 44)
}

@ViewBuilder
private func roiTrendSummary(stats: ROIStats) -> some View {
    let trend = stats.dailyTrend
    guard trend.count >= 10 else { return }
    let mid = trend.count / 2
    let firstHalf = trend[0..<mid]
    let secondHalf = trend[mid...]
    let firstCommits = firstHalf.reduce(0) { $0 + $1.commits }
    let secondCommits = secondHalf.reduce(0) { $0 + $1.commits }
    let firstCost = firstHalf.reduce(0.0) { $0 + $1.cost }
    let secondCost = secondHalf.reduce(0.0) { $0 + $1.cost }
    let firstCPC = firstCommits > 0 ? firstCost / Double(firstCommits) : 0
    let secondCPC = secondCommits > 0 ? secondCost / Double(secondCommits) : 0

    if firstCPC > 0 {
        let pctChange = ((secondCPC - firstCPC) / firstCPC) * 100
        let improved = pctChange < 0
        HStack {
            Image(systemName: improved ? "arrow.down.right" : "arrow.up.right")
                .font(.system(size: 10))
                .foregroundColor(improved ? .green : .orange)
            Text("Cost/commit \(improved ? "decreased" : "increased") \(String(format: "%.0f", abs(pctChange)))% this month")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }
}
```

Note: `modelColor()` already exists in MenuBarView for the Timeline tab — reuse it. `SHStatCard`, `SHCard`, `SHLabel` are existing helper views. `formatCostCompact()` already exists.

- [ ] **Step 2: Build to verify compilation**

Run: `xcodegen generate && xcodebuild -scheme ClaudeGod -configuration Release build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"`
Expected: BUILD SUCCEEDED

- [ ] **Step 3: Commit**

```bash
git add Sources/MenuBarView.swift
git commit -m "feat: add ROI view with project/model breakdown, sparkline, and trend"
```

## Chunk 4: Final Integration + Deploy

### Task 6: Build, test, deploy

- [ ] **Step 1: Full build**

```bash
xcodegen generate && xcodebuild -scheme ClaudeGod -configuration Release build
```

- [ ] **Step 2: Copy to Applications and test manually**

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/ClaudeGod-*/Build/Products/Release/Claude\ God.app /Applications/
```

Launch the app, navigate to ROI tab, verify:
- Stat cards show data
- Projects list is populated
- Model breakdown shows Opus/Sonnet/Haiku
- Sparkline renders
- Empty state shows correctly for projects without Git
- Popover is wider across all tabs

- [ ] **Step 3: Final commit and push**

```bash
git add -A
git commit -m "feat: ROI dashboard — correlate Claude spending with Git productivity"
git push
```
