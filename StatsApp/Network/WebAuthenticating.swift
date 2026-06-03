import Foundation
import AppKit
import AuthenticationServices

/// Абстракция над ASWebAuthenticationSession — для тестируемости AuthService.
protocol WebAuthenticating {
    func authenticate(url: URL, callbackScheme: String) async throws -> URL
}

/// Production-реализация. @MainActor — ASWebAuthenticationSession требует main thread
/// и presentation anchor.
@MainActor
final class ASWebAuthenticator: NSObject, WebAuthenticating, ASWebAuthenticationPresentationContextProviding {
    private var session: ASWebAuthenticationSession?
    private var anchor: NSWindow?

    func authenticate(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url, callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    cont.resume(returning: callbackURL)
                } else if let asError = error as? ASWebAuthenticationSessionError,
                          asError.code == .canceledLogin {
                    cont.resume(throwing: AuthError.cancelled)
                } else {
                    cont.resume(throwing: error ?? AuthError.cancelled)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            if !session.start() {
                cont.resume(throwing: AuthError.cannotStart)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let anchor { return anchor }
        let w = NSApp.windows.first ?? NSWindow(
            contentRect: .zero, styleMask: [.titled], backing: .buffered, defer: true
        )
        anchor = w
        return w
    }
}
