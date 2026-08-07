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
/// The only converter. A Keynote backend existed alongside this one and was
/// removed in #79: it could not import every valid `.pptx`, and it ignored
/// fonts embedded under `ppt/fonts/*.fntdata`, substituting until text
/// reflowed out of its shape. See ADR-0002 for why one converter and a clear
/// error beats two converters and a silent downgrade.
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
