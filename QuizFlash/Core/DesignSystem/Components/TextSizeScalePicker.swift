//
//  TextSizeScalePicker.swift
//  QuizFlash
//
//  Shared seven-step text-size control used by global and deck settings.
//

import SwiftUI

struct TextSizeScalePicker: View {
    let textSize: FlashcardTextSize
    let previewText: String
    let onChange: (FlashcardTextSize) -> Void

    private var selection: Binding<Int> {
        Binding(
            get: { textSize.step },
            set: { onChange(FlashcardTextSize(step: $0)) }
        )
    }

    private var pickerConfig: TickPickerConfig {
        TickPickerConfig(
            tickWidth: 2,
            tickHeight: 24,
            tickHPadding: 8,
            inActiveHeightProgress: 0.46,
            interactionHeight: 48,
            tickAreaTopPadding: 4,
            activeTint: ThemeManager.shared.roleColor(.labelPrimaryForeground),
            inActiveTint: .primary,
            alignment: .center
        )
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Text(previewText)
                .font(
                    .system(
                        size: 17 * CGFloat(textSize.playModeScale),
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .frame(maxWidth: .infinity, minHeight: 54)
                .statusTextMotion(trigger: textSize.step)
                .animation(.smooth(duration: 0.20, extraBounce: 0), value: textSize.step)

            HStack(alignment: .center, spacing: UIConstants.Spacing.small) {
                Text("A")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)

                TickPicker(
                    count: FlashcardTextSize.maximumStep - FlashcardTextSize.minimumStep,
                    config: pickerConfig,
                    selection: selection,
                    highlightedRange: nil
                )
                .accessibilityLabel("Text Size")
                .accessibilityValue("\(textSize.step + 1) of \(FlashcardTextSize.allCases.count)")

                Text("A")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, UIConstants.Spacing.tiny)
    }
}
