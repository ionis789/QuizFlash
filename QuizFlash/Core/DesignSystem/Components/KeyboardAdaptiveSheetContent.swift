//
//  KeyboardAdaptiveSheetContent.swift
//  QuizFlash
//

import SwiftUI

/// Standard content host for custom sheets that contain text input.
///
/// It keeps the content scrollable when the keyboard reduces the available
/// height, provides interactive keyboard dismissal, and preserves the same
/// background-tap behavior across every form sheet.
struct KeyboardAdaptiveSheetContent<Content: View>: View {
    let isScrollable: Bool
    let content: Content

    init(
        isScrollable: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.isScrollable = isScrollable
        self.content = content()
    }

    var body: some View {
        Group {
            if isScrollable {
                ScrollView(showsIndicators: false) {
                    content
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            } else {
                content
                    .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .dismissKeyboardOnBackgroundTap()
    }
}
