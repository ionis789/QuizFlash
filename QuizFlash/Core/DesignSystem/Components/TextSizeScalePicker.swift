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
    @State private var liveTextSize: FlashcardTextSize
    @State private var isInteracting = false

    init(
        textSize: FlashcardTextSize,
        previewText: String,
        onChange: @escaping (FlashcardTextSize) -> Void
    ) {
        self.textSize = textSize
        self.previewText = previewText
        self.onChange = onChange
        _liveTextSize = State(initialValue: textSize)
    }

    private var selection: Binding<Int> {
        Binding(
            get: { liveTextSize.step },
            set: { liveTextSize = FlashcardTextSize(step: $0) }
        )
    }

    private var pickerConfig: TickPickerConfig {
        TickPickerConfig(
            tickWidth: 2,
            tickHeight: 24,
            tickHPadding: 8,
            inActiveHeightProgress: 0.46,
            interactionHeight: 48,
            tickAreaTopPadding: UIConstants.Spacing.medium,
            inActiveTint: .primary,
            alignment: .center
        )
    }

    var body: some View {
        VStack(spacing: UIConstants.Spacing.small) {
            Text(previewText)
                .font(
                    .system(
                        size: 17 * CGFloat(liveTextSize.playModeScale),
                        weight: .semibold,
                        design: .rounded
                    )
                )
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.74)
                .frame(maxWidth: .infinity, minHeight: 54)
                .animation(.smooth(duration: 0.16, extraBounce: 0), value: liveTextSize.step)

            HStack(alignment: .center, spacing: UIConstants.Spacing.standard) {
                Text("A")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(
                        width: UIConstants.Size.iconLarge,
                        height: pickerConfig.interactionHeight,
                        alignment: .center
                    )
                    .accessibilityHidden(true)

                TickPicker(
                    count: FlashcardTextSize.maximumStep - FlashcardTextSize.minimumStep,
                    config: pickerConfig,
                    selection: selection,
                    highlightedRange: nil,
                    onEditingChanged: handleEditingChanged
                )
                .accessibilityLabel("Text Size")
                .accessibilityValue("\(liveTextSize.step + 1) of \(FlashcardTextSize.allCases.count)")

                Text("A")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                    .frame(
                        width: UIConstants.Size.iconLarge,
                        height: pickerConfig.interactionHeight,
                        alignment: .center
                    )
                    .accessibilityHidden(true)
            }
        }
        .padding(.horizontal, UIConstants.Spacing.tiny)
        .onChange(of: textSize) { _, newValue in
            guard !isInteracting else { return }
            liveTextSize = newValue
        }
    }

    private func handleEditingChanged(_ isEditing: Bool) {
        isInteracting = isEditing

        guard !isEditing, liveTextSize != textSize else { return }
        onChange(liveTextSize)
    }
}
