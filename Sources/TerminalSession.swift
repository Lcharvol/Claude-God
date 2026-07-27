// TerminalSession.swift
// Runs a CLI process in a pseudo-TTY and streams output to a @Published string.
// Used to embed `claude auth login` directly inside the popover.

import Foundation
import Combine

final class TerminalSession: ObservableObject {

    @Published private(set) var output: String = ""
    @Published private(set) var isRunning: Bool = false

    private var process: Process?
    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?

    // MARK: - Start

    /// Launch `executablePath args` inside a PTY.
    /// The process gets a real TTY so prompts and browser-open calls work.
    func start(executablePath: String, args: [String] = []) {
        stop() // clean up any previous session
        output = ""

        // Create PTY pair (POSIX, available on Darwin)
        let master = posix_openpt(O_RDWR | O_NOCTTY)
        guard master >= 0 else {
            output = "[error] posix_openpt failed: \(String(cString: strerror(errno)))\n"
            return
        }
        guard grantpt(master) == 0, unlockpt(master) == 0 else {
            close(master)
            output = "[error] grantpt/unlockpt failed\n"
            return
        }
        guard let slaveNamePtr = ptsname(master) else {
            close(master)
            output = "[error] ptsname failed\n"
            return
        }
        let slaveName = String(cString: slaveNamePtr)
        let slave = open(slaveName, O_RDWR)
        guard slave >= 0 else {
            close(master)
            output = "[error] open slave PTY failed\n"
            return
        }

        masterFD = master

        let p = Process()
        p.executableURL = URL(fileURLWithPath: executablePath)
        p.arguments = args

        // Give the process the slave end as its terminal
        let slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
        p.standardInput  = slaveHandle
        p.standardOutput = slaveHandle
        p.standardError  = slaveHandle

        p.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { self?.isRunning = false }
        }

        do {
            try p.run()
        } catch {
            close(master)
            close(slave)
            output = "[error] launch failed: \(error.localizedDescription)\n"
            return
        }

        // App only needs master end — slave is owned by the child process
        close(slave)

        process = p
        isRunning = true
        startReading()
    }

    // MARK: - Input

    /// Write a line to the child process's stdin.
    /// `claude auth login` asks the user to paste an authorization code, so the
    /// embedded session is unusable without a way to answer it.
    func send(_ line: String) {
        guard masterFD >= 0, let data = (line + "\n").data(using: .utf8) else { return }
        data.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var written = 0
            while written < buffer.count {
                let n = write(masterFD, base.advanced(by: written), buffer.count - written)
                guard n > 0 else {
                    Log.warn("TerminalSession.send: write failed: \(String(cString: strerror(errno)))")
                    return
                }
                written += n
            }
        }
    }

    // MARK: - Stop

    func stop() {
        readSource?.cancel()
        readSource = nil
        process?.terminate()
        process = nil
        if masterFD >= 0 {
            close(masterFD)
            masterFD = -1
        }
        isRunning = false
    }

    // MARK: - Read loop

    private func startReading() {
        let fd = masterFD
        let src = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .global(qos: .utility))
        src.setEventHandler { [weak self] in
            var buf = [UInt8](repeating: 0, count: 2048)
            let n = read(fd, &buf, buf.count)
            guard n > 0 else { return }
            let raw = String(bytes: buf.prefix(n), encoding: .utf8) ?? ""
            let clean = Self.stripANSI(raw)
            guard !clean.isEmpty else { return }
            DispatchQueue.main.async { self?.output += clean }
        }
        src.setCancelHandler { /* fd closed in stop() */ }
        src.resume()
        readSource = src
    }

    // MARK: - ANSI stripping

    private static let ansiPattern = try! NSRegularExpression(
        pattern: #"\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07]*\x07)"#
    )

    private static func stripANSI(_ text: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return ansiPattern.stringByReplacingMatches(in: text, range: range, withTemplate: "")
    }

    deinit { stop() }
}
