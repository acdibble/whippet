import Foundation
import Observation

/// Keeps the latest exchange rates for currency conversion, saved so conversions work offline, and fetches new ones at
/// launch and every few hours after. The ECB publishes once each working day, so checking more often would only
/// fetch the same rates again.
@MainActor
@Observable
final class ExchangeRateStore {
    private(set) var rates: ExchangeRates?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// Saved with the time apart from the rates, as 1.1.0 did.
    private struct Saved: Codable {
        let rates: ExchangeRates
        let fetchedAt: Date
    }

    private static let defaultsKey = "exchangeRates"
    private static let refreshInterval: Duration = .seconds(6 * 60 * 60)
    /// How often to look at whether the rates are due, which also retries a failed fetch.
    private static let checkInterval: Duration = .seconds(60 * 60)
    /// Fetched without cookies, as the ECB needs none.
    private static let session = URLSession(configuration: .ephemeral)

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            rates = saved.rates
            rates?.fetchedAt = saved.fetchedAt
        }
    }

    func start() {
        guard refreshTask == nil else { return }
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshIfDue()
                try? await Task.sleep(for: Self.checkInterval)
            }
        }
    }

    private func refreshIfDue() async {
        let interval = TimeInterval(Self.refreshInterval.components.seconds)
        if let fetchedAt = rates?.fetchedAt, Date.now.timeIntervalSince(fetchedAt) < interval { return }
        let request = URLRequest(url: ExchangeRates.sourceURL, timeoutInterval: 30)
        guard
            let (data, response) = try? await Self.session.data(for: request),
            (response as? HTTPURLResponse)?.statusCode == 200,
            var rates = ExchangeRates(ecbXML: String(decoding: data, as: UTF8.self))
        else { return }
        let fetchedAt = Date.now
        rates.fetchedAt = fetchedAt
        self.rates = rates
        if let data = try? JSONEncoder().encode(Saved(rates: rates, fetchedAt: fetchedAt)) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }
}
