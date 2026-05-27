//
//  LibraryLayout+CollapsedTitle.swift
//  QuizFlash
//
//  Fallback logic for the compact Library title handoff.
//

import SwiftUI

extension LibraryLayout {
    func updateHeroCollapsedBaseline(with heroMaxY: CGFloat) {
        guard !viewModel.isSearching else { return }
        guard heroMaxY > 0 else { return }
        let currentOffset = max(viewModel.savedScrollOffset, 0)
        let candidateBaseline = heroMaxY + currentOffset

        guard candidateBaseline > 0 else { return }
        guard currentOffset <= 1 || heroCollapsedBaselineMaxY == 0 else { return }
        guard abs(heroCollapsedBaselineMaxY - candidateBaseline) > 0.5 else { return }

        Task { @MainActor in
            heroCollapsedBaselineMaxY = candidateBaseline
        }
    }

    func updateCollapsedTitleFallback(for offset: CGFloat) {
        guard !viewModel.isSearching else {
            guard heroCollapsedTitleFallbackReady else { return }
            Task { @MainActor in
                heroCollapsedTitleFallbackReady = false
            }
            return
        }

        let shouldReveal: Bool
        if heroCollapsedTitleFallbackReady {
            shouldReveal = offset > collapsedTitleFallbackHideThreshold
        } else {
            shouldReveal = offset > collapsedTitleFallbackShowThreshold
        }

        guard heroCollapsedTitleFallbackReady != shouldReveal else { return }
        Task { @MainActor in
            heroCollapsedTitleFallbackReady = shouldReveal
        }
    }
}
