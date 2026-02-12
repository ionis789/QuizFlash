//
//  AddCardSheetView.swift
//  QuizFlash
//
//  Created by Ion Socol on 12.02.2026.
//

import SwiftUI
import PhotosUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    // Callback actualizat pentru a returna listele de CanvasItem
    var onSave: (String, String, [CanvasItem], [CanvasItem], CardContentType, CardContentType) -> Void

    // --- State ---
    @State private var frontText: String
    @State private var backText: String
    @State private var frontItems: [CanvasItem] = []
    @State private var backItems: [CanvasItem] = []
    
    // Selecție curentă
    @State private var selectedItemID: UUID? = nil
    
    @State private var activeSide: CardSide = .question
    @FocusState private var isEditorFocused: Bool
    
    // UI State
    @State private var showFabExpanded: Bool = false
    @State private var showCanvasModal: Bool = false
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var maxZIndex: Double = 0

    private var accent: Color = ThemeManager.shared.accentColor.color
    
    init(
        initialFront: String = "",
        initialBack: String = "",
        initialFrontLayout: [CanvasItem] = [],
        initialBackLayout: [CanvasItem] = [],
        initialFrontType: CardContentType = .text,
        initialBackType: CardContentType = .text,
        onSave: @escaping (String, String, [CanvasItem], [CanvasItem], CardContentType, CardContentType) -> Void
    ) {
        _frontText = State(initialValue: initialFront)
        _backText = State(initialValue: initialBack)
        _frontItems = State(initialValue: initialFrontLayout)
        _backItems = State(initialValue: initialBackLayout)
        self.onSave = onSave
    }

    enum CardSide { case question, answer }

    var body: some View {
        NavigationStack {
            ZStack {
                // Background Tap to Focus / Deselect
                Color(uiColor: .systemBackground)
                    .ignoresSafeArea()
                    .onTapGesture {
                        selectedItemID = nil // Deselectăm imaginile
                        if showFabExpanded {
                            withAnimation { showFabExpanded = false }
                        } else {
                            isEditorFocused = true // Focus tastatură
                        }
                    }

                VStack(spacing: 0) {
                    customTabBar
                        .padding(.top, 10)
                        .zIndex(100)
                    
                    // ZStack principal: Text + Canvas Items
                    GeometryReader { geo in
                        ZStack(alignment: .topLeading) {
                            
                            // LAYER 1: TEXT (Full Screen, Transparent)
                            TextEditor(text: activeSide == .question ? $frontText : $backText)
                                .font(.system(size: 22, weight: .regular))
                                .focused($isEditorFocused)
                                .scrollContentBackground(.hidden)
                                .padding(24) // Margine pentru text
                                .frame(width: geo.size.width, height: geo.size.height)
                                .zIndex(0)
                            
                            // Placeholder
                            if (activeSide == .question ? frontText : backText).isEmpty {
                                Text("Tap to type or add media...")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.tertiary)
                                    .padding(28)
                                    .allowsHitTesting(false)
                                    .zIndex(1)
                            }
                            
                            // LAYER 2: IMAGINI FREEFORM
                            // Acestea plutesc peste text și sunt poziționate relativ la centrul containerului
                            // sau la poziția salvată.
                            ForEach(activeBindingItems) { $item in
                                CanvasItemView(
                                    item: $item,
                                    isSelected: selectedItemID == item.id,
                                    onSelect: {
                                        selectedItemID = item.id
                                        bringToFront(item: $item)
                                        isEditorFocused = false // Ascundem tastatura
                                    },
                                    onDelete: {
                                        deleteItem(id: item.id)
                                    }
                                )
                                // Centrul este punctul 0,0 în CanvasItemView offset logic
                                // Dar în ZStack, trebuie să le poziționăm în centru initial
                                .position(x: geo.size.width / 2, y: geo.size.height / 2)
                            }
                            .zIndex(10)
                        }
                    }
                }
            }
            .overlay(alignment: .bottomTrailing) {
                fabLayer.padding(30)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveCard() }
                        .fontWeight(.bold)
                        .foregroundStyle(accent)
                }
            }
            .fullScreenCover(isPresented: $showCanvasModal) {
                CanvasModalView { imageData in
                    addItem(imageData: imageData)
                }
            }
            .photosPicker(isPresented: .constant(selectedPhotoItem != nil), selection: $selectedPhotoItem, matching: .images)
            .onChange(of: selectedPhotoItem) { _, newItem in
                processPhoto(newItem)
            }
        }
    }
    
    // MARK: - Logic
    
    var activeBindingItems: Binding<[CanvasItem]> {
        activeSide == .question ? $frontItems : $backItems
    }
    
    private func addItem(imageData: Data) {
        maxZIndex += 1
        let newItem = CanvasItem(imageData: imageData, zIndex: maxZIndex)
        withAnimation(.spring) {
            if activeSide == .question { frontItems.append(newItem) }
            else { backItems.append(newItem) }
        }
    }
    
    private func deleteItem(id: UUID) {
        withAnimation {
            if activeSide == .question { frontItems.removeAll(where: { $0.id == id }) }
            else { backItems.removeAll(where: { $0.id == id }) }
        }
    }
    
    private func bringToFront(item: Binding<CanvasItem>) {
        maxZIndex += 1
        item.wrappedValue.zIndex = maxZIndex
    }
    
    private func processPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run { addItem(imageData: data) }
            }
            selectedPhotoItem = nil
        }
    }
    
    private func saveCard() {
        onSave(frontText, backText, frontItems, backItems, .text, .text)
        dismiss()
    }
    
    // MARK: - Components
    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "QUESTION", side: .question)
            tabButton(title: "ANSWER", side: .answer)
        }
        .padding(4)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
    }
    
    private func tabButton(title: String, side: CardSide) -> some View {
        let isActive = activeSide == side
        return Button {
            isEditorFocused = false
            withAnimation(.spring(response: 0.3)) { activeSide = side }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isActive ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(accent)
                            .matchedGeometryEffect(id: "Tab", in: namespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }
    @Namespace private var namespace
    
    private var fabLayer: some View {
        MorphingButton(
            backgroundColor: colorScheme.oppositeColor,
            showExpandedContent: $showFabExpanded
        ) {
            Image(systemName: "plus").font(.title2).fontWeight(.bold)
                .foregroundStyle(colorScheme.backgroundColor).frame(width: 60, height: 60)
        } content: {
            VStack(alignment: .leading, spacing: 15) {
                fabOptionRow(icon: "scribble.variable", title: "Sketch") {
                    isEditorFocused = false; showFabExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { showCanvasModal = true }
                }
                ZStack {
                    fabOptionRow(icon: "photo.on.rectangle", title: "Photo") { }
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) { Color.clear.frame(height: 45) }
                        .onChange(of: selectedPhotoItem) { isEditorFocused = false; showFabExpanded = false }
                }
                fabOptionRow(icon: "keyboard", title: "Keyboard") {
                    showFabExpanded = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { isEditorFocused = true }
                }
            }
            .padding(15)
        } expandedContent: { EmptyView() }
    }
    
    private func fabOptionRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 15) {
                Image(systemName: icon).font(.title2).frame(width: 45, height: 45)
                    .background(colorScheme.backgroundColor, in: .circle)
                Text(title).font(.title3.weight(.semibold))
                    .foregroundStyle(colorScheme.backgroundColor)
                Spacer()
            }
        }
    }
}
