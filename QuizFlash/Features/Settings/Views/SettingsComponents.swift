//
//  SettingsComponents.swift
//  QuizFlash
//
//  Shared cards and rows used across the Settings feature.
//

import SwiftUI

// MARK: - Settings Chrome Metrics

enum SettingsChromeMetrics {
    static let pillRevealClearance: CGFloat = 60
}

enum SettingsTextContent: Sendable, ExpressibleByStringLiteral {
    case localized(LocalizedStringResource)
    case verbatim(String)

    init(_ resource: LocalizedStringResource) {
        self = .localized(resource)
    }

    init(verbatim value: String) {
        self = .verbatim(value)
    }

    init(stringLiteral value: String) {
        self = .localized(LocalizedStringResource(stringLiteral: value))
    }

    nonisolated static func localizedLiteral(_ value: String) -> SettingsTextContent {
        .localized(LocalizedStringResource(stringLiteral: value))
    }
}

private struct SettingsTextLabel: View {
    let content: SettingsTextContent

    var body: some View {
        switch content {
        case .localized(let resource):
            Text(resource)
        case .verbatim(let value):
            Text(verbatim: value)
        }
    }
}

// MARK: - Settings Header Card

struct SettingsHeaderCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let title: SettingsTextContent
    let subtitle: SettingsTextContent?
    let tint: Color
    let badges: [SettingsTextContent]

    init(
        icon: String,
        title: SettingsTextContent,
        subtitle: SettingsTextContent?,
        tint: Color,
        badges: [SettingsTextContent]
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.badges = badges
    }

    init(
        icon: String,
        title: String,
        subtitle: String?,
        tint: Color,
        badges: [String]
    ) {
        self.init(
            icon: icon,
            title: .localizedLiteral(title),
            subtitle: subtitle.map(SettingsTextContent.localizedLiteral),
            tint: tint,
            badges: badges.map(SettingsTextContent.localizedLiteral)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.large) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                ZStack {
                    RoundedRectangle(cornerRadius: UIConstants.Radius.large, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [tint.opacity(0.26), tint.opacity(0.10)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 62, height: 62)

                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                    SettingsTextLabel(content: title)
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .foregroundStyle(themeManager.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let subtitle {
                        SettingsTextLabel(content: subtitle)
                            .font(.body.weight(.medium))
                            .foregroundStyle(themeManager.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if !badges.isEmpty {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 110), spacing: UIConstants.Spacing.small)],
                    alignment: .leading,
                    spacing: UIConstants.Spacing.small
                ) {
                    ForEach(Array(badges.enumerated()), id: \.offset) { _, badge in
                        SettingsBadge(title: badge)
                    }
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.maximum)
    }
}

// MARK: - Settings Section Card

struct SettingsSectionCard<Content: View>: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: SettingsTextContent
    let subtitle: SettingsTextContent?
    @ViewBuilder let content: () -> Content

    init(
        title: SettingsTextContent,
        subtitle: SettingsTextContent?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content
    }

    init(
        title: String,
        subtitle: String?,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: .localizedLiteral(title),
            subtitle: subtitle.map(SettingsTextContent.localizedLiteral),
            content: content
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.medium) {
            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                SettingsTextLabel(content: title)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(themeManager.textPrimary)

                if let subtitle {
                    SettingsTextLabel(content: subtitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            content()
        }
        .padding(UIConstants.Spacing.large)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }
}

// MARK: - Settings Rows

struct SettingsNavigationRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: SettingsTextContent
    let detail: SettingsTextContent?
    let value: String?

    init(
        icon: String,
        tint: Color,
        title: SettingsTextContent,
        detail: SettingsTextContent?,
        value: String?
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        self.value = value
    }

    init(
        icon: String,
        tint: Color,
        title: String,
        detail: String?,
        value: String?
    ) {
        self.init(
            icon: icon,
            tint: tint,
            title: .localizedLiteral(title),
            detail: detail.map(SettingsTextContent.localizedLiteral),
            value: value
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            SettingsRowIcon(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                SettingsTextLabel(content: title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)

                if let detail {
                    SettingsTextLabel(content: detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            if let value, !value.isEmpty {
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(themeManager.textSecondary)
                    .lineLimit(1)
                    .multilineTextAlignment(.trailing)
            }

            Image(systemName: "chevron.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(themeManager.textSecondary.opacity(0.72))
        }
        .contentShape(Rectangle())
    }
}

struct SettingsToggleRow: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: SettingsTextContent
    let detail: SettingsTextContent?
    @Binding var isOn: Bool

    init(
        icon: String,
        tint: Color,
        title: SettingsTextContent,
        detail: SettingsTextContent?,
        isOn: Binding<Bool>
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        _isOn = isOn
    }

    init(
        icon: String,
        tint: Color,
        title: String,
        detail: String?,
        isOn: Binding<Bool>
    ) {
        self.init(
            icon: icon,
            tint: tint,
            title: .localizedLiteral(title),
            detail: detail.map(SettingsTextContent.localizedLiteral),
            isOn: isOn
        )
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
                SettingsRowIcon(icon: icon, tint: tint)

                VStack(alignment: .leading, spacing: 4) {
                    SettingsTextLabel(content: title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(themeManager.textPrimary)

                    if let detail {
                        SettingsTextLabel(content: detail)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(themeManager.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .tint(tint)
    }
}

struct SettingsMenuPickerRow<Option: Identifiable & Hashable>: View {
    @Environment(AppPreferences.self) private var appPreferences
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let title: SettingsTextContent
    let detail: SettingsTextContent?
    @Binding var selection: Option
    let options: [Option]
    let titleForOption: (Option, Locale) -> String

    init(
        icon: String,
        tint: Color,
        title: SettingsTextContent,
        detail: SettingsTextContent? = nil,
        selection: Binding<Option>,
        options: [Option],
        titleForOption: @escaping (Option, Locale) -> String
    ) {
        self.icon = icon
        self.tint = tint
        self.title = title
        self.detail = detail
        _selection = selection
        self.options = options
        self.titleForOption = titleForOption
    }

    init(
        icon: String,
        tint: Color,
        title: String,
        detail: String? = nil,
        selection: Binding<Option>,
        options: [Option],
        titleForOption: @escaping (Option, Locale) -> String
    ) {
        self.init(
            icon: icon,
            tint: tint,
            title: .localizedLiteral(title),
            detail: detail.map(SettingsTextContent.localizedLiteral),
            selection: selection,
            options: options,
            titleForOption: titleForOption
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: UIConstants.Spacing.medium) {
            SettingsRowIcon(icon: icon, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                SettingsTextLabel(content: title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(themeManager.textPrimary)

                if let detail {
                    SettingsTextLabel(content: detail)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(themeManager.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: UIConstants.Spacing.standard)

            Menu {
                ForEach(options) { option in
                    Button {
                        selection = option
                    } label: {
                        if selection == option {
                            Label(
                                titleForOption(option, appPreferences.resolvedLocale),
                                systemImage: "checkmark"
                            )
                        } else {
                            Text(titleForOption(option, appPreferences.resolvedLocale))
                        }
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(titleForOption(selection, appPreferences.resolvedLocale))
                        .font(.caption.weight(.semibold))
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .foregroundStyle(themeManager.textPrimary)
                .padding(.horizontal, UIConstants.Spacing.standard)
                .padding(.vertical, UIConstants.Spacing.small)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
    }
}

struct SettingsInfoCard: View {
    @Environment(ThemeManager.self) private var themeManager

    let icon: String
    let tint: Color
    let text: SettingsTextContent

    init(icon: String, tint: Color, text: SettingsTextContent) {
        self.icon = icon
        self.tint = tint
        self.text = text
    }

    init(icon: String, tint: Color, text: String) {
        self.init(icon: icon, tint: tint, text: .localizedLiteral(text))
    }

    var body: some View {
        HStack(alignment: .top, spacing: UIConstants.Spacing.medium) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(tint)

            SettingsTextLabel(content: text)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(themeManager.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Spacing.standard)
        .settingsCardBackground(cornerRadius: UIConstants.Radius.large)
    }
}

struct SettingsCardDivider: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        Rectangle()
            .fill(themeManager.roleColor(.settingsCardBorder).opacity(0.16))
            .frame(height: 1)
            .padding(.leading, 54)
    }
}

// MARK: - Small Shared Pieces

private struct SettingsBadge: View {
    @Environment(ThemeManager.self) private var themeManager

    let title: SettingsTextContent

    var body: some View {
        SettingsTextLabel(content: title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(themeManager.textPrimary)
            .padding(.horizontal, UIConstants.Spacing.standard)
            .padding(.vertical, UIConstants.Spacing.small)
            .background(.ultraThinMaterial, in: Capsule())
    }
}

struct SettingsRowIcon: View {
    let icon: String
    let tint: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous)
                .fill(tint.opacity(0.14))
                .frame(width: 40, height: 40)

            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
        }
    }
}

struct CompactTextSizeSliderControl: View {
    @Binding var textSize: FlashcardTextSize
    var isDense = false

    private var trackHeight: CGFloat { isDense ? 6 : 8 }
    private var thumbWidth: CGFloat { isDense ? 42 : 58 }
    private var thumbHeight: CGFloat { isDense ? 24 : 34 }

    private var progress: CGFloat {
        CGFloat(textSize.step - FlashcardTextSize.minimumStep)
            / CGFloat(FlashcardTextSize.maximumStep - FlashcardTextSize.minimumStep)
    }

    var body: some View {
        HStack(spacing: UIConstants.Spacing.standard) {
            Text("A")
                .font(.system(size: isDense ? 16 : 22, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)

            GeometryReader { proxy in
                let width = max(proxy.size.width, 1)
                let usableWidth = max(width - thumbWidth, 1)
                let thumbX = progress * usableWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.28))
                        .frame(height: trackHeight)
                        .padding(.horizontal, thumbWidth / 2)

                    Capsule()
                        .fill(Color.white.opacity(0.68))
                        .frame(width: thumbX + thumbWidth / 2, height: trackHeight)
                        .padding(.leading, thumbWidth / 2)

                    HStack {
                        ForEach(FlashcardTextSize.minimumStep...FlashcardTextSize.maximumStep, id: \.self) { step in
                            Circle()
                                .fill(Color.black.opacity(step == textSize.step ? 0 : 0.28))
                                .frame(width: isDense ? 3 : 5, height: isDense ? 3 : 5)

                            if step != FlashcardTextSize.maximumStep {
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(.horizontal, thumbWidth / 2)
                    .offset(y: isDense ? 11 : 16)

                    Capsule()
                        .fill(Color.white)
                        .frame(width: thumbWidth, height: thumbHeight)
                        .shadow(color: Color.black.opacity(0.22), radius: 8, y: 3)
                        .offset(x: thumbX)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            updateTextSize(locationX: value.location.x, width: width)
                        }
                )
            }
            .frame(height: isDense ? 32 : 48)

            Text("A")
                .font(.system(size: isDense ? 24 : 34, weight: .bold, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, isDense ? UIConstants.Spacing.standard : UIConstants.Spacing.medium)
        .padding(.vertical, isDense ? UIConstants.Spacing.tiny : UIConstants.Spacing.standard)
        .background(Color.black.opacity(0.18), in: Capsule())
    }

    private func updateTextSize(locationX: CGFloat, width: CGFloat) {
        let usableWidth = max(width - thumbWidth, 1)
        let clampedX = min(max(locationX - thumbWidth / 2, 0), usableWidth)
        let progress = clampedX / usableWidth
        let stepSpan = FlashcardTextSize.maximumStep - FlashcardTextSize.minimumStep
        let step = FlashcardTextSize.minimumStep + Int((progress * CGFloat(stepSpan)).rounded())

        textSize = FlashcardTextSize(step: step)
    }
}

private struct SettingsCardBackgroundModifier: ViewModifier {
    @Environment(ThemeManager.self) private var themeManager

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(themeManager.roleColor(.settingsCardFill))
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(themeManager.roleColor(.settingsCardBorder).opacity(0.18), lineWidth: 0.75)
            }
    }
}

extension View {
    func settingsCardBackground(cornerRadius: CGFloat) -> some View {
        modifier(SettingsCardBackgroundModifier(cornerRadius: cornerRadius))
    }
}
