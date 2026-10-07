//
//  StoreManager.swift
//  Nightpine Spider Solitaire
//
//  Created by Jesse Ainscough on 10/6/26.
//

import Foundation
import StoreKit
import Combine

enum RemoveAdsPurchaseResult {
    case purchased
    case cancelled
    case pending
    case failed
}

@MainActor
final class StoreManager: ObservableObject {
    static let shared = StoreManager()

    static let removeAdsProductID = "remove_ads"
    
    @Published private(set) var removeAdsProduct: Product?

    private init() {
        Task {
            await listenForTransactions()
        }
    }
    
    private func listenForTransactions() async {
        for await result in Transaction.updates {
            switch result {
            case .verified(let transaction):
                if transaction.productID == Self.removeAdsProductID {
                    print("Spider Store: received verified remove_ads transaction update")
                }

                await transaction.finish()

            case .unverified(_, let error):
                print("Spider Store: unverified transaction update: \(error)")
            }
        }
    }
    
    func loadProducts() async {
        do {
            let products = try await Product.products(
                for: [Self.removeAdsProductID]
            )

            removeAdsProduct = products.first {
                $0.id == Self.removeAdsProductID
            }

            if let removeAdsProduct {
                print("Spider Store: loaded \(removeAdsProduct.id) at \(removeAdsProduct.displayPrice)")
            } else {
                print("Spider Store: remove_ads product not found")
            }
        } catch {
            print("Spider Store: failed to load products: \(error)")
        }
    }
    
    func purchaseRemoveAds() async -> RemoveAdsPurchaseResult {
        guard let product = removeAdsProduct else {
            print("Spider Store: remove_ads product is not loaded")
            return .failed
        }

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    await transaction.finish()
                    print("Spider Store: remove_ads purchase verified")
                    return .purchased

                case .unverified:
                    print("Spider Store: remove_ads purchase could not be verified")
                    return .failed
                }

            case .userCancelled:
                print("Spider Store: remove_ads purchase cancelled")
                return .cancelled

            case .pending:
                print("Spider Store: remove_ads purchase pending")
                return .pending

            @unknown default:
                print("Spider Store: unknown purchase result")
                return .failed
            }
        } catch {
            print("Spider Store: purchase failed: \(error)")
            return .failed
        }
    }
    
    func hasRemoveAdsEntitlement() async -> Bool {
        for await result in Transaction.currentEntitlements {
            switch result {
            case .verified(let transaction):
                if transaction.productID == Self.removeAdsProductID {
                    print("Spider Store: remove_ads entitlement found")
                    return true
                }

            case .unverified:
                continue
            }
        }

        print("Spider Store: remove_ads entitlement not found")
        return false
    }
}

