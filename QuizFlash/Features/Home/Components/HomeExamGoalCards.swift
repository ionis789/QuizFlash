//
//  HomeExamGoalCards.swift
//  QuizFlash
//
//  Reusable exam-goal summary cards and narrative surfaces for the Home screen.
//

import SwiftUI

// MARK: - Home Exam Narrative Card

/// Compact narrative card that surfaces short Home insights for upcoming exam goals.
struct HomeExamNarrativeCard: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Text("Study Outlook")
                .font(.caption.weight(.black))
                .foregroundStyle(.secondary)

            ForEach(lines, id: \.self) { line in
                HStack(alignment: .top, spacing: UIConstants.Spacing.small) {
                    Circle()
                        .fill(ThemeManager.shared.accentColor.color.opacity(0.9))
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)

                    Text(line)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: 24, surfaceRole: .widget)
    }
}

// MARK: - Home Exam Pressure Card

/// Executive summary for the exam goal carrying the highest current risk.
struct HomeExamPressureCard: View {
    let summary: HomeExamPressureSummary

    private var progressTint: Color {
        if summary.readinessFraction >= 0.75 { return .green }
        if summary.readinessFraction >= 0.55 { return .orange }
        return .red
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Exam Pressure")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    Text(summary.goalTitle)
                        .font(.title3.weight(.heavy))
                        .fontDesign(.rounded)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(summary.headline) • \(summary.countdownLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(progressTint)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(Int((summary.readinessFraction * 100).rounded()))%")
                        .font(.system(size: 28, weight: .heavy, design: .rounded))
                        .foregroundStyle(progressTint)
                        .monospacedDigit()
                        .statusTextMotion(trigger: Int((summary.readinessFraction * 100).rounded()))

                    Text("readiness")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(summary.detailLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(summary.actionLine)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: UIConstants.Spacing.small) {
                pressureMetricChip(title: "Overdue", value: "\(summary.overdueCards)", tint: .orange)
                pressureMetricChip(
                    title: "Pace",
                    value: summary.dailyPaceNeeded == 0 ? "steady" : "\(summary.dailyPaceNeeded)/day",
                    tint: ThemeManager.shared.accentColor.color
                )
                pressureMetricChip(title: "Risk Decks", value: "\(summary.belowTargetDeckCount)", tint: .red)
            }

            if let weakestDeckTitle = summary.weakestDeckTitle {
                HStack(spacing: UIConstants.Spacing.small) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(progressTint)

                    Text("Weakest deck: \(weakestDeckTitle)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if let weakestDeckReadinessFraction = summary.weakestDeckReadinessFraction {
                        Text("\(Int((weakestDeckReadinessFraction * 100).rounded()))%")
                            .font(.footnote.weight(.black))
                            .foregroundStyle(progressTint)
                            .monospacedDigit()
                    }
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: 24, surfaceRole: .widget)
    }

    private func pressureMetricChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
    }
}

// MARK: - Home Exam Goal Summary Card

/// One Home dashboard card summarizing readiness for a single upcoming exam goal.
struct HomeExamGoalSummaryCard: View {
    let summary: HomeExamGoalSummary
    var onEdit: () -> Void
    var onStatusChange: (ExamGoalStatus) -> Void

    private var progressTint: Color {
        if summary.readinessFraction >= 0.75 { return .green }
        if summary.readinessFraction >= 0.55 { return .orange }
        return .red
    }

    private var statusTint: Color {
        switch summary.status {
        case .active:
            return .blue
        case .completed:
            return .green
        case .archived:
            return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            HStack(alignment: .top, spacing: UIConstants.Spacing.standard) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(.headline.weight(.heavy))
                        .fontDesign(.rounded)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("\(summary.countdownLabel) • \(summary.dateLabel)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: UIConstants.Spacing.small) {
                    Text(summary.status.title.uppercased())
                        .font(.caption2.weight(.black))
                        .foregroundStyle(statusTint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(statusTint.opacity(0.12), in: Capsule())

                    examGoalMenu
                }
            }

            VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
                HStack {
                    Text("READINESS")
                        .font(.caption.weight(.black))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    Text("\(Int((summary.readinessFraction * 100).rounded()))%")
                        .font(.caption.weight(.black))
                        .foregroundStyle(progressTint)
                        .monospacedDigit()
                        .statusTextMotion(trigger: Int((summary.readinessFraction * 100).rounded()))
                }

                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.primary.opacity(0.08))

                        Capsule()
                            .fill(progressTint.gradient)
                            .frame(width: proxy.size.width * max(0, min(summary.readinessFraction, 1)))
                    }
                }
                .frame(height: 8)
            }

            Text(summary.summaryLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            if summary.hasNote {
                Text(summary.note)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: UIConstants.Spacing.small) {
                examGoalMetricChip(
                    title: "Decks",
                    value: "\(summary.linkedDeckCount)",
                    tint: ThemeManager.shared.accentColor.color
                )
                examGoalMetricChip(
                    title: "Overdue",
                    value: "\(summary.overdueCount)",
                    tint: .orange
                )
                examGoalMetricChip(
                    title: "Target",
                    value: "\(summary.targetWorkload)/day",
                    tint: .blue
                )
            }

            if let weakestDeck = summary.weakestDeck {
                HStack(spacing: UIConstants.Spacing.small) {
                    Circle()
                        .fill(Color(hex: weakestDeck.colorHex) ?? .secondary)
                        .frame(width: 10, height: 10)

                    Text("Weakest linked deck: \(weakestDeck.title)")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    Text("\(Int((weakestDeck.readinessFraction * 100).rounded()))%")
                        .font(.footnote.weight(.black))
                        .foregroundStyle(progressTint)
                        .monospacedDigit()
                }
            }
        }
        .padding(UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: 24, surfaceRole: .widget)
    }

    private var examGoalMenu: some View {
        Menu {
            Button {
                onEdit()
            } label: {
                Label("Edit Goal", systemImage: "pencil")
            }

            Divider()

            ForEach(ExamGoalStatus.allCases) { status in
                if status != summary.status {
                    Button {
                        onStatusChange(status)
                    } label: {
                        Label(statusMenuTitle(for: status), systemImage: status.systemImage)
                    }
                }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private func statusMenuTitle(for status: ExamGoalStatus) -> String {
        switch status {
        case .active:
            return "Mark Active"
        case .completed:
            return "Mark Completed"
        case .archived:
            return "Archive Goal"
        }
    }

    private func examGoalMetricChip(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title.uppercased())
                .font(.caption2.weight(.black))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
        }
        .padding(.horizontal, UIConstants.Spacing.standard)
        .padding(.vertical, UIConstants.Spacing.small)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: UIConstants.Radius.medium, style: .continuous))
    }
}

// MARK: - Selected Day Exam Card

/// Day-specific summary card used when the selected calendar day contains exam goals.
struct HomeSelectedDayExamCard: View {
    let summary: HomeExamGoalSummary
    var onEdit: () -> Void
    var onStatusChange: (ExamGoalStatus) -> Void

    private var statusTint: Color {
        switch summary.status {
        case .active:
            return ThemeManager.shared.accentColor.color
        case .completed:
            return .green
        case .archived:
            return .secondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.small) {
            HStack {
                Text(summary.title)
                    .font(.subheadline.weight(.heavy))
                    .foregroundStyle(.primary)

                Spacer(minLength: 0)

                HStack(spacing: UIConstants.Spacing.small) {
                    Text(summary.countdownLabel)
                        .font(.caption.weight(.black))
                        .foregroundStyle(statusTint)

                    Menu {
                        Button {
                            onEdit()
                        } label: {
                            Label("Edit Goal", systemImage: "pencil")
                        }

                        Divider()

                        ForEach(ExamGoalStatus.allCases) { status in
                            if status != summary.status {
                                Button {
                                    onStatusChange(status)
                                } label: {
                                    Label(statusMenuTitle(for: status), systemImage: status.systemImage)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            Text(summary.summaryLine)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(UIConstants.Spacing.standard)
        .flashcardStyle(cornerRadius: 20, surfaceRole: .widget)
    }

    private func statusMenuTitle(for status: ExamGoalStatus) -> String {
        switch status {
        case .active:
            return "Mark Active"
        case .completed:
            return "Mark Completed"
        case .archived:
            return "Archive Goal"
        }
    }
}

// MARK: - Empty Exam Goal Card

/// Empty-state card shown before the user creates any exam goals.
struct HomeExamGoalsEmptyCard: View {
    let usesRegularMetrics: Bool
    let onCreate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: UIConstants.Spacing.standard) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: usesRegularMetrics ? 30 : 28, weight: .black))
                .foregroundStyle(ThemeManager.shared.accentColor.color)

            Text("No exam goals yet")
                .font(.headline.weight(.heavy))
                .fontDesign(.rounded)
                .foregroundStyle(.primary)

            Text("Add an exam to track readiness across linked decks and mark that day in the Home calendar.")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button("Create Exam Goal", action: onCreate)
                .buttonStyle(.borderedProminent)
                .tint(ThemeManager.shared.accentColor.color)
        }
        .frame(maxWidth: .infinity, minHeight: usesRegularMetrics ? 210 : 0, alignment: .topLeading)
        .padding(usesRegularMetrics ? UIConstants.Spacing.extraLarge : UIConstants.Spacing.large)
        .flashcardStyle(cornerRadius: 24, surfaceRole: .widget)
    }
}
