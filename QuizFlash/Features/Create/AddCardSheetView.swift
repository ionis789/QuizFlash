//
//  AddCardSheetView.swift
//  QuizFlash
//
//  Created by Ion Socol on 04.01.2026.
//

import SwiftUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) var dismiss
    
    // Callback closure: Passes data back to parent instead of saving to DB
    var onSave: (String, String) -> Void
    
    @State private var frontText = ""
    @State private var backText = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Question / Front", text: $frontText, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Front")
                }
                
                Section {
                    TextField("Answer / Back", text: $backText, axis: .vertical)
                        .lineLimit(2...10)
                } header: {
                    Text("Back")
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(frontText, backText)
                        dismiss()
                    }
                    .disabled(frontText.isEmpty || backText.isEmpty)
                }
            }
        }
    }
}
