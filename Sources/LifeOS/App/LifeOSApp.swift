import AppKit
import OSLog
import SwiftData
import SwiftUI
import LifeOSCore

private enum StoreIntegrityPreflight {
    private static let logger = Logger(subsystem: "local.codex.lifeos", category: "store-preflight")

    static func repairIfNeeded() {
        guard let storeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.appendingPathComponent("LifeOSData.store") else {
            logger.error("Unable to resolve Application Support store URL.")
            return
        }

        guard FileManager.default.fileExists(atPath: storeURL.path) else {
            logger.info("No existing SwiftData store found. Skipping preflight repair.")
            return
        }

        do {
            let beforeCount = try invalidReferenceCount(storeURL: storeURL)
            guard beforeCount > 0 else {
                logger.info("SwiftData store preflight passed with no invalid references.")
                return
            }

            logger.warning("SwiftData store preflight found \(beforeCount, privacy: .public) invalid references. Repairing before ModelContainer opens.")
            _ = try runSQLite(storeURL: storeURL, sql: repairSQL)

            let afterCount = try invalidReferenceCount(storeURL: storeURL)
            if afterCount == 0 {
                logger.info("SwiftData store preflight repaired \(beforeCount, privacy: .public) invalid references.")
            } else {
                logger.error("SwiftData store preflight left \(afterCount, privacy: .public) invalid references.")
            }
        } catch {
            logger.error("SwiftData store preflight failed: \(String(describing: error), privacy: .public)")
        }
    }

    private static func invalidReferenceCount(storeURL: URL) throws -> Int {
        let output = try runSQLite(storeURL: storeURL, sql: invalidReferenceCountSQL)
        return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    private static func runSQLite(storeURL: URL, sql: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [storeURL.path]

        let input = Pipe()
        let output = Pipe()
        let error = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = error

        try process.run()
        input.fileHandleForWriting.write(Data(sql.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = error.fileHandleForReading.readDataToEndOfFile()
        let outputText = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            let errorText = String(data: errorData, encoding: .utf8) ?? "unknown sqlite3 error"
            throw SQLiteError.failed(status: process.terminationStatus, message: errorText)
        }

        return outputText
    }

    private enum SQLiteError: Error {
        case failed(status: Int32, message: String)
    }

    private static let invalidReferenceCountSQL = """
    select
      (select count(*) from ZTASKITEM t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null) +
      (select count(*) from ZCALENDARITEM t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null) +
      (select count(*) from ZLEDGERENTRY t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null) +
      (select count(*) from ZPLANNEDENTRY t left join ZPROJECT p on t.ZPROJECT = p.Z_PK where t.ZPROJECT is not null and p.Z_PK is null) +
      (select count(*) from ZPROJECT t left join ZGOAL p on t.ZGOAL = p.Z_PK where t.ZGOAL is not null and p.Z_PK is null) +
      (select count(*) from ZLEDGERENTRY t left join ZACCOUNT p on t.ZACCOUNT = p.Z_PK where t.ZACCOUNT is not null and p.Z_PK is null) +
      (select count(*) from ZLEDGERENTRY t left join ZCATEGORY p on t.ZCATEGORY = p.Z_PK where t.ZCATEGORY is not null and p.Z_PK is null) +
      (select count(*) from ZPLANNEDENTRY t left join ZACCOUNT p on t.ZACCOUNT = p.Z_PK where t.ZACCOUNT is not null and p.Z_PK is null) +
      (select count(*) from ZPLANNEDENTRY t left join ZCATEGORY p on t.ZCATEGORY = p.Z_PK where t.ZCATEGORY is not null and p.Z_PK is null) +
      (select count(*) from ZASSETSNAPSHOT t left join ZACCOUNT p on t.ZACCOUNT = p.Z_PK where t.ZACCOUNT is not null and p.Z_PK is null) +
      (select count(*) from ZASSETSNAPSHOT t left join ZCATEGORY p on t.ZCATEGORY = p.Z_PK where t.ZCATEGORY is not null and p.Z_PK is null);
    """

    private static let repairSQL = """
    pragma busy_timeout = 5000;
    begin immediate;
    update ZTASKITEM set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
    update ZCALENDARITEM set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
    update ZLEDGERENTRY set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
    update ZPLANNEDENTRY set ZPROJECT = null where ZPROJECT is not null and ZPROJECT not in (select Z_PK from ZPROJECT);
    update ZPROJECT set ZGOAL = null where ZGOAL is not null and ZGOAL not in (select Z_PK from ZGOAL);
    update ZLEDGERENTRY set ZACCOUNT = null where ZACCOUNT is not null and ZACCOUNT not in (select Z_PK from ZACCOUNT);
    update ZLEDGERENTRY set ZCATEGORY = null where ZCATEGORY is not null and ZCATEGORY not in (select Z_PK from ZCATEGORY);
    update ZPLANNEDENTRY set ZACCOUNT = null where ZACCOUNT is not null and ZACCOUNT not in (select Z_PK from ZACCOUNT);
    update ZPLANNEDENTRY set ZCATEGORY = null where ZCATEGORY is not null and ZCATEGORY not in (select Z_PK from ZCATEGORY);
    update ZASSETSNAPSHOT set ZACCOUNT = null where ZACCOUNT is not null and ZACCOUNT not in (select Z_PK from ZACCOUNT);
    update ZASSETSNAPSHOT set ZCATEGORY = null where ZCATEGORY is not null and ZCATEGORY not in (select Z_PK from ZCATEGORY);
    commit;
    pragma wal_checkpoint(truncate);
    """
}

@MainActor
final class LifeOSApplicationDelegate: NSObject, NSApplicationDelegate {
    private let logger = Logger(subsystem: "local.codex.lifeos", category: "app-lifecycle")

    func applicationDidFinishLaunching(_ notification: Notification) {
        logger.info("LifeOS finished launching.")
        bringMainWindowForwardRepeatedly()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        logger.info("LifeOS reopen requested. hasVisibleWindows=\(flag, privacy: .public)")
        bringMainWindowForwardRepeatedly()
        return true
    }

    func applicationShouldSaveApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldRestoreApplicationState(_ sender: NSApplication) -> Bool {
        false
    }

    private func bringMainWindowForwardRepeatedly() {
        for delay in [0.0, 0.25, 0.75, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.bringMainWindowForward()
            }
        }
    }

    private func bringMainWindowForward() {
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)

        guard let mainWindow = primaryMainWindow() else {
            NSApp.activate(ignoringOtherApps: true)
            logger.debug("Requested foreground activation without a visible main window.")
            return
        }

        closeExtraMainWindows(keeping: mainWindow)

        mainWindow.deminiaturize(nil)
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.orderFrontRegardless()

        NSApp.activate(ignoringOtherApps: true)
        NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps])
        logger.debug("Requested foreground activation for one main window. windowCount=\(NSApp.windows.count, privacy: .public)")
    }

    private func primaryMainWindow() -> NSWindow? {
        let visibleWindows = NSApp.windows.filter { $0.canBecomeMain }
        return visibleWindows.first { window in
            window.title == "Life OS" || window.title == "LifeOS"
        } ?? visibleWindows.first
    }

    private func closeExtraMainWindows(keeping mainWindow: NSWindow) {
        let extraWindows = NSApp.windows.filter { window in
            window !== mainWindow && window.canBecomeMain
        }
        guard extraWindows.isEmpty == false else { return }

        for window in extraWindows {
            window.close()
        }
        logger.info("Closed \(extraWindows.count, privacy: .public) extra LifeOS window(s) during foreground activation.")
    }
}

@main
struct LifeOSApp: App {
    @NSApplicationDelegateAdaptor(LifeOSApplicationDelegate.self) private var appDelegate
    @State private var appState = LifeOSAppState()
    @State private var marketQuoteStore = MarketQuoteStore()
    @State private var localizationStore = LocalizationStore()
    private let modelContainer: ModelContainer

    init() {
        StoreIntegrityPreflight.repairIfNeeded()
        do {
            modelContainer = try LifeOSModelContainer.shared()
        } catch {
            fatalError("Unable to create model container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootSplitView()
                .environment(appState)
                .environment(marketQuoteStore)
                .environment(localizationStore)
                .environment(\.locale, localizationStore.locale)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button(localizationStore.text("New Ledger Entry")) {
                    appState.open(.ledger)
                }
                .keyboardShortcut("l", modifiers: [.command, .shift])

                Button(localizationStore.text("New Planned Entry")) {
                    appState.open(.planned)
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])

                Button(localizationStore.text("New Task")) {
                    appState.open(.task)
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])

                Button(localizationStore.text("New Calendar Item")) {
                    appState.open(.calendar)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
            }

            CommandGroup(after: .toolbar) {
                Button(appState.isInspectorPresented ? localizationStore.text("Hide Inspector") : localizationStore.text("Show Inspector")) {
                    appState.toggleInspector()
                }
                .keyboardShortcut("i", modifiers: [.command, .option])
            }
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsWorkspaceView()
                .environment(appState)
                .environment(marketQuoteStore)
                .environment(localizationStore)
                .environment(\.locale, localizationStore.locale)
        }
        .modelContainer(modelContainer)
    }
}
