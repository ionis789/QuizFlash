//
//  AuthComponents.swift
//  QuizFlash
//
//  Shared UI pieces for the authentication flow.
//

import SwiftUI
import UIKit

// MARK: - Auth Icon Text Field

struct AuthIconTextField: View {
    let title: String
    let icon: String
    var isPassword = false
    @Binding var text: String

    var body: some View {
        HStack(spacing: UIConstants.Spacing.small) {
            Image(systemName: icon)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: UIConstants.Size.iconStandard)

            Group {
                if isPassword {
                    SecureField(title, text: $text)
                } else {
                    TextField(title, text: $text)
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .frame(height: UIConstants.Size.buttonHeight)
        .background(Color.primary.opacity(0.06), in: Capsule())
        .overlay {
            Capsule()
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

// MARK: - Auth Async Button

struct AuthAsyncButton: View {
    let title: String
    var icon: String?
    var tint: Color
    var foreground: Color = .white
    var isEnabled = true
    let action: @MainActor @Sendable () async throws -> Void
    let onError: @MainActor @Sendable (Error) -> Void

    @State private var isLoading = false

    var body: some View {
        Button {
            guard !isLoading else { return }

            Task { @MainActor in
                isLoading = true
                defer { isLoading = false }

                do {
                    try await action()
                } catch {
                    onError(error)
                }
            }
        } label: {
            HStack(spacing: UIConstants.Spacing.small) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body.weight(.bold))
                }

                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .opacity(isLoading ? 0 : 1)
            .overlay {
                ProgressView()
                    .tint(foreground)
                    .opacity(isLoading ? 1 : 0)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .frame(height: UIConstants.Size.buttonHeight)
            .background(tint, in: Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled || isLoading)
        .opacity(isEnabled ? 1 : 0.48)
        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isLoading)
        .animation(.easeInOut(duration: UIConstants.Animation.instant), value: isEnabled)
    }
}

// MARK: - Auth Secondary Button

struct AuthSecondaryButton: View {
    let title: String
    var icon: String?
    let action: @MainActor @Sendable () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: UIConstants.Spacing.small) {
                if let icon {
                    Image(systemName: icon)
                        .font(.body.weight(.semibold))
                }

                Text(title)
                    .font(.body.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
            }
            .foregroundStyle(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: UIConstants.Size.buttonHeight)
            .background(Color.primary.opacity(0.07), in: Capsule())
            .overlay {
                Capsule()
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Presenting View Controller Reader

struct AuthPresentingViewControllerReader: UIViewControllerRepresentable {
    let onResolve: @MainActor (UIViewController) -> Void

    func makeUIViewController(context: Context) -> ResolverViewController {
        ResolverViewController(onResolve: onResolve)
    }

    func updateUIViewController(_ uiViewController: ResolverViewController, context: Context) {
        uiViewController.onResolve = onResolve
        uiViewController.resolve()
    }

    final class ResolverViewController: UIViewController {
        var onResolve: @MainActor (UIViewController) -> Void

        init(onResolve: @escaping @MainActor (UIViewController) -> Void) {
            self.onResolve = onResolve
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            resolve()
        }

        func resolve() {
            guard let presenter = parent ?? presentingViewController ?? view.window?.rootViewController else { return }
            onResolve(presenter.topMostPresentedViewController)
        }
    }
}

private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        var controller: UIViewController = self
        while let presented = controller.presentedViewController {
            controller = presented
        }
        return controller
    }
}
