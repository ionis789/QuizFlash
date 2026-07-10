//
//  AuthErrorPresentation.swift
//  QuizFlash
//
//  User-facing authentication error copy.
//

import FirebaseAuth
import Foundation
import GoogleSignIn

enum AuthErrorPresentation {
    static func message(for error: Error, locale: Locale) -> String {
        if let managerError = error as? AuthManagerError {
            return AppLocalization.string(messageKey(for: managerError), locale: locale)
        }

        let nsError = error as NSError
        if nsError.domain == AuthErrorDomain,
           let authCode = AuthErrorCode(rawValue: nsError.code) {
            return AppLocalization.string(messageKey(for: authCode), locale: locale)
        }

        if nsError.domain == kGIDSignInErrorDomain {
            return AppLocalization.string(messageKeyForGoogleSignIn(code: nsError.code), locale: locale)
        }

        return AppLocalization.string("Please try again in a moment.", locale: locale)
    }

    private static func messageKey(for error: AuthManagerError) -> String {
        switch error {
        case .missingCurrentUser:
            "Please sign in again to continue."
        case .missingPresenter:
            "Please wait a moment and try again."
        case .passwordConfirmationMismatch:
            "Passwords do not match."
        case .missingGoogleClientID:
            "Google sign-in is not ready yet. Please try email sign-in."
        case .googleSignInTimedOut, .firebaseSignInTimedOut:
            "Google sign-in took too long. Please try again."
        case .missingCredential, .missingAppleIdentityToken, .invalidAppleIdentityToken:
            "We could not finish sign-in. Please try again."
        }
    }

    private static func messageKey(for code: AuthErrorCode) -> String {
        switch code {
        case .invalidEmail, .missingEmail, .invalidRecipientEmail:
            "Enter a valid email address."
        case .wrongPassword, .invalidCredential, .rejectedCredential:
            "The email or password is incorrect."
        case .userNotFound:
            "No account was found for this email."
        case .userDisabled:
            "This account is currently disabled."
        case .emailAlreadyInUse:
            "An account with this email already exists."
        case .weakPassword:
            "Use a stronger password."
        case .tooManyRequests:
            "Too many attempts. Please wait a bit and try again."
        case .networkError, .webNetworkRequestFailed:
            "Check your internet connection and try again."
        case .operationNotAllowed:
            "This sign-in method is not available right now."
        case .accountExistsWithDifferentCredential, .credentialAlreadyInUse:
            "This sign-in method is already linked to another account."
        case .requiresRecentLogin, .invalidUserToken, .userTokenExpired:
            "Please sign in again to continue."
        case .webContextCancelled:
            "Sign-in was cancelled."
        case .webContextAlreadyPresented:
            "A sign-in window is already open."
        case .appNotAuthorized, .invalidAPIKey, .invalidClientID, .unauthorizedDomain:
            "Sign-in is not ready yet. Please try again later."
        default:
            "Please try again in a moment."
        }
    }

    private static func messageKeyForGoogleSignIn(code: Int) -> String {
        if code == GIDSignInError.canceled.rawValue {
            return "Sign-in was cancelled."
        }

        return "We could not finish Google sign-in. Please try again."
    }
}
