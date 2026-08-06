import Foundation

/// Turns a `.pptx` into a PDF that `PDFSlideRenderer` can draw.
///
/// macOS has no API that renders `.pptx`, so conversion is unavoidable
/// (ADR-0002). Each conformance wraps one external application, and each is
/// optional — `isAvailable()` is what lets the chain skip a backend that is not
/// installed rather than failing the whole open.
public protocol DeckConverter: Sendable {
    /// Shown in errors, so the user learns *which* converter failed.
    var name: String { get }

    /// Whether this converter can run on this machine right now.
    func isAvailable() -> Bool

    func convert(_ pptx: URL, to pdf: URL) async throws
}

/// Why a conversion did not produce a PDF.
public enum ConversionError: Error, Equatable, Sendable {
    case converterUnavailable(String)
    case failed(converter: String, reason: String)
    case producedNothing(converter: String)
    case timedOut(converter: String, seconds: Int)
}

// MARK: - LibreOffice

/// `soffice --headless --convert-to pdf`.
///
/// First in the chain because it honours fonts embedded in the `.pptx` under
/// `ppt/fonts/*.fntdata`. Keynote ignores them and substitutes, which reflows
/// text out of its shape — measured in spike #16, and the specific reason for
/// this ordering rather than a general fidelity preference.
public struct LibreOfficeConverter: DeckConverter {
    public let name = "LibreOffice"

    /// Searched in order. `soffice` on `PATH` is not assumed: a GUI app does not
    /// inherit the shell's environment, so a Homebrew install is invisible unless
    /// its location is checked directly.
    static let candidatePaths = [
        "/opt/homebrew/bin/soffice",
        "/usr/local/bin/soffice",
        "/Applications/LibreOffice.app/Contents/MacOS/soffice",
    ]

    /// Generous on purpose. LibreOffice's **first ever** invocation took 321s
    /// building its user profile, against 6s warm — measured in spike #16. A
    /// short timeout fails every new user's first deck-open and reads as a hang.
    static let timeout = 420

    private let executable: URL?

    public init() {
        self.executable = Self.candidatePaths
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    public func isAvailable() -> Bool { executable != nil }

    public func convert(_ pptx: URL, to pdf: URL) async throws {
        guard let executable else { throw ConversionError.converterUnavailable(name) }

        let workingDirectory = pdf.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: workingDirectory, withIntermediateDirectories: true)

        // soffice names its output after the input and will not be told
        // otherwise, so it writes into a directory and the result is moved.
        let produced =
            workingDirectory
            .appendingPathComponent(pptx.deletingPathExtension().lastPathComponent)
            .appendingPathExtension("pdf")
        try? FileManager.default.removeItem(at: produced)

        try await Subprocess.run(
            executable: executable,
            arguments: [
                "--headless", "--convert-to", "pdf",
                "--outdir", workingDirectory.path, pptx.path,
            ],
            timeout: Self.timeout,
            converter: name)

        guard FileManager.default.fileExists(atPath: produced.path) else {
            throw ConversionError.producedNothing(converter: name)
        }
        if produced != pdf {
            try? FileManager.default.removeItem(at: pdf)
            try FileManager.default.moveItem(at: produced, to: pdf)
        }
    }
}

// MARK: - Keynote

/// Keynote, driven through LaunchServices and then Apple Events.
///
/// **The order is the whole trick.** `tell application "Keynote" to open POSIX
/// file "…"` fails: Keynote is sandboxed, a bare path carries no sandbox
/// extension token, and it raises a modal — *"can't be imported. The file
/// couldn't be opened."* — while the AppleEvent **times out rather than
/// returning an error**. Opening through LaunchServices passes the token, so the
/// export that follows just works. Measured in spike #16; reference script in
/// `Spikes/16-keynote/convert.sh`.
public struct KeynoteConverter: DeckConverter {
    public let name = "Keynote"
    static let bundleIdentifier = "com.apple.iWork.Keynote"
    static let timeout = 300

    public init() {}

    public func isAvailable() -> Bool {
        NSWorkspaceShim.applicationURL(forBundleIdentifier: Self.bundleIdentifier) != nil
    }

    public func convert(_ pptx: URL, to pdf: URL) async throws {
        guard isAvailable() else { throw ConversionError.converterUnavailable(name) }

        try FileManager.default.createDirectory(
            at: pdf.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: pdf)

        // `-g` keeps Keynote off the foreground. Verified in spike #16: the
        // frontmost application is unchanged across a conversion, which is what
        // makes this survivable in a presenter app.
        try await Subprocess.run(
            executable: URL(fileURLWithPath: "/usr/bin/open"),
            arguments: ["-g", "-b", Self.bundleIdentifier, pptx.path],
            timeout: 60,
            converter: name)

        try await Subprocess.run(
            executable: URL(fileURLWithPath: "/usr/bin/osascript"),
            arguments: ["-e", Self.exportScript(output: pdf)],
            timeout: Self.timeout,
            converter: name)

        guard FileManager.default.fileExists(atPath: pdf.path) else {
            throw ConversionError.producedNothing(converter: name)
        }
    }

    /// Waits for the document rather than sleeping a guessed interval, then
    /// exports and closes it. Leaving the document open would leak one per
    /// deck-open.
    static func exportScript(output: URL) -> String {
        """
        set deadline to (current date) + 60
        repeat
          tell application "Keynote"
            if (count of documents) > 0 then exit repeat
          end tell
          if (current date) > deadline then error "Keynote did not open the file"
          delay 0.5
        end repeat
        with timeout of \(timeout) seconds
          tell application "Keynote"
            set d to front document
            export d to POSIX file "\(output.path)" as PDF
            close d saving no
          end tell
        end timeout
        """
    }
}

// MARK: - Running a subprocess with a timeout

enum Subprocess {
    static func run(
        executable: URL, arguments: [String], timeout: Int, converter: String
    ) async throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Discarded rather than inherited: a converter writing to the app's
        // stdout is noise, and an unread pipe that fills will deadlock.
        process.standardOutput = FileHandle.nullDevice
        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()

        let deadline = Date().addingTimeInterval(TimeInterval(timeout))
        while process.isRunning {
            if Date() > deadline {
                process.terminate()
                throw ConversionError.timedOut(converter: converter, seconds: timeout)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }

        guard process.terminationStatus == 0 else {
            let message = String(
                decoding: errorPipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConversionError.failed(
                converter: converter,
                reason: message.isEmpty ? "exit status \(process.terminationStatus)" : message)
        }
    }
}

/// Isolates the one AppKit call this file needs, so `SlideKit` stays testable
/// without pulling a UI framework into every test.
enum NSWorkspaceShim {
    static func applicationURL(forBundleIdentifier identifier: String) -> URL? {
        #if canImport(AppKit)
            return NSWorkspaceBridge.url(forBundleIdentifier: identifier)
        #else
            return nil
        #endif
    }
}

#if canImport(AppKit)
    import AppKit

    private enum NSWorkspaceBridge {
        static func url(forBundleIdentifier identifier: String) -> URL? {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
        }
    }
#endif
