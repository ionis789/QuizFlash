//
//  CreateExamGoalSheet.swift
//  QuizFlash
//
//  Modal sheet for creating a dated exam goal linked to one or more decks.
//

import SwiftUI
import SwiftData

// MARK: - Create Exam Goal Sheet

/// A reusable sheet for creating or editing an `ExamGoalModel`.
struct CreateExamGoalSheet: View {

    // MARK: - Environment

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    // MARK: - Input

    @Bindable var viewModel: HomeViewModel
    let decks: [DeckModel]
    let editingGoal: ExamGoalModel?

    private var isEditing: Bool {
        editingGoal != nil
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Exam Title", text: $viewModel.newExamGoalTitle)

                    TextField("Notes (Optional)", text: $viewModel.newExamGoalNote, axis: .vertical)
                        .lineLimit(3...6)

                    DatePicker(
                        "Date",
                        selection: $viewModel.newExamGoalDate,
                        displayedComponents: [.date]
                    )
                }

                if isEditing {
                    Section("Status") {
                        Picker("Goal Status", selection: $viewModel.newExamGoalStatus) {
                            ForEach(ExamGoalStatus.allCases) { status in
                                Label(status.title, systemImage: status.systemImage)
                                    .tag(status)
                            }
                        }
                        .pickerStyle(.navigationLink)
                    }
                }

                Section("Study Target") {
                    Stepper(value: $viewModel.newExamGoalTargetWorkload, in: 5...250, step: 5) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily Workload")
                            Text("\(viewModel.newExamGoalTargetWorkload) reviews per day")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Linked Decks") {
                    if decks.isEmpty {
                        Text("Create a deck first, then link it to this exam goal.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(decks) { deck in
                            Button {
                                viewModel.toggleExamGoalDeckSelection(deck.persistentModelID)
                            } label: {
                                HStack(spacing: UIConstants.Spacing.standard) {
                                    Circle()
                                        .fill(Color(hex: deck.colorHex) ?? ThemeManager.shared.accentColor.color)
                                        .frame(width: 10, height: 10)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(deck.title)
                                            .foregroundStyle(.primary)

                                        Text("\(deck.cardCount) cards")
                                            .font(.footnote)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer(minLength: 0)

                                    Image(systemName: viewModel.newExamGoalLinkedDeckIDs.contains(deck.persistentModelID) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(viewModel.newExamGoalLinkedDeckIDs.contains(deck.persistentModelID) ? ThemeManager.shared.accentColor.color : .secondary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .navigationTitle(isEditing ? "Edit Exam Goal" : "New Exam Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        viewModel.dismissExamGoalEditor()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Update" : "Save") {
                        viewModel.saveExamGoal(
                            context: context,
                            availableDecks: decks,
                            editingGoal: editingGoal
                        )
                    }
                    .disabled(isSaveDisabled)
                }
            }
        }
        .presentationDetents([.large])
    }

    // MARK: - Private

    private var isSaveDisabled: Bool {
        viewModel.newExamGoalTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        viewModel.newExamGoalLinkedDeckIDs.isEmpty
    }
}
