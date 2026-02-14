//
//  AddCardSheetView.swift
//  QuizFlash
//
//  Card editor with zone-based layout, image resize, split, and adaptive sizing.
//

import SwiftUI
import PhotosUI

struct AddCardSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    // Save zones directly to preserve layout structure
    var onSaveZones: (ZoneModel, ZoneModel) -> Void

    // Zone-based content
    @State private var frontZoneContent: ZoneCardContent
    @State private var backZoneContent: ZoneCardContent
    @State private var activeSide = 0
    @State private var layoutTask: Task<Void, Never>? = nil
    @State private var frontSavedPath: ZonePath? = .root
    @State private var backSavedPath: ZonePath? = .root
    // FAB Menu
    @State private var showFABMenu = false

    // Keyboard tracking
    @State private var keyboardHeight: CGFloat = 0

    // Keyboard retention for smooth transitions
    @FocusState private var isRetainerFocused: Bool
    @State private var retainerText: String = ""
    @StateObject private var focusManager = ZoneFocusManager.shared

    // Modals
    @State private var showPhotoPicker = false
    @State private var showSketchModal = false
    @State private var showPreview = false
    @State private var selectedPhoto: PhotosPickerItem?

    // Selection
    @State private var selectedPath: ZonePath? = .root
    @State private var currentCursorIndex: Int? = nil

    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var currentContent: ZoneCardContent { activeSide == 0 ? frontZoneContent : backZoneContent }
    private var canSave: Bool { frontZoneContent.hasContent || backZoneContent.hasContent }

    // MARK: - Init

    init(onSave: @escaping (ZoneModel, ZoneModel) -> Void) {
        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: .text()))
    }

    init(frontZone: ZoneModel, backZone: ZoneModel, onSave: @escaping (ZoneModel, ZoneModel) -> Void) {
        self.onSaveZones = onSave
        _frontZoneContent = State(initialValue: ZoneCardContent(rootZone: frontZone))
        _backZoneContent = State(initialValue: ZoneCardContent(rootZone: backZone))
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient.ignoresSafeArea()
                // Hidden TextField for keyboard retention during zone insertion
                TextField("", text: $retainerText)
                    .focused($isRetainerFocused)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .allowsHitTesting(false)

                // Main content


                VStack(spacing: 0) {

                    sidePicker

                    Divider()

                    editorArea


                    // Format bar at the bottom
                    if let path = selectedPath, currentContent.zone(at: path) != nil {
                        ZoneFormatBar(
                            content: currentContent,
                            path: path,
                            onAddZone: { direction in addZoneWithFocus(in: direction) },
                            onSplit: { splitZone() },
                            onClose: { selectedPath = nil }
                        )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }


                // Dismiss overlay when FAB menu is open
                fabDismissOverlay

                // FAB
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        fabOverlay
                    }
                }
            }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbarContent }
                .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
                .onChange(of: selectedPhoto) { _, item in addPhoto(item) }
                .fullScreenCover(isPresented: $showSketchModal) {
                CanvasModalView { data in addSketch(data) }
            }
            // Keyboard retention observer
            .onChange(of: focusManager.shouldRetainKeyboard) { _, shouldRetain in
                if shouldRetain {
                    // Activăm TextField-ul ascuns pentru a menține tastatura
                    isRetainerFocused = true
                }
            }
                .fullScreenCover(isPresented: $showPreview) {
                ZonePreviewSheet(front: frontZoneContent, back: backZoneContent)
            }
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: selectedPath)

            // MARK: - Observers

                .onAppear {
                if selectedPath == nil { selectedPath = .root }
                // Focus initial - zona root deja există
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    if let rootZoneID = currentContent.rootZone.id as UUID? {
                        ZoneFocusManager.shared.requestFocus(for: rootZoneID)
                    }
                }
            }

                .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
                if let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                    withAnimation(.spring(response: 0.3)) {
                        keyboardHeight = frame.height
                    }
                }
            }

            // FIX CRITIC 1: Prevenim pierderea selecției când deschidem Galeria
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.spring(response: 0.3)) {
                    keyboardHeight = 0
                }

                // Dacă deschidem un picker sau meniu, NU ștergem selecția!
                if showPhotoPicker || showSketchModal || showFABMenu {
                    return
                }

                // Altfel, dacă e doar ascundere de tastatură, deselectăm doar textul
                if let path = selectedPath,
                    let zone = currentContent.zone(at: path),
                    (zone.contentType == .text || zone.contentType == .empty) {
                    selectedPath = nil
                }
            }
        }
    }

    // MARK: - Side Picker

    private var sidePicker: some View {
            Picker("Side", selection: $activeSide) {
                Text("Question").tag(0)
                Text("Answer").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .onChange(of: activeSide) { oldSide, newSide in
                // Salvăm unde eram înainte de switch
                if oldSide == 0 { frontSavedPath = selectedPath }
                else { backSavedPath = selectedPath }

                executeWithKeyboardRetention {
                    (newSide == 0 ? backZoneContent : frontZoneContent).cleanup()

                    // Restaurăm calea pentru noua secțiune
                    selectedPath = newSide == 0 ? frontSavedPath : backSavedPath
                } afterLayout: {
                    let targetContent = newSide == 0 ? frontZoneContent : backZoneContent
                    if let path = selectedPath, let zoneID = targetContent.zone(at: path)?.id {
                        ZoneFocusManager.shared.requestFocus(for: zoneID)
                    } else {
                        selectedPath = .root
                        ZoneFocusManager.shared.requestFocus(for: targetContent.rootZone.id)
                    }
                }
            }
        }

    // MARK: - Editor Area

    private var editorArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {

                    // Eticheta QUESTION / ANSWER în interiorul cardului
                    HStack {
                        Text(activeSide == 0 ? "QUESTION" : "ANSWER")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                        .padding(.bottom, 16)

                    if activeSide == 0 {
                        ZoneEditorView(content: frontZoneContent, path: .root, selectedPath: $selectedPath)
                    } else {
                        ZoneEditorView(content: backZoneContent, path: .root, selectedPath: $selectedPath)
                    }

                    Color.clear
                        .frame(height: 100)
                        .contentShape(Rectangle())
                        .onTapGesture {
                        addZoneAtBottom()
                    }
                        .id("bottom")
                }
                    .padding(.horizontal, 24) // Padding-ul interior al cardului
                .padding(.top, 24)
                    .background(// Fundalul efectiv al Cardului
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .fill(cardBackground)
                    .shadow(color: shadowColor, radius: 16, y: 8)
                )
                    .overlay(// Border-ul Cardului
                RoundedRectangle(cornerRadius: 32, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
                )
                    .padding(.horizontal, 32) // Padding exterior (lasă loc pentru indicatoare în stânga)
                .padding(.top, 24)
                    .padding(.bottom, max((selectedPath != nil ? 80 : 100), keyboardHeight + 20))
            }
                .scrollDismissesKeyboard(.interactively)

            // Auto-scroll when selection changes
            .onChange(of: selectedPath) { _, newPath in
                if let path = newPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                        withAnimation(.spring(response: 0.6, dampingFraction: 1.0)) {
                            proxy.scrollTo(path.id, anchor: .center)
                        }
                    }
                }
            }

            // Auto-scroll for typing
            .onReceive(NotificationCenter.default.publisher(for: .scrollToCursor)) { _ in
                if let path = selectedPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(path.id)
                        }
                    }
                }
            }

            // Auto-scroll when keyboard appears
            .onChange(of: keyboardHeight) { oldHeight, newHeight in
                if newHeight > oldHeight, let path = selectedPath {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        proxy.scrollTo(path.id)
                    }
                }
            }
                .onReceive(NotificationCenter.default.publisher(for: Notification.Name("UpdateCursorIndex"))) { notification in
                if let index = notification.object as? Int {
                    self.currentCursorIndex = index
                }
            }
        }
    }

    // MARK: - Logic & Actions

    /// FIX CRITIC 2: Logică de adăugare robustă care calculează path-ul instantaneu
    private func addZoneWithFocus(in direction: AddDirection) {
            guard let path = selectedPath else { return }

            let parentPath = path.parent
            let childIndex = path.lastIndex ?? 0
            let parentZone = parentPath != nil ? currentContent.zone(at: parentPath!) : nil
            let parentDirection = parentZone?.direction
            let isRoot = path.indices.isEmpty

            var newZoneID: UUID?
            var newPath: ZonePath = .root

            executeWithKeyboardRetention {
                newZoneID = self.currentContent.addZone(relativeTo: path, direction: direction)

                if isRoot {
                    switch direction {
                    case .left, .up: newPath = ZonePath(indices: [0])
                    case .right, .down: newPath = ZonePath(indices: [1])
                    }
                } else if let pPath = parentPath, parentDirection == direction.zoneDirection {
                    switch direction {
                    case .left, .up: newPath = pPath.appending(childIndex)
                    case .right, .down: newPath = pPath.appending(childIndex + 1)
                    }
                } else {
                    switch direction {
                    case .left, .up: newPath = path.appending(0)
                    case .right, .down: newPath = path.appending(1)
                    }
                }
                self.selectedPath = newPath
            } afterLayout: {
                if let zoneID = newZoneID {
                    ZoneFocusManager.shared.requestFocus(for: zoneID)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }

    private func addZoneAtBottom() {
            let root = currentContent.rootZone
            var newZoneID: UUID?

            executeWithKeyboardRetention {
                if !root.isLeaf && root.direction == .vertical {
                    let newIndex = root.children?.count ?? 0
                    let newZone = ZoneModel.empty()
                    newZoneID = newZone.id

                    self.currentContent.updateZone(at: .root) { rootZone in
                        var kids = rootZone.children ?? []
                        kids.append(newZone)
                        rootZone.children = kids
                    }
                    self.selectedPath = ZonePath(indices: [newIndex])
                } else {
                    newZoneID = self.currentContent.addZone(relativeTo: .root, direction: .down)
                    self.selectedPath = ZonePath(indices: [1])
                }
            } afterLayout: {
                if let zoneID = newZoneID {
                    ZoneFocusManager.shared.requestFocus(for: zoneID)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }

    private func triggerKeyboardForNewZone(zoneID: UUID) {
        // Folosim ZoneFocusManager pentru sincronizare precisă cu ciclul de randare
        // Aceasta evită flickerul cauzat de notificările timing-sensitive
        Task { @MainActor in
            // Delay mic pentru a permite SwiftUI să randeze noul view
            try? await Task.sleep(for: .milliseconds(30))
            ZoneFocusManager.shared.requestFocus(for: zoneID)
        }
    }

    /// Fallback pentru cazuri când nu avem zoneID
    private func triggerKeyboardForNewZoneLegacy() {
        // Apel întârziat pentru siguranță (prinde cazurile de layout complex)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NotificationCenter.default.post(name: .focusNewZone, object: nil)
        }
    }

    private func addPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }

        // FIX: Capturăm zona selectată ACUM, înainte de async
        let targetPath = selectedPath

        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let compressedData = data.compressedImageData(maxDimension: 1200, compressionQuality: 0.7) ?? data

                await MainActor.run {
                    // Folosim targetPath capturat
                    if let path = targetPath, currentContent.zone(at: path) != nil {
                        currentContent.updateZone(at: path) { zone in
                            zone.contentType = .image
                            zone.imageData = compressedData
                        }
                    } else {
                        // Fallback: adaugă jos
                        currentContent.addZone(relativeTo: .root, direction: .down)
                        if let children = currentContent.rootZone.children, !children.isEmpty {
                            let newPath = ZonePath(indices: [children.count - 1])
                            currentContent.updateZone(at: newPath) { zone in
                                zone.contentType = .image
                                zone.imageData = compressedData
                            }
                            selectedPath = newPath
                        }
                    }
                }
            }
            selectedPhoto = nil
        }
    }
    // FIX addSketch
    private func addSketch(_ data: Data) {

        let targetPath = selectedPath // Capturăm și aici pentru siguranță

        Task {

            await MainActor.run {
                if let path = targetPath, currentContent.zone(at: path) != nil {
                    currentContent.updateZone(at: path) { zone in
                        zone.contentType = .sketch
                        zone.imageData = data
                    }
                } else {
                    currentContent.addZone(relativeTo: .root, direction: .down)
                    if let children = currentContent.rootZone.children, !children.isEmpty {
                        let newPath = ZonePath(indices: [children.count - 1])
                        currentContent.updateZone(at: newPath) { zone in
                            zone.contentType = .sketch
                            zone.imageData = data
                        }
                        selectedPath = newPath
                    }
                }
            }



        }
    }

    private func splitZone() {
            guard let path = selectedPath,
                  let zone = currentContent.zone(at: path),
                  zone.contentType == .text else { return }

            let text = zone.text
            let lines = text.components(separatedBy: "\n")

            if lines.count >= 2 {
                executeWithKeyboardRetention {
                    let midPoint = lines.count / 2
                    let firstPart = lines[0..<midPoint].joined(separator: "\n")
                    let secondPart = lines[midPoint...].joined(separator: "\n")

                    self.currentContent.updateZone(at: path) { z in z.text = firstPart }
                    self.currentContent.addZone(relativeTo: path, direction: .down)

                    let newPath: ZonePath
                    if let parent = path.parent {
                        newPath = parent.appending((path.lastIndex ?? 0) + 1)
                    } else {
                        newPath = ZonePath(indices: [1])
                    }

                    self.updateSplitZoneContent(at: newPath, text: secondPart, original: zone)
                    
                    // CRITIC: Păstrăm calea pe zona veche (Cea de sus)
                    self.selectedPath = path
                } afterLayout: {
                    if let topZoneID = self.currentContent.zone(at: path)?.id {
                        ZoneFocusManager.shared.requestFocus(for: topZoneID)
                    }
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                }
                return
            }

            // Dacă e un singur rând
            executeWithKeyboardRetention {
                self.currentContent.addZone(relativeTo: path, direction: .down)
            } afterLayout: {
                if let topZoneID = self.currentContent.zone(at: path)?.id {
                    ZoneFocusManager.shared.requestFocus(for: topZoneID)
                }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            }
        }

    private func updateSplitZoneContent(at path: ZonePath, text: String, original: ZoneModel) {
        currentContent.updateZone(at: path) { z in
            z.text = text
            z.contentType = .text
            z.textStyle = original.textStyle
            z.textAlignment = original.textAlignment
            z.textColor = original.textColor
            z.isBold = original.isBold
            z.isItalic = original.isItalic
            z.hasBullet = original.hasBullet
        }
    }

    /// Execută o mutație de layout menținând tastatura deschisă, apoi aplică focusul
    private func executeWithKeyboardRetention(action: @escaping () -> Void, afterLayout: @escaping () -> Void) {
            // 1. OPRIM orice animație/focus anterior care încă nu s-a terminat!
            layoutTask?.cancel()
            
            ZoneFocusManager.shared.prepareForInsertion()

            // 2. Creăm un nou Task pe care îl putem controla
            layoutTask = Task {
                // Pauză scurtă de 50 milisecunde
                try? await Task.sleep(nanoseconds: 50_000_000)
                
                // Dacă între timp ai apăsat pe altceva, ne oprim aici!
                if Task.isCancelled { return }
                
                await MainActor.run { action() }

                // Pauză pentru a lăsa SwiftUI să deseneze zonele noi (100 milisecunde)
                try? await Task.sleep(nanoseconds: 100_000_000)
                
                // Verificăm din nou dacă nu ai dat spam la click-uri
                if Task.isCancelled { return }
                
                await MainActor.run { afterLayout() }
            }
        }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // MARK: - Subviews & Overlays

    private var fabOverlay: some View {
        VStack(alignment: .trailing, spacing: 12) {
            if showFABMenu {
                VStack(spacing: 8) {
                    FABMenuItem(icon: "photo", label: "Photo") {
                        showFABMenu = false
                        showPhotoPicker = true
                    }
                    FABMenuItem(icon: "scribble.variable", label: "Sketch") {
                        showFABMenu = false
                        showSketchModal = true
                        hideKeyboard()
                    }
                }
                    .transition(.scale(scale: 0.5, anchor: .bottomTrailing).combined(with: .opacity))
            }

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { showFABMenu.toggle() }
            } label: {
                Image(systemName: "plus")
                    .font(.title3.bold())
                    .foregroundStyle(accent)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
                    .rotationEffect(.degrees(showFABMenu ? 135 : 0))
            }
        }
            .padding(.trailing, 20)
            .padding(.bottom, selectedPath != nil ? 65 : 30)
    }

    private var fabDismissOverlay: some View {
        Group {
            if showFABMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture {
                    withAnimation(.spring(response: 0.3)) { showFABMenu = false }
                }
            }
        }
    }

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
                } label: { Image(systemName: "eye") }
                    .disabled(!canSave)

                Button("Save") {
                    frontZoneContent.cleanup()
                    backZoneContent.cleanup()
                    onSaveZones(frontZoneContent.rootZone, backZoneContent.rootZone)
                    dismiss()
                }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
    }


    // MARK: - Styling
    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
            : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        : AnyShapeStyle(Color.white)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }

}


// MARK: - Helper Views

private struct FABMenuItem: View {
    let icon: String
    let label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(label).font(.subheadline.weight(.medium))
                Image(systemName: icon)
                    .font(.body.weight(.medium))
                    .frame(width: 36, height: 36)
                    .background(Color(uiColor: .tertiarySystemBackground))
                    .clipShape(Circle())
            }
                .padding(.leading, 14).padding(.trailing, 6).padding(.vertical, 6)
                .background(.ultraThinMaterial, in: Capsule())
        }
            .foregroundStyle(.primary)
    }
}

private struct ZoneFormatBar: View {
    @Bindable var content: ZoneCardContent
    let path: ZonePath
    var onAddZone: (AddDirection) -> Void
    var onSplit: () -> Void
    var onClose: () -> Void

    private var zone: ZoneModel? { content.zone(at: path) }
    private var accent: Color { ThemeManager.shared.accentColor.color }
    private var canSplit: Bool {
        guard let zone = zone else { return false }
        return zone.contentType == .text && !zone.text.isEmpty && zone.text.components(separatedBy: "\n").count >= 2
    }

    var body: some View {
        HStack(spacing: 0) {
            addZoneMenu.padding(.leading, 12).padding(.trailing, 8)
            Divider().frame(height: 28)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if canSplit { ToolbarButton(icon: "rectangle.split.1x2") { onSplit() } }
                    if zone?.contentType == .text || zone?.contentType == .empty { textTools }
                    else if zone?.contentType == .image || zone?.contentType == .sketch { mediaTools }
                    ToolbarButton(icon: "trash", tint: .red) {
                        content.deleteZone(at: path)
                        onClose()
                    }
                }
                    .padding(.horizontal, 8)
            }
            Divider().frame(height: 28)
            Button { onClose() } label: {
                Text("Done").font(.subheadline.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(accent, in: Capsule())
            }
                .padding(.leading, 8).padding(.trailing, 12)
        }
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
    }

    private var addZoneMenu: some View {
        Menu {
            Section("Horizontal") {
                Button { onAddZone(.left) } label: { Label("Left", systemImage: "arrow.left") }
                Button { onAddZone(.right) } label: { Label("Right", systemImage: "arrow.right") }
            }
            Section("Vertical") {
                Button { onAddZone(.up) } label: { Label("Above", systemImage: "arrow.up") }
                Button { onAddZone(.down) } label: { Label("Below", systemImage: "arrow.down") }
            }
        } label: {
            Image(systemName: "plus.square.dashed")
                .font(.body.weight(.medium)).foregroundStyle(accent)
                .frame(width: 34, height: 34)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
        }
    }

    private var textTools: some View {
        HStack(spacing: 8) {
            // Text style menu
            Menu {
                ForEach([TextBlockStyle.title, .headline, .body, .caption], id: \.self) { style in
                    Button { content.updateZone(at: path) { $0.textStyle = style } } label: {
                        HStack { Text(style.rawValue.capitalized); if zone?.textStyle == style { Image(systemName: "checkmark") } }
                    }
                }
            } label: { ToolbarButton(icon: "textformat.size") }

            // Bold & Italic
            ToolbarButton(icon: "bold", isActive: zone?.isBold == true) { content.updateZone(at: path) { $0.isBold.toggle() } }
            ToolbarButton(icon: "italic", isActive: zone?.isItalic == true) { content.updateZone(at: path) { $0.isItalic.toggle() } }

            // Font Family menu
            Menu {
                ForEach(FontFamily.allCases, id: \.self) { family in
                    Button { content.updateZone(at: path) { $0.fontFamily = family } } label: {
                        HStack {
                            Image(systemName: family.icon)
                            Text(family.name)
                            if zone?.fontFamily == family { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: { ToolbarButton(icon: zone?.fontFamily.icon ?? "textformat") }

            // Alignment menu
            Menu {
                Button { content.updateZone(at: path) { $0.textAlignment = .leading } } label: { Label("Left", systemImage: "text.alignleft") }
                Button { content.updateZone(at: path) { $0.textAlignment = .center } } label: { Label("Center", systemImage: "text.aligncenter") }
                Button { content.updateZone(at: path) { $0.textAlignment = .trailing } } label: { Label("Right", systemImage: "text.alignright") }
            } label: { ToolbarButton(icon: "text.alignleft") }

            // Text color menu
            Menu {
                ForEach(TextBlockColor.allCases, id: \.self) { color in
                    Button { content.updateZone(at: path) { $0.textColor = color } } label: {
                        HStack { Circle().fill(color.color).frame(width: 14, height: 14); Text(color.name) }
                    }
                }
            } label: { ToolbarButton(icon: "paintpalette", tint: zone?.textColor.color ?? .primary) }

            // Highlight/Marker menu
            Menu {
                ForEach(HighlightColor.allCases, id: \.self) { highlight in
                    Button { content.updateZone(at: path) { $0.highlightColor = highlight } } label: {
                        HStack {
                            if highlight != .none {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(highlight.color ?? .clear)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "xmark")
                                    .frame(width: 14, height: 14)
                            }
                            Text(highlight.name)
                            if zone?.highlightColor == highlight { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                ToolbarButton(
                    icon: "highlighter",
                    isActive: zone?.highlightColor != HighlightColor.none,
                    tint: zone?.highlightColor.color != nil ? .primary : .primary
                )
            }

            // Bullet
            ToolbarButton(icon: "list.bullet", isActive: zone?.hasBullet == true) { content.updateZone(at: path) { $0.hasBullet.toggle() } }
        }
    }

    private var mediaTools: some View {
        HStack(spacing: 8) {
            // Alignment menu for images/sketches
            Menu {
                Button { content.updateZone(at: path) { $0.textAlignment = .leading } } label: {
                    HStack { Text("Left"); if zone?.textAlignment == .leading { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.textAlignment = .center } } label: {
                    HStack { Text("Center"); if zone?.textAlignment == .center { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.textAlignment = .trailing } } label: {
                    HStack { Text("Right"); if zone?.textAlignment == .trailing { Image(systemName: "checkmark") } }
                }
            } label: { ToolbarButton(icon: alignmentIcon(for: zone?.textAlignment ?? .leading)) }

            // Scale menu
            Menu {
                Button { content.updateZone(at: path) { $0.imageScale = 0.3 } } label: {
                    HStack { Text("Small"); if zone?.imageScale == 0.3 { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.imageScale = 0.7 } } label: {
                    HStack { Text("Medium"); if zone?.imageScale == 0.7 { Image(systemName: "checkmark") } }
                }
                Button { content.updateZone(at: path) { $0.imageScale = 1.0 } } label: {
                    HStack { Text("Full Width"); if zone?.imageScale == 1.0 { Image(systemName: "checkmark") } }
                }
            } label: { ToolbarButton(icon: "aspectratio") }
        }
    }

    private func alignmentIcon(for alignment: TextBlockAlignment) -> String {
        switch alignment {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }
}

private struct ToolbarButton: View {
    let icon: String
    var isActive: Bool = false
    var tint: Color = .primary
    var action: (() -> Void)? = nil
    var body: some View {
        Button { action?() } label: {
            Image(systemName: icon).font(.body.weight(.medium))
                .foregroundStyle(isActive ? ThemeManager.shared.accentColor.color : tint)
                .frame(width: 34, height: 34)
                .background(isActive ? ThemeManager.shared.accentColor.color.opacity(0.12) : Color(uiColor: .tertiarySystemFill))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

//MARK: Card Preview

private struct ZonePreviewSheet: View {
    let front: ZoneCardContent
    let back: ZoneCardContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var isFlipped = false

    private var isCompact: Bool { horizontalSizeClass == .compact }
    private var cardCornerRadius: CGFloat { isCompact ? 24 : 32 }
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack {
                    // Background gradient
                    backgroundGradient
                        .ignoresSafeArea()

                    VStack(spacing: isCompact ? 16 : 24) {
                        Spacer()

                        // Card label
                        HStack(spacing: 8) {
                            Image(systemName: isFlipped ? "lightbulb.fill" : "questionmark.circle.fill")
                                .foregroundStyle(accent)
                            Text(isFlipped ? "ANSWER" : "QUESTION")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())

                        // Flip Card Container
                        ZStack {
                            // Back side (Answer)
                            cardFace(zone: back.rootZone, title: "Answer")
                                .rotation3DEffect(.degrees(isFlipped ? 0 : 180), axis: (x: 0, y: 1, z: 0))
                                .opacity(isFlipped ? 1 : 0)

                            // Front side (Question)
                            cardFace(zone: front.rootZone, title: "Question")
                                .rotation3DEffect(.degrees(isFlipped ? -180 : 0), axis: (x: 0, y: 1, z: 0))
                                .opacity(isFlipped ? 0 : 1)
                        }
                            .frame(
                            width: geo.size.width * 0.85,
                            height: geo.size.height * 0.85
                        )
                            .onTapGesture {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                isFlipped.toggle()
                            }
                        }

                        // Hint
                        HStack(spacing: 6) {
                            Image(systemName: "hand.tap.fill")
                                .font(.caption)
                            Text("Tap to flip")
                                .font(.caption)
                        }
                            .foregroundStyle(.tertiary)

                        // Navigation dots
                        HStack(spacing: 8) {
                            Circle()
                                .fill(isFlipped ? Color.secondary.opacity(0.3) : accent)
                                .frame(width: 8, height: 8)
                            Circle()
                                .fill(isFlipped ? accent : Color.secondary.opacity(0.3))
                                .frame(width: 8, height: 8)
                        }
                            .animation(.easeInOut, value: isFlipped)

                        Spacer()
                    }
                }
            }
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
    }

    // MARK: - Card Face

    @ViewBuilder
    private func cardFace(zone: ZoneModel, title: String) -> some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .fill(cardBackground)
                .shadow(color: shadowColor, radius: isCompact ? 16 : 24, y: 8)

            // Border
            RoundedRectangle(cornerRadius: cardCornerRadius, style: .continuous)
                .stroke(borderColor, lineWidth: 1)

            // Content
            VStack(alignment: .leading, spacing: 0) {
                // Content area
                if zone.hasContent {
                    ScrollView(.vertical, showsIndicators: false) {
                        ZonePreviewView(zone: zone)
                            .padding(.horizontal, isCompact ? 20 : 28)
                            .padding(.vertical, isCompact ? 20 : 24)
                    }
                        .scrollBounceBehavior(.basedOnSize)
                } else {
                    emptyContent
                }
            }
        }
    }

    // MARK: - Empty Content

    private var emptyContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "text.quote")
                .font(.system(size: isCompact ? 40 : 56))
                .foregroundStyle(.tertiary)
            Text("No content")
                .font(isCompact ? .body : .title3)
                .foregroundStyle(.secondary)
        }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Styling

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(uiColor: .systemBackground), Color(uiColor: .secondarySystemBackground)]
            : [Color(uiColor: .systemGray6), Color(uiColor: .systemBackground)],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
        : AnyShapeStyle(Color.white)
    }

    private var shadowColor: Color {
        colorScheme == .dark ? Color.black.opacity(0.5) : Color.black.opacity(0.15)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.08)
    }
}

#Preview {
    AddCardSheetView { _, _ in }
}
