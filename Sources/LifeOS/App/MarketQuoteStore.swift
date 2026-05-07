import Foundation
import OSLog
import Observation
import LifeOSCore

@Observable
@MainActor
final class MarketQuoteStore {
    private let logger = Logger(subsystem: "local.codex.lifeos", category: "market-quotes")
    private let service = TaiwanMarketQuoteService()
    private(set) var quotesBySymbol: [String: TaiwanMarketQuote] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefreshAt: Date?
    private(set) var lastError: String?

    func refresh(for snapshots: [AssetSnapshot], force: Bool = false) async {
        let symbols = trackedSymbols(from: snapshots)
        guard symbols.isEmpty == false else {
            lastError = nil
            return
        }
        if isRefreshing && force == false {
            return
        }

        isRefreshing = true
        defer { isRefreshing = false }

        do {
            logger.info("Refreshing Taiwan quotes for \(symbols.count, privacy: .public) symbols.")
            let quotes = try await service.fetchQuotes(for: symbols)
            quotesBySymbol.merge(quotes) { _, new in new }
            lastRefreshAt = Date()
            lastError = nil
            logger.info("Taiwan quote refresh succeeded with \(quotes.count, privacy: .public) quotes.")
        } catch {
            lastError = error.localizedDescription
            logger.error("Taiwan quote refresh failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func trackedSymbols(from snapshots: [AssetSnapshot]) -> [String] {
        Array(Set(snapshots.compactMap(\.normalizedQuoteSymbol))).sorted()
    }

    func quote(for snapshot: AssetSnapshot) -> TaiwanMarketQuote? {
        guard let symbol = snapshot.normalizedQuoteSymbol else { return nil }
        return quotesBySymbol[symbol]
    }

    func liveValue(for snapshot: AssetSnapshot) -> Decimal? {
        guard let quote = quote(for: snapshot), let units = snapshot.trackedUnits else { return nil }
        return quote.lastPrice * units
    }

    func dayChange(for snapshot: AssetSnapshot) -> Decimal? {
        guard let quote = quote(for: snapshot), let previousClose = quote.previousClose else { return nil }
        return quote.lastPrice - previousClose
    }

    func dayChangePercent(for snapshot: AssetSnapshot) -> Decimal? {
        guard let change = dayChange(for: snapshot), let previousClose = quote(for: snapshot)?.previousClose, previousClose != 0 else { return nil }
        return NSDecimalNumber(decimal: change)
            .dividing(by: NSDecimalNumber(decimal: previousClose))
            .decimalValue
    }

    func positionDayChangeValue(for snapshot: AssetSnapshot) -> Decimal? {
        guard let change = dayChange(for: snapshot), let units = snapshot.trackedUnits else { return nil }
        return change * units
    }

    func displayValue(for snapshot: AssetSnapshot) -> Decimal {
        liveValue(for: snapshot) ?? snapshot.amount
    }

    func unrealizedProfit(for snapshot: AssetSnapshot) -> Decimal? {
        guard let liveValue = liveValue(for: snapshot) else { return nil }
        return liveValue - snapshot.referenceCostBasis
    }

    func unrealizedReturn(for snapshot: AssetSnapshot) -> Decimal? {
        guard let profit = unrealizedProfit(for: snapshot) else { return nil }
        let costBasis = snapshot.referenceCostBasis
        guard costBasis != 0 else { return nil }
        return NSDecimalNumber(decimal: profit)
            .dividing(by: NSDecimalNumber(decimal: costBasis))
            .decimalValue
    }

    func marketSummary(for snapshots: [AssetSnapshot]) -> MarketQuoteSummary {
        let trackedSnapshots = snapshots.filter(\.usesLiveMarketQuote)
        let liveValue = trackedSnapshots.reduce(Decimal.zero) { $0 + displayValue(for: $1) }
        let unrealized = trackedSnapshots.compactMap(unrealizedProfit(for:)).reduce(Decimal.zero, +)
        let dayChange = trackedSnapshots.compactMap(positionDayChangeValue(for:)).reduce(Decimal.zero, +)
        return MarketQuoteSummary(
            trackedCount: trackedSnapshots.count,
            liveValue: liveValue,
            unrealizedProfit: unrealized,
            dayChangeValue: dayChange,
            lastRefreshAt: lastRefreshAt,
            isRefreshing: isRefreshing,
            lastError: lastError
        )
    }
}

struct MarketQuoteSummary {
    let trackedCount: Int
    let liveValue: Decimal
    let unrealizedProfit: Decimal
    let dayChangeValue: Decimal
    let lastRefreshAt: Date?
    let isRefreshing: Bool
    let lastError: String?
}
