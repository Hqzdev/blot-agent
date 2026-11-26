import Foundation

/// A purchase approval is independent of Ori subscription billing and contains no card secrets.
public struct WorkspacePurchaseOrder: Codable, Equatable, Sendable {
    public struct Item: Codable, Equatable, Sendable {
        public let title: String
        public let quantity: Int
        public let unitAmountMinor: Int
        public init(title: String, quantity: Int, unitAmountMinor: Int) {
            self.title = title; self.quantity = quantity; self.unitAmountMinor = unitAmountMinor
        }
    }
    public let merchant: String
    public let checkoutURL: URL
    public let currency: String
    public let items: [Item]
    public let taxMinor: Int
    public let deliveryMinor: Int
    public let totalMinor: Int
    public init(merchant: String, checkoutURL: URL, currency: String, items: [Item], taxMinor: Int, deliveryMinor: Int, totalMinor: Int) {
        self.merchant = merchant; self.checkoutURL = checkoutURL; self.currency = currency; self.items = items
        self.taxMinor = taxMinor; self.deliveryMinor = deliveryMinor; self.totalMinor = totalMinor
    }
    public func validate() throws {
        guard !merchant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, merchant.utf8.count <= 400,
              (try? WorkspaceBrowserURL.validated(checkoutURL.absoluteString)) != nil,
              ["RUB", "USD", "EUR", "GBP"].contains(currency),
              (1...100).contains(items.count), (1...1_000_000_000_000).contains(totalMinor),
              taxMinor >= 0, deliveryMinor >= 0 else { throw WorkspaceStorageError.invalidParameters }
        var sum: Int64 = 0
        for item in items {
            guard !item.title.isEmpty, item.title.utf8.count <= 800, (1...10_000).contains(item.quantity),
                  (0...1_000_000_000).contains(item.unitAmountMinor) else { throw WorkspaceStorageError.invalidParameters }
            sum += Int64(item.quantity) * Int64(item.unitAmountMinor)
        }
        guard taxMinor <= totalMinor, deliveryMinor <= totalMinor,
              sum + Int64(taxMinor) + Int64(deliveryMinor) == Int64(totalMinor) else { throw WorkspaceStorageError.invalidParameters }
    }
}
