# ROI Dashboard — Design Spec

## Overview

A new "ROI" tab in Claude God that correlates Claude AI spending with Git productivity. Shows cost per commit, cost per line of code, per-project and per-model efficiency, and 30-day trends.

## Decisions

- **Git discovery**: auto-detect repos from Claude session project paths (JSONL files already contain project directories)
- **Commit scope**: all commits by the user (filtered by `git config user.email`)
- **Correlation window**: a commit is "Claude-assisted" if it falls within 2 hours after the end of a Claude session on the same project
- **Metrics**: cost/commit, cost/line, per-project breakdown, per-model efficiency, 30-day trend
- **Location**: 4th tab "ROI" with keyboard shortcut Cmd+4
- **Popover width**: increase globally from ~300px to ~380px (benefits all tabs)
- **Refresh strategy**: lazy — computed on tab click, cached until next click

## Architecture

### GitAnalyzer (new file: `Sources/GitAnalyzer.swift`)

Stateless static functions. Runs `git log` as subprocess (same pattern as `security` in AuthManager).

Inputs: list of project paths + date range.
Outputs: array of `GitCommit`.

Filters by user email. Parses: hash, date, lines added/deleted, commit message. Limited to 30 days via `--since`.

### Correlation (in UsageManager)

Crosses `TimelineSession` data with `GitCommit` data. A commit is "assisted" if `commit.date` falls between `session.startTime` and `session.endTime + 2 hours` for the same project path.

Produces `ROIStats` struct.

### ROI View (in MenuBarView)

4th tab, same visual style as Analytics.

## Data Models

```swift
struct GitCommit {
    let hash: String
    let date: Date
    let message: String
    let linesAdded: Int
    let linesDeleted: Int
    let projectPath: String
}

struct ProjectROI {
    let projectName: String
    let totalCost: Double
    let assistedCommits: Int
    let totalLinesChanged: Int
    let costPerCommit: Double
    let costPerLine: Double
    let modelBreakdown: [(model: String, cost: Double, commits: Int)]
}

struct ROIStats {
    let period: Int  // days (default 30)
    let totalCost: Double
    let totalAssistedCommits: Int
    let totalLinesChanged: Int
    let costPerCommit: Double
    let costPerLine: Double
    let byProject: [ProjectROI]
    let dailyTrend: [(date: Date, cost: Double, commits: Int)]
    let byModel: [(model: String, cost: Double, avgCostPerCommit: Double)]
}
```

## UI Layout (vertical scroll)

1. **Header** — 3 stat cards: Total Cost (30d) | Assisted Commits | Cost/Commit
2. **Sparkline trend** — 30 days, bars = commits/day, line = cost/day
3. **By project** — top 5, sorted by cost desc. Columns: name, commits, lines changed, cost, cost/commit. Color bar per project.
4. **By model** — compact table. Opus/Sonnet/Haiku: commits, avg cost/commit.
5. **Trend line** — "Your cost per commit decreased 23% this month" (first half vs second half comparison)

## Error Handling

- No `.git` in project → skip silently
- No commits in period → empty state message
- Git not installed → detect with `which git`, show "Git not found" in tab
- Large repos → `git log --since=30.days.ago` keeps it fast
- Division by zero → cost/commit = 0 when 0 commits
- Execution → background thread, same as timeline JSONL parsing

## Popover Resize

Increase popover width globally from ~300px to ~380px. All tabs benefit from the extra space (fixes existing truncation issues in Analytics).
