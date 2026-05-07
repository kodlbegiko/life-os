import Foundation

public struct TaiwanMarketQuote: Sendable, Equatable {
    public let symbol: String
    public let name: String
    public let lastPrice: Decimal
    public let previousClose: Decimal?
    public let openPrice: Decimal?
    public let highPrice: Decimal?
    public let lowPrice: Decimal?
    public let tradeDate: String?
    public let tradeTime: String?
    public let fetchedAt: Date

    public init(
        symbol: String,
        name: String,
        lastPrice: Decimal,
        previousClose: Decimal?,
        openPrice: Decimal?,
        highPrice: Decimal?,
        lowPrice: Decimal?,
        tradeDate: String?,
        tradeTime: String?,
        fetchedAt: Date = .now
    ) {
        self.symbol = symbol
        self.name = name
        self.lastPrice = lastPrice
        self.previousClose = previousClose
        self.openPrice = openPrice
        self.highPrice = highPrice
        self.lowPrice = lowPrice
        self.tradeDate = tradeDate
        self.tradeTime = tradeTime
        self.fetchedAt = fetchedAt
    }
}

public enum TaiwanMarketQuoteError: LocalizedError {
    case emptySymbolList
    case invalidResponse
    case missingQuote(symbol: String)
    case serverMessage(String)

    public var errorDescription: String? {
        switch self {
        case .emptySymbolList:
            return "No symbols were provided for quote refresh."
        case .invalidResponse:
            return "The TWSE quote service returned an unreadable response."
        case let .missingQuote(symbol):
            return "No public quote was returned for \(symbol)."
        case let .serverMessage(message):
            return message
        }
    }
}

public actor TaiwanMarketQuoteService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func fetchQuotes(for symbols: [String]) async throws -> [String: TaiwanMarketQuote] {
        let normalized = Array(Set(symbols.compactMap(Self.normalizeSymbol))).sorted()
        guard normalized.isEmpty == false else {
            throw TaiwanMarketQuoteError.emptySymbolList
        }

        let channel = normalized
            .map { "tse_\($0).tw" }
            .joined(separator: "|")

        guard var components = URLComponents(string: "https://mis.twse.com.tw/stock/api/getStockInfo.jsp") else {
            throw TaiwanMarketQuoteError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "ex_ch", value: channel),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "delay", value: "0")
        ]

        guard let url = components.url else {
            throw TaiwanMarketQuoteError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        request.setValue("Mozilla/5.0 LifeOS", forHTTPHeaderField: "User-Agent")
        request.setValue("https://mis.twse.com.tw/", forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, (200..<300).contains(httpResponse.statusCode) else {
            throw TaiwanMarketQuoteError.invalidResponse
        }

        let envelope = try Self.decodeEnvelope(from: data)
        guard envelope.rtcode == "0000" else {
            throw TaiwanMarketQuoteError.serverMessage(envelope.rtmessage)
        }

        let fetchedAt = Date()
        let quotes = envelope.msgArray.compactMap { message -> (String, TaiwanMarketQuote)? in
            guard let symbol = Self.normalizeSymbol(message.c) else { return nil }
            guard let lastPrice = Self.decimal(fromMIS: message.z) ?? Self.decimal(fromMIS: message.y) else { return nil }
            let quote = TaiwanMarketQuote(
                symbol: symbol,
                name: message.n,
                lastPrice: lastPrice,
                previousClose: Self.decimal(fromMIS: message.y),
                openPrice: Self.decimal(fromMIS: message.o),
                highPrice: Self.decimal(fromMIS: message.h),
                lowPrice: Self.decimal(fromMIS: message.l),
                tradeDate: Self.clean(message.d),
                tradeTime: Self.clean(message.t),
                fetchedAt: fetchedAt
            )
            return (symbol, quote)
        }

        let quoteMap = Dictionary(uniqueKeysWithValues: quotes)
        for symbol in normalized where quoteMap[symbol] == nil {
            throw TaiwanMarketQuoteError.missingQuote(symbol: symbol)
        }
        return quoteMap
    }

    public static func decodeEnvelope(from data: Data) throws -> TWSEQuoteEnvelope {
        let decoder = JSONDecoder()
        return try decoder.decode(TWSEQuoteEnvelope.self, from: data)
    }

    public static func normalizeSymbol(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func decimal(fromMIS raw: String?) -> Decimal? {
        guard let cleaned = clean(raw) else { return nil }
        return Decimal(string: cleaned)
    }

    public static func clean(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != "-" else { return nil }
        return trimmed
    }
}

public struct TWSEQuoteEnvelope: Decodable, Sendable {
    public let msgArray: [TWSEQuoteMessage]
    public let rtcode: String
    public let rtmessage: String
}

public struct TWSEQuoteMessage: Decodable, Sendable {
    public let c: String
    public let n: String
    public let z: String?
    public let y: String?
    public let o: String?
    public let h: String?
    public let l: String?
    public let d: String?
    public let t: String?
}
