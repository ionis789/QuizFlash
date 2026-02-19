//
//  ImageCropEditorView.swift
//  QuizFlash
//
//  Production-ready Freeform Image Cropping Tool (Apple Photos Style).
//

import SwiftUI

// MARK: - Drag Handles Enum
private enum CropDragHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case none
}

// MARK: - Main Freeform Crop Editor View
struct ImageCropEditorView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    // View & Layout State
    @State private var containerSize: CGSize = .zero
    @State private var imageDisplayRect: CGRect = .zero

    // Crop Rect State
    @State private var cropRect: CGRect = .zero
    @State private var lastCropRect: CGRect = .zero
    @State private var activeHandle: CropDragHandle = .none

    // Zoom & Pan State for the Image
    @State private var imageScale: CGFloat = 1.0
    @State private var lastImageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var lastImageOffset: CGSize = .zero
    
    // UI/UX State
    @State private var isInteracting: Bool = false

    private let minCropSize: CGFloat = 80
    private let handleSize: CGFloat = 44
    private let cornerRadius: CGFloat = 16 // ADDED: Beautiful rounded corners

    private var accent: Color { .blue } // Swap back to ThemeManager.shared.accentColor.color

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if imageDisplayRect != .zero {
                        // 1. The Underlying Image (Zoomable and Pannable)
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: containerSize.width, height: containerSize.height)
                            .scaleEffect(imageScale)
                            .offset(imageOffset)
                            .gesture(
                                SimultaneousGesture(
                                    MagnificationGesture()
                                        .onChanged { value in
                                            withAnimation(.interactiveSpring()) { isInteracting = true }
                                            imageScale = max(0.5, lastImageScale * value)
                                        }
                                        .onEnded { _ in
                                            lastImageScale = imageScale
                                            withAnimation(.easeOut(duration: 0.2)) { isInteracting = false }
                                        },
                                    DragGesture()
                                        .onChanged { value in
                                            withAnimation(.interactiveSpring()) { isInteracting = true }
                                            imageOffset = CGSize(
                                                width: lastImageOffset.width + value.translation.width,
                                                height: lastImageOffset.height + value.translation.height
                                            )
                                        }
                                        .onEnded { _ in
                                            lastImageOffset = imageOffset
                                            withAnimation(.easeOut(duration: 0.2)) { isInteracting = false }
                                        }
                                )
                            )

                        // 2. Dimmed Overlay with Cutout (Now Rounded)
                        dimmedOverlay

                        // 3. The Interactive Crop Frame (Grid + Handles)
                        cropFrameView
                    }
                }
                .onAppear { setupInitialLayout(with: proxy.size) }
                .onChange(of: proxy.size, initial: false) { _, newSize in setupInitialLayout(with: newSize) }
            }
            // ADDED: Prevents the iOS Home Bar from stealing your bottom crop drags!
            .defersSystemGestures(on: .bottom)
            .navigationTitle("Crop Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { onCancel() }
                        .tint(.white)
                }
                
                // ADDED: Reset Button centered or grouped
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: resetToOriginal) {
                        Image(systemName: "arrow.uturn.backward")
                            .fontWeight(.semibold)
                    }
                    .tint(.white)
                    // Only show reset if something has actually changed
                    .opacity(hasChanges ? 1.0 : 0.0)
                    .animation(.easeInOut, value: hasChanges)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { processCrop() }
                        .fontWeight(.semibold)
                        .tint(accent)
                }
            }
        }
    }

    // MARK: - Computed Properties
    private var hasChanges: Bool {
        cropRect != imageDisplayRect || imageScale != 1.0 || imageOffset != .zero
    }

    // MARK: - Actions
    private func resetToOriginal() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
            cropRect = imageDisplayRect
            lastCropRect = imageDisplayRect
            imageScale = 1.0
            lastImageScale = 1.0
            imageOffset = .zero
            lastImageOffset = .zero
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    // MARK: - Layout Initialization
    private func setupInitialLayout(with size: CGSize) {
        containerSize = size
        imageDisplayRect = calculateImageDisplayRect(containerSize: size, imageSize: image.size)
        cropRect = imageDisplayRect
        lastCropRect = imageDisplayRect
    }

    private func calculateImageDisplayRect(containerSize: CGSize, imageSize: CGSize) -> CGRect {
        let containerRatio = containerSize.width / containerSize.height
        let imageRatio = imageSize.width / imageSize.height
        var w: CGFloat = 0, h: CGFloat = 0

        if imageRatio > containerRatio {
            w = containerSize.width
            h = containerSize.width / imageRatio
        } else {
            h = containerSize.height
            w = containerSize.height * imageRatio
        }
        return CGRect(x: (containerSize.width - w) / 2.0, y: (containerSize.height - h) / 2.0, width: w, height: h)
    }

    // MARK: - UI Components
    private var dimmedOverlay: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
            .mask(
                ZStack {
                    Color.black
                    // ADDED: Cutout is now perfectly rounded
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .frame(width: cropRect.width, height: cropRect.height)
                        .position(x: cropRect.midX, y: cropRect.midY)
                        .blendMode(.destinationOut)
                }
                .compositingGroup()
            )
            .allowsHitTesting(false)
    }

    private var cropFrameView: some View {
        ZStack {
            // Inner Grid & Border
            gridOverlay
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            // ADDED: The new beautiful rounded thick corner visuals
            thickRoundedCorners
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false) // Purely visual

            // Edge Handles
            edgeHandle(for: .top)
            edgeHandle(for: .bottom)
            edgeHandle(for: .left)
            edgeHandle(for: .right)

            // Corner Handles (Invisible hitboxes for dragging)
            invisibleCornerHitbox(for: .topLeft)
            invisibleCornerHitbox(for: .topRight)
            invisibleCornerHitbox(for: .bottomLeft)
            invisibleCornerHitbox(for: .bottomRight)
        }
    }

    private var gridOverlay: some View {
        ZStack {
            // Main Border (Now Rounded)
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white, lineWidth: 1.5)

            // Rule of Thirds Grid
            ZStack {
                VStack(spacing: 0) {
                    Spacer()
                    Rectangle().fill(Color.white).frame(height: 0.5)
                    Spacer()
                    Rectangle().fill(Color.white).frame(height: 0.5)
                    Spacer()
                }
                HStack(spacing: 0) {
                    Spacer()
                    Rectangle().fill(Color.white).frame(width: 0.5)
                    Spacer()
                    Rectangle().fill(Color.white).frame(width: 0.5)
                    Spacer()
                }
            }
            // Clip the internal grid so lines don't bleed out of the rounded corners
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(isInteracting ? 1.0 : 0.0)
        }
    }

    // ADDED: A highly elegant way to draw perfect rounded corners
    // It creates one thick rounded rectangle and masks it so only the 4 corners show.
    private var thickRoundedCorners: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white, lineWidth: 4)
            .mask(
                ZStack {
                    let size: CGFloat = 40 // Length of the corner handles
                    Rectangle().frame(width: size, height: size).position(x: 0, y: 0)
                    Rectangle().frame(width: size, height: size).position(x: cropRect.width, y: 0)
                    Rectangle().frame(width: size, height: size).position(x: 0, y: cropRect.height)
                    Rectangle().frame(width: size, height: size).position(x: cropRect.width, y: cropRect.height)
                }
            )
    }

    @ViewBuilder
    private func edgeHandle(for position: CropDragHandle) -> some View {
        let x: CGFloat = {
            switch position { case .left: return cropRect.minX; case .right: return cropRect.maxX; default: return cropRect.midX }
        }()
        let y: CGFloat = {
            switch position { case .top: return cropRect.minY; case .bottom: return cropRect.maxY; default: return cropRect.midY }
        }()

        let width: CGFloat = (position == .top || position == .bottom) ? max(0, cropRect.width - handleSize * 2) : handleSize
        let height: CGFloat = (position == .left || position == .right) ? max(0, cropRect.height - handleSize * 2) : handleSize

        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: width, height: height)
            .position(x: x, y: y)
            .gesture(dragGesture(for: position))
    }

    @ViewBuilder
    private func invisibleCornerHitbox(for position: CropDragHandle) -> some View {
        let x: CGFloat = {
            switch position { case .topLeft, .bottomLeft: return cropRect.minX; case .topRight, .bottomRight: return cropRect.maxX; default: return 0 }
        }()
        let y: CGFloat = {
            switch position { case .topLeft, .topRight: return cropRect.minY; case .bottomLeft, .bottomRight: return cropRect.maxY; default: return 0 }
        }()

        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(width: handleSize, height: handleSize)
            .position(x: x, y: y)
            .gesture(dragGesture(for: position))
    }

    // MARK: - Gestures & Logic
    private func dragGesture(for handle: CropDragHandle) -> some Gesture {
        DragGesture()
            .onChanged { value in
                withAnimation(.interactiveSpring()) { isInteracting = true }
                if activeHandle == .none {
                    activeHandle = handle
                    UISelectionFeedbackGenerator().selectionChanged()
                }
                updateCropRect(handle: handle, translation: value.translation)
            }
            .onEnded { _ in
                activeHandle = .none
                lastCropRect = cropRect
                withAnimation(.easeOut(duration: 0.2)) { isInteracting = false }
            }
    }

    private func updateCropRect(handle: CropDragHandle, translation: CGSize) {
        var minX = lastCropRect.minX, minY = lastCropRect.minY
        var maxX = lastCropRect.maxX, maxY = lastCropRect.maxY
        let bounds = imageDisplayRect

        switch handle {
        case .topLeft:
            minX = min(max(minX + translation.width, bounds.minX), maxX - minCropSize)
            minY = min(max(minY + translation.height, bounds.minY), maxY - minCropSize)
        case .topRight:
            maxX = max(min(maxX + translation.width, bounds.maxX), minX + minCropSize)
            minY = min(max(minY + translation.height, bounds.minY), maxY - minCropSize)
        case .bottomLeft:
            minX = min(max(minX + translation.width, bounds.minX), maxX - minCropSize)
            maxY = max(min(maxY + translation.height, bounds.maxY), minY + minCropSize)
        case .bottomRight:
            maxX = max(min(maxX + translation.width, bounds.maxX), minX + minCropSize)
            maxY = max(min(maxY + translation.height, bounds.maxY), minY + minCropSize)
        case .top:
            minY = min(max(minY + translation.height, bounds.minY), maxY - minCropSize)
        case .bottom:
            maxY = max(min(maxY + translation.height, bounds.maxY), minY + minCropSize)
        case .left:
            minX = min(max(minX + translation.width, bounds.minX), maxX - minCropSize)
        case .right:
            maxX = max(min(maxX + translation.width, bounds.maxX), minX + minCropSize)
        case .none: return
        }
        cropRect = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    // MARK: - Pixel-Perfect Cropping Core
    private func processCrop() {
        let normalizedImage = image.normalizedOrientation()
        let scaledImageWidth = imageDisplayRect.width * imageScale
        let scaledImageHeight = imageDisplayRect.height * imageScale

        let imageScreenMinX = (containerSize.width / 2.0) + imageOffset.width - (scaledImageWidth / 2.0)
        let imageScreenMinY = (containerSize.height / 2.0) + imageOffset.height - (scaledImageHeight / 2.0)

        let pixelScaleX = normalizedImage.size.width / scaledImageWidth
        let pixelScaleY = normalizedImage.size.height / scaledImageHeight

        let actualCropX = (cropRect.minX - imageScreenMinX) * pixelScaleX
        let actualCropY = (cropRect.minY - imageScreenMinY) * pixelScaleY
        let actualCropWidth = cropRect.width * pixelScaleX
        let actualCropHeight = cropRect.height * pixelScaleY

        var actualCropRect = CGRect(x: actualCropX, y: actualCropY, width: actualCropWidth, height: actualCropHeight)
        actualCropRect = actualCropRect.intersection(CGRect(origin: .zero, size: normalizedImage.size))

        guard !actualCropRect.isNull, actualCropRect.width > 0, actualCropRect.height > 0,
              let cgImage = normalizedImage.cgImage?.cropping(to: actualCropRect) else {
            onCancel()
            return
        }
        onCrop(UIImage(cgImage: cgImage, scale: normalizedImage.scale, orientation: .up))
    }
}

extension UIImage {
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
}
