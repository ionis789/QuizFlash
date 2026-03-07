//
//  ImageCropEditorView.swift
//  QuizFlash
//
//  Production-ready freeform image cropping tool (Apple Photos style).
//

import SwiftUI

// MARK: - Crop Drag Handle

/// Identifies which edge or corner of the crop frame is being dragged.
private enum CropDragHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case none
}

// MARK: - Image Crop Editor View

/// Full-screen freeform image cropping editor.
///
/// Supports:
/// - Pinch-to-zoom and pan on the underlying image
/// - Edge and corner drag handles for precise crop region selection
/// - Rounded-corner crop frame with a rule-of-thirds grid overlay
/// - A reset action that animates back to the original framing
struct ImageCropEditorView: View {
    let image: UIImage
    var onCrop: (UIImage) -> Void
    var onCancel: () -> Void

    // MARK: - View & Layout State
    @State private var containerSize: CGSize = .zero
    @State private var imageDisplayRect: CGRect = .zero

    // MARK: - Crop Rect State
    @State private var cropRect: CGRect = .zero
    @State private var lastCropRect: CGRect = .zero
    @State private var activeHandle: CropDragHandle = .none

    // MARK: - Zoom & Pan State
    @State private var imageScale: CGFloat = 1.0
    @State private var lastImageScale: CGFloat = 1.0
    @State private var imageOffset: CGSize = .zero
    @State private var lastImageOffset: CGSize = .zero

    // MARK: - UI State
    @State private var isInteracting: Bool = false

    private let minCropSize: CGFloat = 80
    private let handleSize: CGFloat = 44
    private let cornerRadius: CGFloat = 16

    /// Uses the app's global accent color for interactive UI chrome (toolbar buttons, Done button).
    private var accent: Color { ThemeManager.shared.accentColor.color }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ZStack {
                    Color.black.ignoresSafeArea()

                    if imageDisplayRect != .zero {
                        // 1. Underlying image — zoomable and pannable
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

                        // 2. Dimmed overlay with rounded crop cutout
                        dimmedOverlay

                        // 3. Interactive crop frame — grid lines + drag handles
                        cropFrameView
                    }
                }
                .onAppear { setupInitialLayout(with: proxy.size) }
                .onChange(of: proxy.size, initial: false) { _, newSize in setupInitialLayout(with: newSize) }
            }
            // Prevents the iOS system home bar from intercepting bottom-edge crop drags.
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
                
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: resetToOriginal) {
                        Image(systemName: "arrow.uturn.backward")
                            .fontWeight(.semibold)
                    }
                    .tint(.white)
                    // Shown only when the crop or pan/zoom state differs from the original.
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

    /// Returns `true` when the crop region, zoom, or pan state differs from its initial value.
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

    /// Semi-transparent black overlay with a rounded rectangular cutout revealing
    /// only the selected crop region.
    private var dimmedOverlay: some View {
        Color.black.opacity(0.7)
            .ignoresSafeArea()
            .mask(
                ZStack {
                    Color.black
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
            // Inner grid and border
            gridOverlay
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            // Thick rounded corner accents — purely decorative
            thickRoundedCorners
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .allowsHitTesting(false)

            // Edge handles
            edgeHandle(for: .top)
            edgeHandle(for: .bottom)
            edgeHandle(for: .left)
            edgeHandle(for: .right)

            // Corner handles (invisible hit targets)
            invisibleCornerHitbox(for: .topLeft)
            invisibleCornerHitbox(for: .topRight)
            invisibleCornerHitbox(for: .bottomLeft)
            invisibleCornerHitbox(for: .bottomRight)
        }
    }

    private var gridOverlay: some View {
        ZStack {
            // Main border
            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(Color.white, lineWidth: 1.5)

            // Rule-of-thirds grid lines
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
            // Clip grid lines so they don't bleed past the rounded corners.
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .opacity(isInteracting ? 1.0 : 0.0)
        }
    }

    /// Draws thick rounded-corner accents by masking a stroked rectangle
    /// so only the four corner regions remain visible.
    private var thickRoundedCorners: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .stroke(Color.white, lineWidth: 4)
            .mask(
                ZStack {
                    let size: CGFloat = 40
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

    // MARK: - Gestures

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

    // MARK: - Crop Rect Mutation

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

    // MARK: - Pixel-Perfect Crop

    /// Converts the screen-space crop rectangle back to pixel coordinates in the
    /// original image and performs the actual `CGImage` crop.
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

// MARK: - UIImage Orientation Helper

extension UIImage {
    /// Returns a new image with the orientation normalised to `.up`.
    ///
    /// Some camera captures arrive with a non-standard `imageOrientation` that
    /// must be baked into the pixel data before cropping, otherwise the crop
    /// rectangle will be applied to the wrong axis.
    func normalizedOrientation() -> UIImage {
        if imageOrientation == .up { return self }
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return normalizedImage ?? self
    }
}
