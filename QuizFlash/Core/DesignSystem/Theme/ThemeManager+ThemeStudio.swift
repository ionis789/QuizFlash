//
//  ThemeManager+ThemeStudio.swift
//  QuizFlash
//
//  Slot-oriented helpers used by the screen-first Theme Studio.
//

import SwiftUI

extension ThemeManager {
    func resolvedToken(for bindingTarget: ThemeStudioBindingTarget) -> ThemeColorToken {
        switch bindingTarget {
        case .role(let role):
            resolvedToken(for: role)
        case .token(let token):
            token
        }
    }

    func resolvedColor(for bindingTarget: ThemeStudioBindingTarget) -> Color {
        switch bindingTarget {
        case .role(let role):
            roleColor(role)
        case .token(let token):
            color(token)
        }
    }

    func canRemap(_ bindingTarget: ThemeStudioBindingTarget) -> Bool {
        if case .role = bindingTarget {
            return true
        }
        return false
    }

    func hasBindingOverride(for bindingTarget: ThemeStudioBindingTarget) -> Bool {
        switch bindingTarget {
        case .role(let role):
            hasRoleOverride(for: role)
        case .token:
            false
        }
    }

    func setBindingOverride(_ token: ThemeColorToken, for bindingTarget: ThemeStudioBindingTarget) {
        guard case .role(let role) = bindingTarget else { return }
        setRoleOverride(token, for: role)
    }

    func clearBindingOverride(for bindingTarget: ThemeStudioBindingTarget) {
        guard case .role(let role) = bindingTarget else { return }
        clearRoleOverride(for: role)
    }

    func resolvedHex(for bindingTarget: ThemeStudioBindingTarget) -> String {
        resolvedHex(for: resolvedToken(for: bindingTarget))
    }

    func defaultHex(for bindingTarget: ThemeStudioBindingTarget) -> String {
        defaultHex(for: resolvedToken(for: bindingTarget))
    }

    func hasColorOverride(for bindingTarget: ThemeStudioBindingTarget) -> Bool {
        hasColorOverride(for: resolvedToken(for: bindingTarget))
    }

    func setColorOverride(_ color: Color, for bindingTarget: ThemeStudioBindingTarget) {
        setColorOverride(color, for: resolvedToken(for: bindingTarget))
    }

    func setColorHexOverride(_ hex: String, for bindingTarget: ThemeStudioBindingTarget) {
        setColorHexOverride(hex, for: resolvedToken(for: bindingTarget))
    }

    func clearColorOverride(for bindingTarget: ThemeStudioBindingTarget) {
        clearColorOverride(for: resolvedToken(for: bindingTarget))
    }
}
