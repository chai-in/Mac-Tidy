import Foundation
import XCTest
@testable import MacTidy

final class MoleCommandTests: XCTestCase {
    func testBundledEngineCandidateComesFirst() {
        let resources = URL(fileURLWithPath: "/Applications/Mac Tidy.app/Contents/Resources")
        let candidates = MoleExecutableLocator.candidatePaths(
            resourceURL: resources,
            environment: ["MAC_TIDY_EXECUTABLE": "/tmp/development-mole"],
            homePath: "/Users/example",
            pathVariable: "/custom/bin:/other/bin"
        )

        XCTAssertEqual(candidates.first, "/Applications/Mac Tidy.app/Contents/Resources/Mole/mole")
        XCTAssertEqual(candidates[1], "/tmp/development-mole")
        XCTAssertTrue(candidates.contains("/custom/bin/mo"))
    }

    func testPackagedAppOnlyConsidersBundledEngine() {
        let resources = URL(fileURLWithPath: "/Applications/Mac Tidy.app/Contents/Resources")
        let candidates = MoleExecutableLocator.candidatePaths(
            resourceURL: resources,
            environment: ["MAC_TIDY_EXECUTABLE": "/tmp/untrusted-mole"],
            homePath: "/Users/example",
            pathVariable: "/custom/bin",
            allowDevelopmentFallback: false
        )

        XCTAssertEqual(candidates, ["/Applications/Mac Tidy.app/Contents/Resources/Mole/mole"])
    }

    func testCleanPreservesExternalPathAndNativeSystemChoice() {
        let preview = MoleCommands.clean(
            preview: true,
            externalPath: "/Volumes/Backup Disk",
            debug: true,
            includeSystemCaches: false
        )
        XCTAssertEqual(preview.arguments, ["clean", "--dry-run", "--external", "/Volumes/Backup Disk", "--debug"])
        XCTAssertEqual(preview.environment["MOLE_GUI_SYSTEM_CACHES"], "skip")
        XCTAssertNil(preview.environment["MOLE_GUI_CONFIRMED"])

        let clean = MoleCommands.clean(
            preview: false,
            externalPath: nil,
            debug: false,
            includeSystemCaches: true
        )
        XCTAssertEqual(clean.environment["MOLE_GUI_SYSTEM_CACHES"], "include")
        XCTAssertEqual(clean.environment["MOLE_GUI_CONFIRMED"], "1")
        XCTAssertEqual(clean.risk, .destructiveMutation)
    }

    func testUninstallUsesExactCurrentPaths() {
        let command = MoleCommands.uninstall(
            paths: ["/Applications/Microsoft 365 Copilot.app", "/Applications/Bob's App.app"],
            preview: false,
            permanent: false,
            debug: true
        )

        XCTAssertEqual(command.arguments, [
            "uninstall", "--debug",
            "--gui-path=/Applications/Microsoft 365 Copilot.app",
            "--gui-path=/Applications/Bob's App.app"
        ])
        XCTAssertEqual(command.risk, .recoverableMutation)
        XCTAssertEqual(command.environment["MOLE_GUI_CONFIRMED"], "1")
        XCTAssertFalse(command.arguments.contains("--permanent"))
    }

    func testPermanentUninstallIsDestructive() {
        let command = MoleCommands.uninstall(
            paths: ["/Applications/Example.app"],
            preview: false,
            permanent: true,
            debug: false
        )
        XCTAssertEqual(command.risk, .destructiveMutation)
        XCTAssertTrue(command.arguments.contains("--permanent"))
    }

    func testNativeWhitelistCommandsKeepEachPatternAsOneArgument() {
        let command = MoleCommands.whitelistSave(.clean, patterns: ["~/Library/Caches/App With Spaces/*", "dns_cache_refresh"])
        XCTAssertEqual(command.arguments, [
            "clean", "--gui-whitelist-save", "~/Library/Caches/App With Spaces/*", "dns_cache_refresh"
        ])
        XCTAssertEqual(command.risk, .configuration)
    }

    func testAnalyzeTrashRequiresNativeConfirmation() {
        let command = MoleCommands.moveToTrash(paths: ["/Users/example/Large File.dmg"])
        XCTAssertEqual(command.arguments, ["analyze", "--trash-json", "/Users/example/Large File.dmg"])
        XCTAssertEqual(command.risk, .recoverableMutation)
        XCTAssertEqual(command.environment["MOLE_GUI_CONFIRMED"], "1")
    }

    func testPurgeSelectionFollowsPrivateFlagAndIsConfirmed() {
        let command = MoleCommands.purgeRemove(
            paths: ["/Users/example/Code/App/node_modules", "/Users/example/Code/App/.build"],
            preview: false,
            includeEmpty: true,
            debug: true
        )
        XCTAssertEqual(command.arguments, [
            "purge", "--include-empty", "--debug", "--gui-remove",
            "/Users/example/Code/App/node_modules", "/Users/example/Code/App/.build"
        ])
        XCTAssertEqual(command.environment["MOLE_GUI_CONFIRMED"], "1")
        XCTAssertEqual(command.risk, .destructiveMutation)
    }

    func testInstallerPreviewCannotMutate() {
        let command = MoleCommands.installersRemove(
            paths: ["/Users/example/Downloads/App.dmg"],
            preview: true,
            debug: false
        )
        XCTAssertEqual(command.arguments, [
            "installer", "--dry-run", "--gui-remove", "/Users/example/Downloads/App.dmg"
        ])
        XCTAssertEqual(command.risk, .preview)
        XCTAssertNil(command.environment["MOLE_GUI_CONFIRMED"])
    }

    func testEveryTrueMutationCarriesConfirmationToken() {
        let commands = [
            MoleCommands.clean(preview: false, externalPath: nil, debug: false, includeSystemCaches: false),
            MoleCommands.uninstall(paths: ["/Applications/App.app"], preview: false, permanent: false, debug: false),
            MoleCommands.optimize(preview: false, debug: false),
            MoleCommands.moveToTrash(paths: ["/tmp/item"]),
            MoleCommands.purgeRemove(paths: ["/tmp/project/node_modules"], preview: false, includeEmpty: false, debug: false),
            MoleCommands.installersRemove(paths: ["/tmp/App.dmg"], preview: false, debug: false),
            MoleCommands.touchID(.enable)
        ]

        for command in commands {
            XCTAssertTrue(command.risk.requiresNativeConfirmation, command.label)
            XCTAssertEqual(command.environment["MOLE_GUI_CONFIRMED"], "1", command.label)
        }
    }

    func testHistoryLimitIsClampedToMoleContract() {
        XCTAssertEqual(MoleCommands.history(limit: 0).arguments.suffix(1), ["1"])
        XCTAssertEqual(MoleCommands.history(limit: 999).arguments.suffix(1), ["200"])
    }

    func testSidebarCoversEveryNativeFeatureOnce() {
        let grouped = MoleFeature.toolkit + MoleFeature.storage + MoleFeature.settings
        XCTAssertEqual(Set(grouped), Set(MoleFeature.allCases))
        XCTAssertEqual(grouped.count, MoleFeature.allCases.count)
    }

    func testFullDiskAccessSetupAppearsOncePerAppVersion() {
        XCTAssertTrue(FullDiskAccessSetup.shouldPresent(completedVersion: ""))
        XCTAssertTrue(FullDiskAccessSetup.shouldPresent(completedVersion: "0.9.0"))
        XCTAssertFalse(FullDiskAccessSetup.shouldPresent(completedVersion: FullDiskAccessSetup.currentVersion))
        XCTAssertEqual(
            FullDiskAccessSetup.settingsURL.absoluteString,
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles"
        )
    }

    func testVersionParserReadsBundledMoleVersion() {
        XCTAssertEqual(MoleRunner.parseVersion("Mole version 1.53.0\n"), "1.53.0")
    }

    func testPrivateJSONModelsDecodeSnakeCaseContracts() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        let application = try decoder.decode(InstalledApplication.self, from: Data(#"{"name":"Example","bundle_id":"com.example.app","source":"App","uninstall_name":"Example","path":"/Applications/Example.app","size":"2 MB"}"#.utf8))
        XCTAssertEqual(application.bundleID, "com.example.app")

        let installer = try decoder.decode(InstallerCandidate.self, from: Data(#"{"name":"App.dmg","path":"/tmp/App.dmg","source":"Downloads","size":"2 MB","size_bytes":2097152}"#.utf8))
        XCTAssertEqual(installer.sizeBytes, 2_097_152)

        let purge = try decoder.decode(PurgeCandidate.self, from: Data(#"{"path":"/tmp/App/node_modules","display_path":"~/App/node_modules","project_path":"/tmp/App","artifact":"node_modules","size_kb":1024,"size_unknown":false,"recent":false,"age":"12d","cloud":false}"#.utf8))
        XCTAssertTrue(purge.recommended)
        XCTAssertEqual(purge.sizeBytes, 1_048_576)
    }

    func testAnalysisDecodesLargeFileRowsWithoutDirectoryFlag() throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let json = #"{"path":"/tmp/fixture","overview":false,"entries":[{"name":"folder","path":"/tmp/fixture/folder","size":120000000,"is_dir":true}],"large_files":[{"name":"large.bin","path":"/tmp/fixture/folder/large.bin","size":120000000}],"total_size":120000000}"#
        let analysis = try decoder.decode(DiskAnalysis.self, from: Data(json.utf8))
        XCTAssertTrue(analysis.entries[0].isDir)
        XCTAssertFalse(try XCTUnwrap(analysis.largeFiles?.first).isDir)
        XCTAssertEqual(analysis.largeFiles?.first?.size, 120_000_000)
    }
}
