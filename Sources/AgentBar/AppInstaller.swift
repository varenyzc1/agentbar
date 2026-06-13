import AppKit
import Foundation

enum AppInstallMethod: Equatable {
    case unknown
    case homebrew
    case manual

    var displayText: String {
        switch self {
        case .unknown:
            return "Checking install method..."
        case .homebrew:
            return "Installed with Homebrew."
        case .manual:
            return "Manual install or DMG install."
        }
    }
}

enum HomebrewUpdateError: LocalizedError {
    case brewNotFound
    case notHomebrewInstall
    case couldNotCreateCommand

    var errorDescription: String? {
        switch self {
        case .brewNotFound:
            return "Homebrew was not found"
        case .notHomebrewInstall:
            return "AgentBar is not managed by Homebrew"
        case .couldNotCreateCommand:
            return "Could not create Homebrew update command"
        }
    }
}

struct AppInstaller {
    private static let caskName = "agentbar"
    private static let brewPaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew"
    ]

    static func currentInstallMethod() async -> AppInstallMethod {
        await Task.detached(priority: .utility) {
            guard let brew = brewExecutable() else {
                return .manual
            }

            guard let output = run(brew, arguments: ["list", "--cask", caskName]),
                  output.exitCode == 0 else {
                return .manual
            }

            let appPath = Bundle.main.bundleURL.resolvingSymlinksInPath().standardizedFileURL.path
            let managedPaths = output.stdout
                .split(whereSeparator: \.isNewline)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            if managedPaths.contains(where: { path in
                path.hasSuffix(".app") && URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path == appPath
            }) {
                return .homebrew
            }

            return managedPaths.contains(where: { $0.hasSuffix("/AgentBar.app") }) ? .homebrew : .manual
        }.value
    }

    @MainActor
    static func openHomebrewUpdateTerminal() throws {
        guard brewExecutable() != nil else {
            throw HomebrewUpdateError.brewNotFound
        }

        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("agentbar-homebrew-update-\(UUID().uuidString)")
            .appendingPathExtension("command")

        let script = """
        #!/bin/zsh
        set -e
        export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        echo "Updating AgentBar with Homebrew..."
        brew update
        brew upgrade --cask agentbar
        echo
        echo "AgentBar update finished. You can close this window."
        read -r -s -k 1 "?Press any key to close..."
        """

        do {
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        } catch {
            throw HomebrewUpdateError.couldNotCreateCommand
        }

        NSWorkspace.shared.open(scriptURL)
    }

    private static func brewExecutable() -> String? {
        brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private static func run(_ executable: String, arguments: [String]) -> ProcessOutput? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        return ProcessOutput(
            exitCode: process.terminationStatus,
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }
}

private struct ProcessOutput {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}
