//
//  LoginViewModel.swift
//  BlotMac
//
//  State of the auth flow: «09 · Sign up», «10 · Log in», «11 · Verify email».
//

import Foundation
import Observation
import BlotDesign
import SwiftUI

enum AuthScreen: Equatable {
    case signUp
    case logIn
    case verify
    case reset
}

@MainActor
@Observable
final class LoginViewModel {
    // Navigation
    var screen: AuthScreen = .logIn

    // Fields
    var email = ""
    var password = ""
    var staySignedIn = true
    var code = "" {
        didSet {
            let digits = String(code.filter(\.isNumber).prefix(Self.codeLength))
            if digits != code { code = digits; return }
            if screen == .verify, code.count == Self.codeLength, oldValue.count < Self.codeLength { verify() }
        }
    }

    // Status
    private(set) var isLoading = false
    private(set) var error: String?
    private(set) var resendSeconds = 0
    /// Set when sign-in succeeds; the view hands it to AppState.
    private(set) var signedInUser: AuthUser?

    static let codeLength = 6
    private let service: any AuthService
    private var countdown: Task<Void, Never>?
    /// Screen to return to from «Use a different email».
    private var verifyOrigin: AuthScreen = .signUp

    init(service: (any AuthService)? = nil, lastEmail: String = "") {
        self.service = service ?? LiveAuthService()
        self.email = lastEmail
    }

    // MARK: Derived

    var isEmailValid: Bool {
        email.trimmingCharacters(in: .whitespaces)
            .range(of: "^[^@\\s]+@[^@\\s]+\\.[^@\\s]{2,}$", options: .regularExpression) != nil
    }

    var canSubmitCode: Bool { code.count == Self.codeLength && !isLoading }

    var resendLabel: String {
        resendSeconds > 0
            ? "Didn't get it? Resend in \(resendSeconds / 60):\(String(format: "%02d", resendSeconds % 60))"
            : "Didn't get it? Resend code"
    }

    // MARK: Navigation

    func show(_ screen: AuthScreen) {
        error = nil
        password = ""
        withAnimation(KMotion.standard) { self.screen = screen }
    }

    func useDifferentEmail() {
        countdown?.cancel()
        code = ""
        show(verifyOrigin)
    }

    // MARK: Actions

    /// «Log in» with email and password.
    func logIn() {
        guard !isLoading else { return }
        guard isEmailValid else { return fail(.invalidEmail) }
        guard !password.isEmpty else { return fail(.emptyPassword) }
        run {
            try await self.service.logIn(email: self.normalizedEmail, password: self.password, remember: self.staySignedIn)
        }
    }

    /// «Continue with email» on sign up, or «Email me a sign-in code instead» on log in.
    func sendCode() {
        guard !isLoading else { return }
        guard isEmailValid else { return fail(.invalidEmail) }
        verifyOrigin = screen == .verify ? verifyOrigin : screen
        error = nil
        isLoading = true
        Task {
            do {
                if screen == .signUp {
                    guard password.count >= 12 else { throw AuthError.emptyPassword }
                    try await service.register(email: normalizedEmail, password: password)
                } else { try await service.sendCode(to: normalizedEmail) }
                isLoading = false
                code = ""
                startCountdown()
                withAnimation(KMotion.standard) { screen = .verify }
            } catch {
                isLoading = false
                self.error = error.localizedDescription
            }
        }
    }

    func resendCode() {
        guard resendSeconds == 0, !isLoading else { return }
        code = ""
        sendCode()
    }

    func verify() {
        guard canSubmitCode else { return }
        let entered = code
        isLoading = true
        error = nil
        Task {
            do {
                try await service.verify(code: entered, email: normalizedEmail)
                countdown?.cancel()
                code = ""
                screen = .logIn
            } catch { self.error = error.localizedDescription; code = "" }
            isLoading = false
        }
    }

    func requestPasswordReset() {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        Task {
            do {
                try await service.requestReset(email: normalizedEmail)
                code = ""
                password = ""
                screen = .reset
            } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }

    func resetPassword() {
        guard !isLoading, code.count == Self.codeLength else { return }
        isLoading = true
        error = nil
        Task {
            do {
                try await service.reset(email: normalizedEmail, code: code, password: password)
                screen = .logIn
                code = ""
            } catch { self.error = error.localizedDescription }
            isLoading = false
        }
    }

    // MARK: Helpers

    private var normalizedEmail: String {
        email.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private func fail(_ error: AuthError) {
        withAnimation(KMotion.quick) { self.error = error.errorDescription }
    }

    private func run(clearCodeOnError: Bool = false, _ operation: @escaping () async throws -> AuthUser) {
        error = nil
        isLoading = true
        Task {
            do {
                let user = try await operation()
                countdown?.cancel()
                isLoading = false
                signedInUser = user
            } catch {
                isLoading = false
                if clearCodeOnError { code = "" }
                withAnimation(KMotion.quick) { self.error = error.localizedDescription }
            }
        }
    }

    private func startCountdown() {
        countdown?.cancel()
        resendSeconds = 60
        countdown = Task {
            while !Task.isCancelled, resendSeconds > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                resendSeconds -= 1
            }
        }
    }
}
