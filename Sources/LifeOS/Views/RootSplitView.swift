import SwiftUI
import LifeOSCore

struct RootSplitView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(LifeOSAppState.self) private var appState
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        NavigationSplitView {
            SidebarListView(selection: Binding(
                get: { appState.activeSection },
                set: { appState.activeSection = $0 }
            ))
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 250)
        .navigationSplitViewStyle(.balanced)
        .inspector(isPresented: Binding(
            get: { appState.isInspectorPresented },
            set: { appState.isInspectorPresented = $0 }
        )) {
            InspectorDetailView()
                .environment(appState)
        }
        .inspectorColumnWidth(min: 280, ideal: 320, max: 380)
        .searchable(
            text: Binding(
                get: { appState.searchText },
                set: { appState.searchText = $0 }
            ),
            placement: .toolbar,
            prompt: l10n.text("Search current workspace")
        )
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    appState.open(.ledger)
                } label: {
                    Label(l10n.text("New Ledger Entry"), systemImage: "plus.circle.fill")
                }
                .accessibilityIdentifier("toolbar-new-ledger")

                Button {
                    appState.open(.planned)
                } label: {
                    Label(l10n.text("New Planned Entry"), systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("toolbar-new-planned")

                Button {
                    appState.open(.task)
                } label: {
                    Label(l10n.text("New Task"), systemImage: "checklist.checked")
                }
                .accessibilityIdentifier("toolbar-new-task")

                Button {
                    appState.open(.calendar)
                } label: {
                    Label(l10n.text("New Calendar Item"), systemImage: "calendar.badge.plus")
                }
                .accessibilityIdentifier("toolbar-new-calendar")

                Divider()

                Button {
                    appState.toggleInspector()
                } label: {
                    Label(l10n.text("Toggle Inspector"), systemImage: "sidebar.right")
                }
                .accessibilityIdentifier("toolbar-toggle-inspector")
            }

            ToolbarItem(placement: .secondaryAction) {
                if appState.isSearching {
                    Button {
                        appState.clearSearch()
                    } label: {
                        Label(l10n.text("Clear Search"), systemImage: "xmark.circle")
                    }
                    .accessibilityIdentifier("toolbar-clear-search")
                }
            }
        }
        .sheet(item: Binding(
            get: { appState.presentedSheet },
            set: { appState.presentedSheet = $0 }
        )) { sheet in
            QuickEntrySheetContainer(sheet: sheet)
                .environment(appState)
        }
        .task(id: l10n.language) {
            try? StarterTemplateService.refreshLocalizedContentIfPossible(context: modelContext, language: l10n.language)
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.activeSection ?? .overview {
        case .overview:
            OverviewWorkspaceView()
        case .ledger:
            LedgerWorkspaceView()
        case .planned:
            PlannedWorkspaceView()
        case .assets:
            AssetsWorkspaceView()
        case .tasks:
            TasksWorkspaceView()
        case .calendar:
            CalendarWorkspaceView()
        case .goals:
            GoalsWorkspaceView()
        case .projects:
            ProjectsWorkspaceView()
        case .settings:
            SettingsWorkspaceView()
        }
    }
}

private struct SidebarListView: View {
    @Binding var selection: SidebarSection?
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        List {
            ForEach(SidebarSection.allCases) { item in
                Button {
                    selection = item
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: item.systemImage)
                            .frame(width: 18)
                        Text(item.localizedTitle(in: l10n.language))
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selection == item ? Color.accentColor.opacity(0.18) : .clear)
                    )
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets(top: 3, leading: 8, bottom: 3, trailing: 8))
                .listRowBackground(Color.clear)
                .accessibilityIdentifier("sidebar-button-\(item.rawValue)")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle(l10n.text("Life OS"))
    }
}
