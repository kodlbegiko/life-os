import Foundation
import Observation
import LifeOSCore

@Observable
@MainActor
final class LifeOSAppState {
    enum QuickSheet: String, Identifiable {
        case ledger
        case planned
        case task
        case calendar

        var id: String { rawValue }
    }

    enum InspectorSelection: Equatable {
        case ledger(UUID)
        case planned(UUID)
        case asset(UUID)
        case task(UUID)
        case calendar(UUID)
        case goal(UUID)
        case project(UUID)
        case account(UUID)
        case category(UUID)
    }

    var activeSection: SidebarSection? = .overview {
        didSet {
            clearInspectorIfNeeded(for: activeSection)
        }
    }
    var presentedSheet: QuickSheet?
    var inspectorSelection: InspectorSelection?
    var isInspectorPresented = true
    var searchText = ""

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearching: Bool {
        trimmedSearchText.isEmpty == false
    }

    func open(_ sheet: QuickSheet) {
        presentedSheet = sheet
    }

    func toggleInspector() {
        isInspectorPresented.toggle()
    }

    func reveal(_ selection: InspectorSelection) {
        inspectorSelection = selection
        isInspectorPresented = true
    }

    func clearSearch() {
        searchText = ""
    }

    private func clearInspectorIfNeeded(for section: SidebarSection?) {
        guard let inspectorSelection else { return }
        guard isInspectorSelection(inspectorSelection, compatibleWith: section ?? .overview) == false else { return }
        self.inspectorSelection = nil
    }

    private func isInspectorSelection(_ selection: InspectorSelection, compatibleWith section: SidebarSection) -> Bool {
        switch section {
        case .overview:
            return true
        case .ledger:
            if case .ledger = selection { return true }
        case .planned:
            if case .planned = selection { return true }
        case .assets:
            if case .asset = selection { return true }
        case .tasks:
            if case .task = selection { return true }
        case .calendar:
            if case .calendar = selection { return true }
        case .goals:
            if case .goal = selection { return true }
        case .projects:
            if case .project = selection { return true }
        case .settings:
            switch selection {
            case .account, .category:
                return true
            default:
                break
            }
        }

        return false
    }
}
