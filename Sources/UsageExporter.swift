// UsageExporter.swift
// Serialize the current usage state to ~/.claude-god/usage.json so that
// external tools (statusline scripts, tmux/i3blocks widgets, dashboards) can
// read live data without having to talk to the OAuth API themselves.

import Foundation

enum UsageExporter {
    /// Root directory that other Claude God integrations read from.
    static let baseDirectory: URL = {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude-god", isDirectory: true)
    }()

    static var usageFileURL: URL { baseDirectory.appendingPathComponent("usage.json") }
    static var statuslineScriptURL: URL { baseDirectory.appendingPathComponent("statusline.sh") }

    /// One-shot serialization. Returns the JSON string on success or nil on failure.
    /// Caller decides whether to actually write to disk.
    static func makeSnapshot(
        version: String,
        quotas: [UsageQuota],
        extraUsage: ExtraUsageData?,
        activeSessionRunning: Bool,
        activeSessionCost: Double,
        activeSessionMessages: Int,
        today: UsageStats,
        month: UsageStats,
        monthlyForecast: (projected: Double, daysRemaining: Int)?,
        credentialSource: String
    ) -> Data? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let now = Date()

        var root: [String: Any] = [
            "generated_at": iso.string(from: now),
            "generator": "claude-god \(version)",
            "credential_source": credentialSource,
        ]

        // ---- Full quota list ----
        let quotaObjects: [[String: Any]] = quotas.map { q in
            var obj: [String: Any] = [
                "label": q.label,
                "utilization": q.utilization,
                "level": q.level.jsonName,
            ]
            if let resetsAt = q.resetsAt {
                obj["resets_at"] = iso.string(from: resetsAt)
                obj["resets_in_seconds"] = Int(max(0, resetsAt.timeIntervalSince(now)))
            }
            return obj
        }
        root["quotas"] = quotaObjects

        // ---- Convenience "primary" object for scripts that just want a headline number ----
        // Picks Session (5h) first, then falls back to Weekly (all), then the first quota.
        let primary = quotas.first(where: { $0.label.hasPrefix("Session") })
            ?? quotas.first(where: { $0.label.hasPrefix("Weekly") })
            ?? quotas.first
        if let primary {
            var p: [String: Any] = [
                "label": primary.label,
                "utilization": primary.utilization,
                "level": primary.level.jsonName,
            ]
            if let resetsAt = primary.resetsAt {
                p["resets_at"] = iso.string(from: resetsAt)
                p["resets_in_seconds"] = Int(max(0, resetsAt.timeIntervalSince(now)))
            }
            root["primary"] = p
        }

        // ---- Extra usage ----
        if let extra = extraUsage {
            var ex: [String: Any] = [
                "enabled": extra.isEnabled,
                "currency": extra.currency ?? "USD",
            ]
            if let cents = extra.usedCredits { ex["used_usd"] = cents / 100.0 }
            if let limit = extra.monthlyLimit { ex["limit_usd"] = limit / 100.0 }
            if let util = extra.utilization { ex["utilization"] = util }
            root["extra_usage"] = ex
        }

        // ---- Active session + today + month ----
        root["active_session"] = [
            "running": activeSessionRunning,
            "cost_usd": activeSessionCost,
            "messages": activeSessionMessages,
        ]
        root["today"] = [
            "cost_usd": today.totalCost,
            "messages": today.totalMessages,
            "tokens": today.totalTokens.totalTokens,
        ]
        var monthObj: [String: Any] = [
            "cost_usd": month.totalCost,
            "messages": month.totalMessages,
            "tokens": month.totalTokens.totalTokens,
        ]
        if let forecast = monthlyForecast {
            monthObj["projected_usd"] = forecast.projected
            monthObj["days_remaining"] = forecast.daysRemaining
        }
        root["month"] = monthObj

        return try? JSONSerialization.data(
            withJSONObject: root,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    /// Ensure `~/.claude-god/` exists and write the snapshot atomically.
    @discardableResult
    static func writeSnapshot(_ data: Data) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
            try data.write(to: usageFileURL, options: .atomic)
            return true
        } catch {
            Log.error("Failed to write usage.json: \(error)")
            return false
        }
    }

    /// Remove the export files when the user disables the toggle so that a
    /// consumer picking up a stale file doesn't keep rendering old numbers.
    static func removeSnapshot() {
        try? FileManager.default.removeItem(at: usageFileURL)
    }

    // MARK: - Statusline helper script

    /// Bundled statusline script — reads `usage.json` and prints a colored one-liner
    /// suitable for Claude Code's `statusLine` setting or any other consumer.
    ///
    /// Kept intentionally dependency-free: only `python3` (pre-installed on macOS).
    static let statuslineScript: String = #"""
    #!/usr/bin/env python3
    # Claude God statusline helper — reads ~/.claude-god/usage.json and prints
    # a compact one-line status. Wire it into Claude Code by adding to
    # ~/.claude/settings.json:
    #
    #   "statusLine": {
    #       "type": "command",
    #       "command": "~/.claude-god/statusline.sh"
    #   }
    #
    # Regenerated by Claude God — safe to edit but changes will be overwritten
    # next time you toggle the statusline in Settings.
    import json, os, sys, time

    PATH = os.path.expanduser("~/.claude-god/usage.json")

    def color(pct):
        if pct is None: return "\033[90m"
        if pct >= 90:   return "\033[31m"  # red
        if pct >= 75:   return "\033[33m"  # yellow
        return "\033[32m"                   # green

    RESET = "\033[0m"
    DIM   = "\033[2m"

    def fmt_eta(seconds):
        if seconds is None: return None
        seconds = int(seconds)
        if seconds < 60:      return f"{seconds}s"
        if seconds < 3600:    return f"{seconds // 60}m"
        if seconds < 86400:   return f"{seconds // 3600}h{(seconds % 3600) // 60}m"
        return f"{seconds // 86400}d"

    def pick(quotas, prefix):
        for q in quotas:
            if q.get("label", "").startswith(prefix):
                return q
        return None

    try:
        with open(PATH) as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"{DIM}claude god: not running (enable JSON export in Settings){RESET}")
        sys.exit(0)
    except Exception as e:
        print(f"{DIM}claude god: read error{RESET}", file=sys.stderr)
        sys.exit(0)

    parts = []
    quotas = data.get("quotas", [])

    session = pick(quotas, "Session")
    if session is not None:
        pct = session.get("utilization", 0)
        eta = fmt_eta(session.get("resets_in_seconds"))
        s = f"{color(pct)}session {pct:.0f}%{RESET}"
        if eta: s += f"{DIM} · {eta}{RESET}"
        parts.append(s)

    weekly = pick(quotas, "Weekly (all)") or pick(quotas, "Weekly")
    if weekly is not None:
        pct = weekly.get("utilization", 0)
        parts.append(f"{color(pct)}weekly {pct:.0f}%{RESET}")

    today = data.get("today") or {}
    if today.get("cost_usd") is not None:
        parts.append(f"{DIM}${today['cost_usd']:.2f} today{RESET}")

    # Show staleness so users notice when Claude God is stopped or slow.
    gen = data.get("generated_at")
    try:
        if gen:
            gen_epoch = time.mktime(time.strptime(gen[:19], "%Y-%m-%dT%H:%M:%S"))
            age = int(time.time() - gen_epoch) - time.timezone
            if age > 120:
                parts.append(f"{DIM}(stale {age // 60}m){RESET}")
    except Exception:
        pass

    print(" · ".join(parts) if parts else f"{DIM}claude god: no data yet{RESET}")
    """#

    /// Write the statusline helper to `~/.claude-god/statusline.sh` and mark it executable.
    /// Returns the destination path on success.
    @discardableResult
    static func installStatuslineScript() -> URL? {
        do {
            try FileManager.default.createDirectory(
                at: baseDirectory,
                withIntermediateDirectories: true
            )
            try statuslineScript.write(to: statuslineScriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: statuslineScriptURL.path
            )
            return statuslineScriptURL
        } catch {
            Log.error("Failed to install statusline script: \(error)")
            return nil
        }
    }

    static func uninstallStatuslineScript() {
        try? FileManager.default.removeItem(at: statuslineScriptURL)
    }

    /// The JSON snippet the user pastes into `~/.claude/settings.json` to wire us up.
    static var statuslineConfigSnippet: String {
        """
        {
          "statusLine": {
            "type": "command",
            "command": "\(statuslineScriptURL.path)"
          }
        }
        """
    }
}

// MARK: - UsageLevel JSON hint

private extension UsageLevel {
    var jsonName: String {
        switch self {
        case .good:     return "green"
        case .warning:  return "orange"
        case .critical: return "red"
        }
    }
}
