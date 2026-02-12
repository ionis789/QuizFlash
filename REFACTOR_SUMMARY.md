# QuizFlash - Apple Notes-Style Editor Refactor

## Date: February 12, 2026

## Overview
Complete refactor of the QuizFlash card editor from a ZStack-based overlay system to an Apple Notes-style linear content flow editor. This eliminates the major UX issue where images would hide text behind them.

---

## What Changed

### 1. **New Data Model: ContentBlock**
**File:** `Features/Create/ContentBlock.swift`

- Created a new `ContentBlock` model supporting three types: `.text`, `.image`, `.sketch`
- Each block is a distinct unit in a vertical flow (like paragraphs in Notes)
- Blocks are ordered and serialized to JSON for persistence
- Created `CardSideContent` observable class to manage arrays of blocks
- Full backward compatibility with legacy text + images format

**Key Features:**
- Factory methods: `.text()`, `.image(data:)`, `.sketch(data:)`
- Migration support from legacy format
- Combined text extraction for search/preview
- Empty state detection

---

### 2. **Updated CardModel**
**File:** `Features/Create/CardModel.swift`

**Changes:**
- Added `frontBlocksData` and `backBlocksData` (JSON-encoded ContentBlock arrays)
- Kept legacy fields (`frontText`, `backText`, `frontImages`, `backImages`) for backward compatibility
- Computed properties `frontContent` and `backContent` return `CardSideContent` objects
- Automatic migration from legacy format when old data is loaded
- New initializer accepting `CardSideContent` directly

**Backward Compatibility:**
- Existing cards with legacy format automatically migrate on first access
- Legacy fields stay synchronized for search/preview features
- No data loss during migration

---

### 3. **BlockEditorView Component**
**File:** `Features/Create/BlockEditorView.swift`

**Apple Notes-Style Linear Editor:**
- Vertical `ScrollView` with `LazyVStack` of content blocks
- Each block type (text/image/sketch) renders inline - no overlapping
- Text blocks use native `TextField` with vertical axis
- Images/sketches display at full width with delete buttons
- Context menu on text blocks for adding media below
- Automatic focus management and keyboard scrolling
- PhotosPicker integration for adding images
- Tap empty space to add new text block

**Gesture Handling:**
- Long press on images/sketches shows delete option
- Context menu for inserting content between blocks
- Smooth animations for block insertion/deletion
- Auto-scroll to focused block when keyboard appears

---

### 4. **Refactored AddCardSheetView**
**File:** `Features/Create/AddCardSheetView.swift`

**Major Changes:**
- Removed ZStack overlay approach entirely
- Now uses two separate `BlockEditorView` instances (front/back)
- Toggle between Question/Answer with animated tab bar
- FAB (Floating Action Button) menu for Sketch/Photo/Keyboard
- Full-screen presentation on iPad (`.fullScreenCover`)
- Proper keyboard management - FAB closes when keyboard appears
- Sketch opens after keyboard dismisses (fixes conflict bug)

**UI Improvements:**
- Clean tab bar with content indicators (dot shows if side has content)
- Minimalist FAB menu with glass morphism
- Background tap closes menu
- Content indicator dots show which sides have content
- Save button disabled until both sides have content

**Bug Fixes:**
- ✅ Keyboard/FAB conflict resolved
- ✅ Full-screen on iPad (not small modal)
- ✅ Sketch visibility fixed
- ✅ No more overlapping content

---

### 5. **CanvasModalView (Sketch)**
**File:** `Features/Create/PaperKit/CanvasModalView.swift`

**Improvements:**
- Full-screen PencilKit canvas
- **Dark/Light mode adaptation** - canvas background changes with color scheme
  - Light mode: white background
  - Dark mode: dark gray background (white ink now visible!)
- Clear button to erase drawing
- Renders drawing to PNG with proper padding
- Clean navigation toolbar

**Bug Fixes:**
- ✅ Canvas adapts to color scheme (no more invisible white ink in dark mode)
- ✅ Sketch appears immediately after saving
- ✅ Proper bounds calculation with padding

---

### 6. **Updated CreateView**
**File:** `Features/Create/CreateView.swift`

**Changes:**
- Updated to use new `CardSideContent` instead of legacy string/array format
- `AddCardSheetView` now passes `CardSideContent` objects directly
- Simplified card creation/editing logic
- Full-screen presentation for editor (iPad support)
- Maintains all existing UX (success banner, animations, etc.)

---

### 7. **Updated CardRowView**
**File:** `Features/Create/CardRowView.swift`

**Changes:**
- Displays combined text from all text blocks
- Shows attachment indicators (photo/sketch icons)
- Handles empty states gracefully
- Works with new `CardSideContent` structure

---

### 8. **Updated FlipCardPreview**
**File:** `Features/Library/DeckPlay/FlipCardPreview.swift`

**Changes:**
- Renders blocks in linear order (text → image → text → sketch)
- Preview mode shows combined text + first image thumbnail
- Full mode (gameplay) scrolls through all blocks naturally
- Each block type renders with appropriate styling
- Sketches show proper background in both light/dark mode

**Display Logic:**
- **Preview (Grid):** Shows text preview + first image thumbnail
- **Full (Play):** ScrollView with all blocks in order

---

### 9. **Updated DeckView**
**File:** `Features/Library/Deck/DeckView.swift`

**Changes:**
- Card creation uses new `CardSideContent` format
- Simplified callback - no more 8-parameter legacy format
- Maintains all selection/deletion/sorting logic
- Full-screen presentation for add/edit

---

## Technical Implementation

### Data Flow

```
User Input (BlockEditorView)
    ↓
ContentBlock objects in CardSideContent
    ↓
JSON serialization to CardModel.frontBlocksData / backBlocksData
    ↓
SwiftData persistence (@Attribute .externalStorage)
    ↓
Deserialization on load
    ↓
Display in FlipCardPreview (linear flow)
```

### Backward Compatibility Strategy

1. **Legacy Data Detection:**
   - When `frontBlocksData` is nil, check `frontText` and `frontImages`
   - Automatically migrate to ContentBlock format on first access
   
2. **Synchronized Fields:**
   - When saving ContentBlocks, also update `frontText` (combined) and `frontImages` (extracted)
   - Enables search and preview without deserializing JSON
   
3. **No Breaking Changes:**
   - Existing cards load and display correctly
   - Old code paths still work during transition period

---

## Bug Fixes Summary

### ✅ Fixed Issues

1. **Images Overlapping Text** (PRIMARY ISSUE)
   - ❌ Before: ZStack with absolute positioning caused images to hide text
   - ✅ After: Linear VStack flow - images push content down naturally

2. **Scroll Freezing** (iOS 18/26)
   - ❌ Before: Complex gesture interactions caused scroll to freeze
   - ✅ After: Native ScrollView with proper gesture priority

3. **Keyboard/FAB Conflict**
   - ❌ Before: FAB menu stayed open when tapping text field
   - ✅ After: Keyboard appearance auto-closes FAB menu

4. **Sketch Not Appearing**
   - ❌ Before: Async timing issues prevented immediate display
   - ✅ After: Proper state management and block insertion

5. **Dark Mode Canvas Visibility**
   - ❌ Before: White canvas in dark mode made white ink invisible
   - ✅ After: Canvas background adapts to color scheme

6. **iPad Layout Issues**
   - ❌ Before: Small modal sheet on iPad, content cut off
   - ✅ After: Full-screen presentation with proper layout

---

## Architecture Improvements

### Before (Problems)
```
ZStack {
    TextEditor (full screen)
    ForEach(images) { image
        // Floating at absolute positions
        // HIDES TEXT UNDERNEATH
    }
}
```

### After (Solution)
```
ScrollView {
    LazyVStack {
        ForEach(contentBlocks) { block
            if block.type == .text {
                TextField(...)
            } else if block.type == .image {
                Image(...)  // PUSHES OTHER CONTENT DOWN
            } else if block.type == .sketch {
                Image(...)  // PUSHES OTHER CONTENT DOWN
            }
        }
    }
}
```

---

## File Structure

### New Files Created
```
Features/Create/
├── ContentBlock.swift              ✨ NEW - Core data model
├── BlockEditorView.swift           ✨ NEW - Linear editor component
└── PaperKit/
    └── CanvasModalView.swift       ✨ NEW - Full implementation

```

### Modified Files
```
Features/Create/
├── CardModel.swift                 🔄 UPDATED - Added ContentBlock support
├── AddCardSheetView.swift          🔄 UPDATED - Complete rewrite
├── CreateView.swift                🔄 UPDATED - New editor integration
└── CardRowView.swift               🔄 UPDATED - ContentBlock display

Features/Library/
├── Deck/
│   └── DeckView.swift              🔄 UPDATED - Simplified callbacks
└── DeckPlay/
    └── FlipCardPreview.swift       🔄 UPDATED - Linear block rendering
```

---

## Usage Examples

### Creating a New Card

```swift
// Old way (legacy)
let card = CardModel(
    frontText: "Question",
    backText: "Answer",
    frontImages: [imageData]
)

// New way (recommended)
let frontContent = CardSideContent(blocks: [
    .text("What is SwiftUI?"),
    .image(data: imageData),
    .text("Bonus question:")
])

let backContent = CardSideContent(blocks: [
    .text("A declarative UI framework"),
    .sketch(data: sketchData)
])

let card = CardModel(
    frontContent: frontContent,
    backContent: backContent
)
```

### Migration is Automatic

```swift
// Old card with legacy data
let oldCard = CardModel(frontText: "Test", backText: "Answer")

// Access automatically migrates
let content = oldCard.frontContent
// Returns: CardSideContent with [.text("Test")]

// Save updates both formats
oldCard.frontContent = newContent
// Updates: frontBlocksData + frontText (for search)
```

---

## Testing Checklist

### ✅ Core Functionality
- [x] Create card with text only
- [x] Create card with text + image
- [x] Create card with text + sketch
- [x] Create card with mixed content (text → image → text → sketch)
- [x] Edit existing cards
- [x] Delete blocks within editor
- [x] Reorder blocks (via context menu insert)

### ✅ UI/UX
- [x] Keyboard appears/dismisses smoothly
- [x] FAB menu closes when keyboard opens
- [x] Scroll auto-adjusts to focused text field
- [x] Images don't overlap text
- [x] Sketches visible in both light/dark mode
- [x] Full-screen presentation on iPad

### ✅ Persistence
- [x] Cards save correctly
- [x] Cards load correctly
- [x] Legacy cards migrate automatically
- [x] Search still works (uses combined text)

### ✅ Gestures
- [x] Tap text to edit
- [x] Tap image to see delete button
- [x] Context menu on text blocks
- [x] Long press for delete (images/sketches)
- [x] Swipe in gameplay mode

---

## Performance Considerations

### Optimizations Implemented

1. **LazyVStack** - Only renders visible blocks
2. **Lazy image loading** - Images load on-demand
3. **JSON caching** - Deserialized blocks cached in memory
4. **External storage** - Large data (images/sketches) stored externally
5. **Combined text** - Pre-computed for search without JSON parsing

### Memory Management

- Images stored as `Data` in SwiftData with `.externalStorage` attribute
- Sketches rendered to PNG (compressed) instead of storing full PKDrawing
- Blocks are value types (structs) for efficient copying
- Observable objects use `@Observable` macro (no Combine overhead)

---

## Known Limitations

1. **Block Reordering**: Currently no drag-to-reorder (future enhancement)
2. **Rich Text**: Text blocks are plain text only (no bold/italic)
3. **Image Editing**: No cropping/rotating within app (use Photos app)
4. **Sketch Editing**: Can't re-edit a saved sketch (must delete and recreate)

---

## Future Enhancements

### Planned Features
- [ ] Drag-and-drop block reordering
- [ ] Rich text formatting (bold, italic, links)
- [ ] Image cropping/resizing within editor
- [ ] Audio blocks (voice recording)
- [ ] Video blocks
- [ ] LaTeX math support
- [ ] Collaborative editing
- [ ] Block templates

### Architecture Ready For
- ✅ New block types (just add enum case)
- ✅ Block-level metadata (tags, timestamps)
- ✅ Version history (ContentBlock is Codable)
- ✅ Export/import (JSON serialization)

---

## Migration Guide for Users

### Automatic Migration
- Existing cards will continue to work
- First time opening a card converts it to new format
- No user action required
- No data loss

### What Users Will Notice
1. **Better Editing**: Images no longer hide text
2. **Smoother Scrolling**: No more freeze bugs
3. **Dark Mode**: Sketches now visible in dark mode
4. **iPad**: Full-screen editor instead of small modal
5. **Keyboard**: Better handling, no conflicts with menu

---

## Developer Notes

### Adding a New Block Type

1. Add enum case to `ContentBlockType`:
```swift
enum ContentBlockType: String, Codable {
    case text, image, sketch, video // ← Add here
}
```

2. Add factory method to `ContentBlock`:
```swift
static func video(url: URL) -> ContentBlock {
    ContentBlock(type: .video, videoURL: url)
}
```

3. Add rendering in `BlockView` (BlockEditorView.swift):
```swift
case .video:
    VideoPlayer(url: block.videoURL)
```

4. Add display in `CardFaceView` (FlipCardPreview.swift):
```swift
case .video:
    VideoPlayer(url: block.videoURL)
        .frame(height: 300)
```

---

## Support & Troubleshooting

### Common Issues

**Q: My old cards look different**
A: Old cards are automatically migrated. The content is the same, just displayed in a cleaner linear format.

**Q: Images are too large**
A: Images scale to fit width automatically. Resize before importing for best results.

**Q: Sketch isn't saving**
A: Make sure you tap "Done" after drawing. Empty sketches are not saved.

**Q: Keyboard covers my text**
A: The editor auto-scrolls to keep focused text visible. Make sure you're running iOS 17+.

---

## Credits

**Refactor Completed:** February 12, 2026  
**Architecture:** Apple Notes-inspired linear content flow  
**Framework:** SwiftUI + SwiftData + PencilKit  
**Compatibility:** iOS 17+, iPadOS 17+

---

## Summary

This refactor successfully transforms QuizFlash from a buggy overlay-based editor to a professional, Apple Notes-style linear content editor. All major bugs are fixed, UX is significantly improved, and the architecture is now extensible for future features.

**Result:** A native-feeling, bug-free, professional flashcard creation experience. ✨
