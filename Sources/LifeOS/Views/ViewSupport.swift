import Foundation
import SwiftUI
import LifeOSCore

enum ScheduleDragPayload {
    case task(UUID)
    case dailyPlan(UUID)

    static func taskPayload(_ id: UUID) -> String {
        "lifeos-task:\(id.uuidString)"
    }

    static func dailyPlanPayload(_ id: UUID) -> String {
        "lifeos-daily-plan:\(id.uuidString)"
    }

    init?(_ rawValue: String) {
        let parts = rawValue.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return nil }
        switch parts[0] {
        case "lifeos-task":
            self = .task(id)
        case "lifeos-daily-plan":
            self = .dailyPlan(id)
        default:
            return nil
        }
    }
}

extension Decimal {
    var currencyString: String {
        formatted(.currency(code: "TWD").precision(.fractionLength(0)))
    }

    var signedCurrencyString: String {
        let prefix = self > 0 ? "+" : ""
        return prefix + currencyString
    }

    var plainNumberString: String {
        NSDecimalNumber(decimal: self).stringValue
    }

    var quotePriceString: String {
        formatted(.number.precision(.fractionLength(2)))
    }

    var percentDisplayString: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .percent
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: self)) ?? "-"
    }

    var signedPercentDisplayString: String {
        let prefix = self > 0 ? "+" : ""
        return prefix + percentDisplayString
    }
}

extension Date {
    var dayLabel: String {
        formatted(date: .abbreviated, time: .omitted)
    }

    var shortLabel: String {
        formatted(date: .numeric, time: .shortened)
    }

    func dayLabel(locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: self)
    }

    func shortLabel(locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: self)
    }

    func commandDayID(calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: self)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private struct OptionalAccessibilityIDModifier: ViewModifier {
    let id: String?

    func body(content: Content) -> some View {
        if let id, id.isEmpty == false {
            content.accessibilityIdentifier(id)
        } else {
            content
        }
    }
}

extension View {
    func optionalAccessibilityIdentifier(_ id: String?) -> some View {
        modifier(OptionalAccessibilityIDModifier(id: id))
    }
}

struct MetricCard: View {
    let label: String
    let value: String
    let detail: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(tone)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

struct EmptyStateView: View {
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.title3.weight(.semibold))
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct SectionHeader: View {
    let title: String
    let detail: String
    let buttonTitle: String?
    let action: (() -> Void)?
    var accessibilityID: String? = nil

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.largeTitle.weight(.semibold))
                    .optionalAccessibilityIdentifier(accessibilityID)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

func workspaceSearchMatches(_ query: String, fields: [String?]) -> Bool {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return true }
    let haystack = fields
        .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { $0.isEmpty == false }
        .joined(separator: "\n")
        .lowercased()
    let terms = trimmed.lowercased().split(whereSeparator: \.isWhitespace)
    return terms.allSatisfy { haystack.contains($0) }
}

func workspaceDetailText(base: String, query: String, resultCount: Int, itemNoun: String, language: AppLanguage = .english) -> String {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return base }
    switch language {
    case .english:
        return "\(resultCount) \(itemNoun) match '\(trimmed)'."
    case .traditionalChinese:
        return "目前有 \(resultCount) 個\(itemNoun)符合「\(trimmed)」。"
    }
}

struct WorkspaceSearchBanner: View {
    let query: String
    let resultCount: Int
    let itemNoun: String
    let clearAction: () -> Void
    @Environment(LocalizationStore.self) private var l10n

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Label(l10n.text("Search Active"), systemImage: "magnifyingglass")
                .font(.headline)
            Text("'\(query)'")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            Text("\(resultCount) \(itemNoun)")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Button(l10n.text("Clear"), action: clearAction)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}
