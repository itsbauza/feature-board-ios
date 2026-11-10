import Foundation
import StoreKit

/// Board sessions for App Store subscribers, with no backend of the app's own: the app sends the
/// subscription transaction StoreKit 2 signed, and the board checks Apple's signature, the bundle,
/// the product and the expiry before issuing a five-minute session.
public struct AppStoreSessions: Sendable {
    public enum Failure: Error, Sendable {
        /// No active subscription on this Apple Account (or none of `productIDs`).
        case noSubscription
        case invalidBoardURL
        case rejected(status: Int)
    }

    private let endpoint: URL?
    /// `/api/v1/boards/<id>/me`: everything this subscriber wrote, voted, reported or blocked.
    private let mine: URL?
    private let productIDs: Set<String>?

    /// - Parameter board: The board URL, `https://<host>/board/<id>`.
    public init(board: URL, productIDs: Set<String>? = nil) {
        self.productIDs = productIDs
        let parts = board.pathComponents
        if parts.count == 3, parts[1] == "board", var components = URLComponents(url: board, resolvingAgainstBaseURL: false) {
            components.path = "/api/v1/boards/\(parts[2])/sessions/app-store"
            components.query = nil
            components.fragment = nil
            endpoint = components.url
            components.path = "/api/v1/boards/\(parts[2])/me"
            mine = components.url
        } else {
            endpoint = nil
            mine = nil
        }
    }

    public func token() async throws -> String {
        guard let endpoint else { throw Failure.invalidBoardURL }
        let signedTransaction = try await currentSubscription()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["signedTransaction": signedTransaction])
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await URLSession.shared.data(for: request, delegate: NoRedirects())
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
        guard status == 200 else { throw Failure.rejected(status: status) }
        return try JSONDecoder().decode(Session.self, from: data).token
    }

    /// Removes everything this subscriber wrote, voted, reported or blocked on the board, for
    /// example when they delete their account in your app. Throws `noSubscription` when there is
    /// no active subscription to sign in with: the board then holds nothing it can tie to them here.
    public func deleteMyContent() async throws {
        try await leave(query: nil)
    }

    /// Keeps this subscriber's requests, comments and votes on the board but moves them to a new
    /// identity with no name, so nothing ties them to the person or their subscription any more.
    /// Their blocks are removed. Use it instead of `deleteMyContent()` when your app's account
    /// deletion should keep feedback. Throws like `deleteMyContent()`.
    public func anonymizeMyContent() async throws {
        try await leave(query: URLQueryItem(name: "keep", value: "posts"))
    }

    private func leave(query: URLQueryItem?) async throws {
        guard var url = mine else { throw Failure.invalidBoardURL }
        if let query { url.append(queryItems: [query]) }
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (_, response) = try await URLSession.shared.data(for: request, delegate: NoRedirects())
        guard let status = (response as? HTTPURLResponse)?.statusCode else { throw URLError(.badServerResponse) }
        guard status == 204 else { throw Failure.rejected(status: status) }
    }

    /// The latest-expiring active, unrevoked auto-renewable subscription StoreKit has verified.
    private func currentSubscription() async throws -> String {
        var best: (jws: String, expires: Date)?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.productType == .autoRenewable,
                  transaction.revocationDate == nil, productIDs?.contains(transaction.productID) ?? true else { continue }
            let expires = transaction.expirationDate ?? .distantFuture
            guard expires > .now, expires > (best?.expires ?? .distantPast) else { continue }
            best = (result.jwsRepresentation, expires)
        }
        guard let best else { throw Failure.noSubscription }
        return best.jws
    }

    private struct Session: Decodable { let token: String }

    /// The signed transaction goes only to the board's own origin.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
