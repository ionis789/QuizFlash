//
//  AddCardSheetView.swift
//  QuizFlash
//
//  Professional card editor with vertical line indicators and proper animations.
//

import SwiftUI
import PhotosUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    
    var onSave: (CardSideContent, CardSideContent) -> Void
    
    @State private var frontContent: CardSideContent
    @State private var backContent: CardSideContent
    @State private var activeSide = 0
    
    // FAB Menu
    @State private var showFABMenu = false
    
    // Modals
    @State private var showPhotoPicker = false
    @State private var showSketchModal = false
    @State private var showPreview = false
    @State private var selectedPhoto: PhotosPickerItem?
    
    // Formatting mode
    @State private var formattingBlockIndex: Int? = nil
    
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var canSave: Bool { frontContent.hasContent || backContent.hasContent }
    private var currentContent: CardSideContent { activeSide == 0 ? frontContent : backContent }
    
    // MARK: - Init
    
    init(onSave: @escaping (CardSideContent, CardSideContent) -> Void) {
        self.onSave = onSave
        _frontContent = State(initialValue: CardSideContent(blocks: [.text()]))
        _backContent = State(initialValue: CardSideContent(blocks: [.text()]))
    }
    
    init(frontContent: CardSideContent, backContent: CardSideContent, onSave: @escaping (CardSideContent, CardSideContent) -> Void) {
        self.onSave = onSave
        _frontContent = State(initialValue: frontContent.blocks.isEmpty ? CardSideContent(blocks: [.text()]) : frontContent)
        _backContent = State(initialValue: backContent.blocks.isEmpty ? CardSideContent(blocks: [.text()]) : backContent)
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            ZStack {
                VStack(spacing: 0) {
                    // Side Picker
                    Picker("Side", selection: $activeSide) {
                        Text("Question").tag(0)
                        Text("Answer").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: activeSide) { _, _ in
                        // Cleanup empty blocks when switching sides
                        cleanupEmptyBlocks(in: activeSide == 0 ? backContent : frontContent)
                        formattingBlockIndex = nil
                    }
                    
                    Divider()
                    
                    // Editor
                    if activeSide == 0 {
                        BlockEditorView(
                            content: frontContent,
                            formattingIndex: $formattingBlockIndex
                        )
                    } else {
                        BlockEditorView(
                            content: backContent,
                            formattingIndex: $formattingBlockIndex
                        )
                    }
                    
                    // Format Bar
                    if let index = formattingBlockIndex, index < currentContent.blocks.count {
                        FormatBarView(
                            content: currentContent,
                            index: index,
                            onClose: { closeFormatting() }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                
                // FAB Overlay
                if showFABMenu {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3)) {
                                showFABMenu = false
                            }
                        }
                }
                
                // FAB Button
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fabButton
                            .padding(.trailing, 20)
                            .padding(.bottom, 24)
                    }
                }
            }
            .background(Color(uiColor: .systemBackground))
            .navigationTitle("New Card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) { _, item in addPhoto(item) }
            .fullScreenCover(isPresented: $showSketchModal) {
                CanvasModalView { data in addSketch(data) }
            }
            .sheet(isPresented: $showPreview) {
                CardPreviewSheet(front: frontContent, back: backContent)
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: formattingBlockIndex)
        }
    }
    
    // MARK: - Toolbar
    
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") { dismiss() }
        }
        ToolbarItem(placement: .primaryAction) {
            HStack(spacing: 16) {
                Button {
                    hideKeyboard()
                    showPreview = true
                } label: {
                    Image(systemName: "eye")
                }
                .disabled(!canSave)
                
                Button("Save") {
                    cleanupEmptyBlocks(in: frontContent)
                    cleanupEmptyBlocks(in: backContent)
                    onSave(frontContent, backContent)
                    dismiss()
                }
                .fontWeight(.semibold)
                .disabled(!canSave)
            }
        }
    }
    
    // MARK: - FAB Button
    
    private var fabButton: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showFABMenu {
                VStack(spacing: 8) {
                    FABMenuItem(icon: "photo", label: "Photo") {
                        showFABMenu = false
                        showPhotoPicker = true
                    }
                    FABMenuItem(icon: "scribble.variable", label: "Sketch") {
                        showFABMenu = false
                        hideKeyboard()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            showSketchModal = true
                        }
                    }
                    FABMenuItem(icon: "keyboard.chevron.compact.down", label: "Done") {
                        showFABMenu = false
                        hideKeyboard()
                    }
                }
                .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
            }
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    showFABMenu.toggle()
                }
            } label: {
                Image(systemName: showFABMenu ? "xmark" : "plus")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(colorScheme == .dark ? .black : .white)
                    .frame(width: 56, height: 56)
                    .background(accent)
                    .clipShape(Circle())
                    .shadow(color: accent.opacity(0.4), radius: 8, y: 4)
                    .rotationEffect(.degrees(showFABMenu ? 45 : 0))
            }
        }
    }
    
    // MARK: - Actions
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func addPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                await MainActor.run {
                    let target = activeSide == 0 ? frontContent : backContent
                    target.blocks.append(.image(data: data))
                    target.blocks.append(.text())
                }
            }
            selectedPhoto = nil
        }
    }
    
    private func addSketch(_ data: Data) {
        let target = activeSide == 0 ? frontContent : backContent
        target.blocks.append(.sketch(data: data))
        target.blocks.append(.text())
    }
    
    private func closeFormatting() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            formattingBlockIndex = nil
        }
    }
    
    private func cleanupEmptyBlocks(in content: CardSideContent) {
        // Remove empty text blocks but keep at least one
        let nonEmptyBlocks = content.blocks.filter { block in
            if block.type == .text {
                return !block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            return true // Keep images and sketches
        }
        
        if nonEmptyBlocks.isEmpty {
            content.blocks = [.text()]
        } else {
            content.blocks = nonEmptyBlocks
        }
    }
}

// MARK: - FAB Menu Item

private struct FABMenuItem: View {
    let icon: String
    let label: String
    var action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label)
                    .font(.subheadline.weight(.medium))
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(Circle())
            }
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - Block Editor View

private struct BlockEditorView: View {
    @Bindable var content: CardSideContent
    @Binding var formattingIndex: Int?
    
    @FocusState private var focusedIndex: Int?
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(content.blocks.enumerated()), id: \.element.id) { index, _ in
                        BlockRowView(
                            content: content,
                            index: index,
                            isFocused: focusedIndex == index,
                            isFormatting: formattingIndex == index,
                            focusedIndex: _focusedIndex,
                            onEnterFormatting: {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                    formattingIndex = index
                                }
                            },
                            onExitFormatting: {
                                if formattingIndex != nil {
                                    withAnimation(.spring(response: 0.3)) {
                                        formattingIndex = nil
                                    }
                                }
                            }
                        )
                        .id(index)
                    }
                    
                    // Tap below to add/focus
                    Color.clear
                        .frame(height: 200)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            formattingIndex = nil
                            
                            // Clean up empty blocks first
                            cleanupEmptyTextBlocks()
                            
                            // Add new text block if needed
                            if content.blocks.isEmpty || content.blocks.last?.type != .text {
                                content.blocks.append(.text())
                            } else if let last = content.blocks.last, last.type == .text && !last.text.isEmpty {
                                content.blocks.append(.text())
                            }
                            
                            // Focus last block
                            let lastIndex = content.blocks.count - 1
                            focusedIndex = lastIndex
                            
                            withAnimation {
                                proxy.scrollTo(lastIndex, anchor: .center)
                            }
                        }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: focusedIndex) { oldIndex, newIndex in
                // Clean up empty block when losing focus
                if let old = oldIndex, old != newIndex, old < content.blocks.count {
                    let block = content.blocks[old]
                    if block.type == .text && block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        // Don't delete if it's the only block or if we're in formatting mode
                        if content.blocks.count > 1 && formattingIndex != old {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                if old < content.blocks.count {
                                    let blockToCheck = content.blocks[old]
                                    if blockToCheck.type == .text && blockToCheck.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            content.blocks.remove(at: old)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                
                // Scroll to new focus
                if let idx = newIndex {
                    withAnimation {
                        proxy.scrollTo(idx, anchor: .center)
                    }
                }
            }
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                if let idx = content.blocks.firstIndex(where: { $0.type == .text }) {
                    focusedIndex = idx
                }
            }
        }
    }
    
    private func cleanupEmptyTextBlocks() {
        // Remove empty text blocks except the last one
        var indicesToRemove: [Int] = []
        for (index, block) in content.blocks.enumerated() {
            if block.type == .text && block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // Keep if it's the only block or the last block
                if content.blocks.count > 1 && index != content.blocks.count - 1 {
                    indicesToRemove.append(index)
                }
            }
        }
        
        // Remove in reverse order to maintain indices
        for index in indicesToRemove.reversed() {
            content.blocks.remove(at: index)
        }
    }
}

// MARK: - Block Row View

private struct BlockRowView: View {
    @Bindable var content: CardSideContent
    let index: Int
    let isFocused: Bool
    let isFormatting: Bool
    @FocusState var focusedIndex: Int?
    
    var onEnterFormatting: () -> Void
    var onExitFormatting: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme
    
    // Press animation states
    @State private var isPressing = false
    @State private var lineWidth: CGFloat = 3
    @State private var lineGlow: CGFloat = 0
    
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    var body: some View {
        let block = content.blocks[safe: index]
        
        HStack(alignment: .top, spacing: 0) {
            // Vertical Line Indicator with press animation
            verticalLine
            
            // Content
            VStack(alignment: .leading, spacing: 0) {
                switch block?.type {
                case .text:
                    textBlockView(block: block)
                case .image:
                    imageBlockView(block: block)
                case .sketch:
                    sketchBlockView(block: block)
                case .none:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onLongPressGesture(minimumDuration: 0.5, pressing: { pressing in
            // Called when press state changes
            withAnimation(.easeInOut(duration: 0.15)) {
                isPressing = pressing
            }
            
            if pressing {
                // Start pulsing animation
                startPulseAnimation()
            } else {
                // Reset line state if released early
                resetLineState()
            }
        }, perform: {
            // Long press completed - enter formatting mode
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
            
            // Final pulse before entering formatting
            withAnimation(.spring(response: 0.2, dampingFraction: 0.5)) {
                lineWidth = 6
                lineGlow = 1
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                onEnterFormatting()
                resetLineState()
            }
        })
    }
    
    // MARK: - Vertical Line
    
    private var verticalLine: some View {
        let block = content.blocks[safe: index]
        let isTextBlock = block?.type == .text
        
        return ZStack {
            // Glow effect
            if lineGlow > 0 {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: lineWidth + 4)
                    .blur(radius: 4)
                    .opacity(lineGlow * 0.5)
            }
            
            // Main line
            RoundedRectangle(cornerRadius: 2)
                .fill(lineColor)
                .frame(width: lineWidth)
        }
        .frame(maxHeight: .infinity)
        .padding(.vertical, isTextBlock ? 8 : 12)
        .padding(.trailing, 12)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFocused)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isFormatting)
        .onChange(of: isFocused) { _, focused in
            if focused && !isFormatting {
                // Quick pulse when focused
                withAnimation(.easeOut(duration: 0.1)) {
                    lineWidth = 4
                }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.6).delay(0.1)) {
                    lineWidth = 3
                }
            }
        }
        .onChange(of: isFormatting) { _, formatting in
            if formatting {
                lineWidth = 4
            } else if !isPressing {
                lineWidth = 3
            }
        }
    }
    
    private var lineColor: Color {
        if isFormatting {
            return accent
        } else if isPressing {
            return accent.opacity(0.8)
        } else if isFocused {
            return accent.opacity(0.6)
        } else {
            return Color.secondary.opacity(0.25)
        }
    }
    
    private func startPulseAnimation() {
        // Animate line growing with pulse effect
        withAnimation(.easeOut(duration: 0.2)) {
            lineWidth = 5
            lineGlow = 0.5
        }
        
        // Continue pulsing while pressing
        withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true).delay(0.2)) {
            lineGlow = 1.0
        }
    }
    
    private func resetLineState() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            lineWidth = isFormatting ? 4 : 3
            lineGlow = 0
        }
    }
    
    // MARK: - Text Block
    
    @ViewBuilder
    private func textBlockView(block: ContentBlock?) -> some View {
        let alignment: TextAlignment = block?.textAlignment.alignment ?? .leading
        
        TextField("Type here...", text: textBinding, axis: .vertical)
            .font(block?.textStyle.font ?? .system(size: 17))
            .fontWeight(block?.isBold == true ? .bold : .regular)
            .italic(block?.isItalic == true)
            .multilineTextAlignment(alignment)
            .focused($focusedIndex, equals: index)
            .padding(.vertical, 8)
            .onTapGesture {
                onExitFormatting()
                focusedIndex = index
            }
    }
    
    // MARK: - Image Block
    
    @ViewBuilder
    private func imageBlockView(block: ContentBlock?) -> some View {
        if let data = block?.imageData, let img = UIImage(data: data) {
            let scale = block?.imageScale ?? 1.0
            let alignment = alignmentFromBlock(block)
            
            HStack {
                if alignment == .center || alignment == .trailing { Spacer() }
                
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                    
                    if isFormatting {
                        deleteButton
                    }
                }
                .onTapGesture { onExitFormatting() }
                
                if alignment == .center || alignment == .leading { Spacer() }
            }
            .padding(.vertical, 8)
        }
    }
    
    // MARK: - Sketch Block
    
    @ViewBuilder
    private func sketchBlockView(block: ContentBlock?) -> some View {
        if let data = block?.imageData, let img = UIImage(data: data) {
            let scale = block?.imageScale ?? 1.0
            let alignment = alignmentFromBlock(block)
            
            HStack {
                if alignment == .center || alignment == .trailing { Spacer() }
                
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: UIScreen.main.bounds.width * scale * 0.8)
                        .background(colorScheme == .dark ? Color.gray.opacity(0.2) : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                    
                    if isFormatting {
                        deleteButton
                    }
                }
                .onTapGesture { onExitFormatting() }
                
                if alignment == .center || alignment == .leading { Spacer() }
            }
            .padding(.vertical, 8)
        }
    }
    
    private var deleteButton: some View {
        Button { deleteBlock() } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.title2)
                .foregroundStyle(.white, .red.opacity(0.8))
        }
        .padding(8)
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Helpers
    
    private var textBinding: Binding<String> {
        Binding(
            get: { content.blocks[safe: index]?.text ?? "" },
            set: { if index < content.blocks.count { content.blocks[index].text = $0 } }
        )
    }
    
    private func alignmentFromBlock(_ block: ContentBlock?) -> Alignment {
        switch block?.textAlignment ?? .leading {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
    
    private func deleteBlock() {
        guard content.blocks.count > 1, index < content.blocks.count else { return }
        withAnimation(.spring(response: 0.3)) {
            content.blocks.remove(at: index)
        }
    }
}

// MARK: - Format Bar View

private struct FormatBarView: View {
    @Bindable var content: CardSideContent
    let index: Int
    var onClose: () -> Void
    
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    private var canSplit: Bool {
        guard index < content.blocks.count else { return false }
        let block = content.blocks[index]
        // Can only split text blocks that have content
        return block.type == .text && !block.text.isEmpty
    }
    
    var body: some View {
        let block = content.blocks[safe: index]
        
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Split button - only for text blocks with content
                if canSplit {
                    FormatButton(icon: "rectangle.split.1x2", tint: accent) {
                        splitBlock()
                    }
                    Divider().frame(height: 24).padding(.horizontal, 4)
                }
                
                // Text formatting
                if block?.type == .text {
                    Menu {
                        Button { setStyle(.title) } label: { Label("Title", systemImage: "textformat.size.larger") }
                        Button { setStyle(.headline) } label: { Label("Headline", systemImage: "textformat.size") }
                        Button { setStyle(.body) } label: { Label("Body", systemImage: "textformat") }
                        Button { setStyle(.caption) } label: { Label("Caption", systemImage: "textformat.size.smaller") }
                    } label: {
                        FormatButton(icon: "textformat.size")
                    }
                    
                    FormatButton(icon: "bold", isActive: block?.isBold == true) { toggleBold() }
                    FormatButton(icon: "italic", isActive: block?.isItalic == true) { toggleItalic() }
                    
                    Divider().frame(height: 24).padding(.horizontal, 4)
                }
                
                // Alignment
                FormatButton(icon: "text.alignleft", isActive: block?.textAlignment == .leading) { setAlignment(.leading) }
                FormatButton(icon: "text.aligncenter", isActive: block?.textAlignment == .center) { setAlignment(.center) }
                FormatButton(icon: "text.alignright", isActive: block?.textAlignment == .trailing) { setAlignment(.trailing) }
                
                // Size for images/sketches
                if block?.type == .image || block?.type == .sketch {
                    Divider().frame(height: 24).padding(.horizontal, 4)
                    
                    Menu {
                        Button { setSize(0.4) } label: { Label("Small", systemImage: "square.resize.down") }
                        Button { setSize(0.6) } label: { Label("Medium", systemImage: "square.resize") }
                        Button { setSize(0.8) } label: { Label("Large", systemImage: "square.resize.up") }
                        Button { setSize(1.0) } label: { Label("Full", systemImage: "arrow.left.and.right") }
                    } label: {
                        FormatButton(icon: "aspectratio")
                    }
                }
                
                Divider().frame(height: 24).padding(.horizontal, 4)
                
                // Delete
                FormatButton(icon: "trash", tint: .red) { deleteBlock() }
                
                // Done
                FormatButton(icon: "checkmark.circle.fill", tint: accent) { onClose() }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .secondarySystemBackground))
    }
    
    // MARK: - Actions
    
    private func splitBlock() {
        guard index < content.blocks.count else { return }
        let block = content.blocks[index]
        
        guard block.type == .text && !block.text.isEmpty else { return }
        
        let text = block.text
        
        // Find middle point - try to split at newline or space
        var splitIndex = text.index(text.startIndex, offsetBy: text.count / 2)
        
        // Look for nearest newline first
        if let newlineIndex = text.range(of: "\n", range: splitIndex..<text.endIndex)?.lowerBound {
            splitIndex = newlineIndex
        } else if let newlineIndex = text.range(of: "\n", options: .backwards, range: text.startIndex..<splitIndex)?.lowerBound {
            splitIndex = text.index(after: newlineIndex)
        }
        // If no newline, look for space
        else if let spaceIndex = text.range(of: " ", range: splitIndex..<text.endIndex)?.lowerBound {
            splitIndex = text.index(after: spaceIndex)
        } else if let spaceIndex = text.range(of: " ", options: .backwards, range: text.startIndex..<splitIndex)?.lowerBound {
            splitIndex = text.index(after: spaceIndex)
        }
        
        // Split the text
        let firstPart = String(text[..<splitIndex]).trimmingCharacters(in: .whitespacesAndNewlines)
        let secondPart = String(text[splitIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Update current block with first part
        content.blocks[index].text = firstPart
        
        // Create new block with second part
        var newBlock = ContentBlock.text(secondPart)
        newBlock.textStyle = block.textStyle
        newBlock.textAlignment = block.textAlignment
        newBlock.isBold = block.isBold
        newBlock.isItalic = block.isItalic
        
        // Insert new block after current
        withAnimation(.spring(response: 0.3)) {
            content.blocks.insert(newBlock, at: index + 1)
        }
        
        onClose()
    }
    
    private func setStyle(_ style: TextBlockStyle) {
        guard index < content.blocks.count else { return }
        content.blocks[index].textStyle = style
    }
    
    private func toggleBold() {
        guard index < content.blocks.count else { return }
        content.blocks[index].isBold.toggle()
    }
    
    private func toggleItalic() {
        guard index < content.blocks.count else { return }
        content.blocks[index].isItalic.toggle()
    }
    
    private func setAlignment(_ alignment: TextBlockAlignment) {
        guard index < content.blocks.count else { return }
        content.blocks[index].textAlignment = alignment
    }
    
    private func setSize(_ scale: CGFloat) {
        guard index < content.blocks.count else { return }
        content.blocks[index].imageScale = scale
    }
    
    private func deleteBlock() {
        guard content.blocks.count > 1, index < content.blocks.count else { return }
        withAnimation(.spring(response: 0.3)) {
            content.blocks.remove(at: index)
        }
        onClose()
    }
}

// MARK: - Format Button

private struct FormatButton: View {
    let icon: String
    var isActive: Bool = false
    var tint: Color = .primary
    var action: (() -> Void)? = nil
    
    private var accent: Color { ThemeManager.shared.accentColor.color }
    
    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon)
                .font(.body.weight(.medium))
                .foregroundStyle(isActive ? accent : tint)
                .frame(width: 40, height: 40)
                .background(isActive ? accent.opacity(0.15) : Color(uiColor: .tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }
}

// MARK: - Card Preview Sheet

private struct CardPreviewSheet: View {
    let front: CardSideContent
    let back: CardSideContent
    @Environment(\.dismiss) private var dismiss
    @State private var showBack = false
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color(uiColor: .systemGroupedBackground).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    Text(showBack ? "ANSWER" : "QUESTION")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    
                    ZStack {
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color(uiColor: .systemBackground))
                            .shadow(radius: 8)
                        
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(showBack ? back.blocks : front.blocks) { block in
                                    PreviewBlockView(block: block, colorScheme: colorScheme)
                                }
                            }
                            .padding(20)
                        }
                    }
                    .frame(height: 380)
                    .padding(.horizontal, 24)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showBack.toggle()
                        }
                    }
                    
                    Text("Tap to flip")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 20)
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview Block View

private struct PreviewBlockView: View {
    let block: ContentBlock
    let colorScheme: ColorScheme
    
    var body: some View {
        // Skip empty text blocks
        if block.type == .text && block.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            EmptyView()
        } else {
            let hAlignment: HorizontalAlignment = {
                switch block.textAlignment {
                case .leading: return .leading
                case .center: return .center
                case .trailing: return .trailing
                }
            }()
            
            VStack(alignment: hAlignment) {
                switch block.type {
                case .text:
                    Text(block.text)
                        .font(block.textStyle.font)
                        .fontWeight(block.isBold ? .bold : .regular)
                        .italic(block.isItalic)
                        .multilineTextAlignment(block.textAlignment.alignment)
                    
                case .image:
                    if let data = block.imageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: UIScreen.main.bounds.width * block.imageScale * 0.7)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    
                case .sketch:
                    if let data = block.imageData, let img = UIImage(data: data) {
                        Image(uiImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: UIScreen.main.bounds.width * block.imageScale * 0.7)
                            .background(colorScheme == .dark ? Color.gray.opacity(0.2) : .white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: Alignment(horizontal: hAlignment, vertical: .center))
        }
    }
}

// MARK: - Safe Array Extension

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

#Preview {
    AddCardSheetView { _, _ in }
}
