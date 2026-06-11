# DesignReviewKit — Specification

A reusable iOS package that lets designers annotate a running app's UI, attach severity-rated commentary, and export a polished, shareable PDF report.

---

## 1. Summary of Decisions

| Area | Decision |
|---|---|
| Capture model | Frozen screenshot — annotate a static capture, never the live UI |
| Distribution | Local SPM package `DesignReviewKit`, zero host-app dependencies |
| Activation | Host app decides (shake expected); package exposes a presentation API |
| Build scope | Debug + TestFlight; gated out of App Store behavior |
| Session | Multi-screen: capture → annotate → save → navigate → re-trigger resumes |
| Persistence | In-memory only; session dies with the process |
| Annotation tool | Rectangle only (anchor-drag); move, resize, delete. No pencil |
| Comment flow | Comment sheet appears immediately on draw completion; cancel removes the rect |
| Severity | Low / Medium / High; default Low; severity drives annotation color |
| Numbering | Global across the session (screen 2 continues from screen 1); derived from order |
| PDF | Landscape A4, one page per annotation, full screenshot with others dimmed |
| Metadata | App name/version/build, device model, OS, screen size, per-capture timestamps |
| Export | Session review screen → Generate PDF → preview → share sheet. Explicit End Session |
| iOS target | iOS 17 |
| Architecture | No singletons — host owns the `DesignInspector` instance |

---

## 2. Architecture

### 2.1 Package

- `DesignReviewKit`, a local Swift package, iOS 17+, Swift 6 mode.
- Pure SwiftUI internally. No third-party dependencies.
- MVVM with the ViewState/ViewEvent pattern; `@Observable` view models.

### 2.2 Ownership — no singletons

The host app creates and owns the entry point at its composition root and injects it wherever the trigger lives:

```swift
// Composition root (AppDelegate / App struct)
let designInspector = DesignInspector(configuration: .init())

// Trigger site (e.g. shake handler)
designInspector.beginCapture(in: windowScene)
```

- All session state lives inside the `DesignInspector` instance. No `static let shared`, no global mutable state.
- `DesignInspector` is `@MainActor`.

### 2.3 Integration API (UIKit core + SwiftUI wrapper)

The primary host is an AppDelegate/UIKit app with SwiftUI screens, so the core API is imperative and window-scene based; a thin SwiftUI convenience wraps it.

```swift
@MainActor
public final class DesignInspector {
    public init(configuration: Configuration = .init())

    /// Begin a new session, or resume the open one, by capturing the
    /// host's key window and presenting the annotation UI.
    public func beginCapture(in windowScene: UIWindowScene)

    /// Whether a session with at least one captured screen is open.
    public private(set) var hasActiveSession: Bool
}
```

SwiftUI convenience (thin wrapper, same instance injected via environment):

```swift
extension View {
    /// Install the inspector so descendant views can trigger it.
    func designInspector(_ inspector: DesignInspector) -> some View
}
```

### 2.4 Presentation: overlay window

- The inspector UI lives in its own `UIWindow` (level above `.alert`) attached to the provided `UIWindowScene`, with a `UIHostingController` root.
- This guarantees the inspector floats above any host presentation (sheets, full-screen covers, tab bars) and that dismissing it never disturbs host view-controller state.
- The capture is taken **before** the overlay window becomes visible, so the inspector never appears in its own screenshots.

### 2.5 Build gating

- The package compiles everywhere; the host gates the *trigger* (e.g. wires the shake handler only in Debug/TestFlight builds).
- `Configuration` carries an `isEnabled` flag so hosts that prefer runtime gating (feature flag) can hard-disable `beginCapture` calls.

---

## 3. Session Lifecycle

```
shake ──▶ capture screen 1 ──▶ annotate ──▶ Save Screen ──▶ back to live app
                                                                │
            shake again ◀───────────────────────────────────────┘
                │
                ▼
         session resumes: captures screen 2, thumbnail strip shows screen 1
                ⋮
         Review ──▶ Generate PDF ──▶ preview ──▶ share
                └──▶ End Session (confirmed) ──▶ session destroyed
```

### 3.1 States

1. **Idle** — no session. `beginCapture` starts a session and captures the current screen.
2. **Annotating** — inspector presented, one screen active on the canvas.
3. **Suspended** — designer tapped **Save Screen**; overlay window hidden; session retained in memory; host app fully interactive. `beginCapture` resumes with a fresh capture of whatever is now on screen.
4. **Reviewing** — session review screen presented (list of all issues; export and end-session actions live here).
5. **Ended** — explicit End Session (with confirmation alert, since work is unrecoverable) or process death.

### 3.2 Rules

- Exporting does **not** end the session — the designer can export a partial report and continue.
- `beginCapture` while the inspector is already presented is a no-op.
- A capture with zero annotations that the designer saves is kept in the session (it may be annotated later via the thumbnail strip) but contributes no PDF pages.
- Memory bound: captures are stored JPEG-compressed (quality ~0.8); the canvas re-decodes per screen.

### 3.3 Inspector chrome (Annotating state)

- **Top bar**: screen label ("Screen 2"), issue count for this screen, **Review** button (badge with total session issue count).
- **Primary action**: **Save Screen** — suspends the session and returns to the live app.
- **Bottom thumbnail strip** (visible when the session has >1 screen): previously captured screens with annotation-count badges; tapping one switches the canvas to that screen for editing.
- **Discard Screen** available via overflow menu (removes the current capture after confirmation).

---

## 4. Capture

- Capture the host's key window with `UIGraphicsImageRenderer` + `drawHierarchy(in:afterScreenUpdates:false)` at the screen's native scale, before the overlay window is shown.
- Record per capture: timestamp, point size, display scale, interface orientation.
- The screenshot is captured as-is (dark mode, keyboards, transient UI included) — what the designer sees is what gets annotated.
- Screens captured in different orientations or on different size classes are independent; each PDF page scales its own screenshot.

---

## 5. Annotation Canvas

### 5.1 Drawing

- Single tool: **rectangle**. Touch down anchors one corner; dragging grows the rect toward the finger in any direction; lift to commit.
- Live rubber-band preview while dragging (severity-Low color until saved).
- **Minimum size**: commits below 16×16 pt are discarded silently (filters accidental micro-drags).
- On commit, the comment sheet is presented immediately (§6). The rect only becomes a real annotation when the sheet is saved.

### 5.2 Gesture arbitration

| Gesture | On | Result |
|---|---|---|
| Drag | Empty canvas | Draw a new rectangle |
| Tap | Existing rect | Select it (handles + action bar appear) |
| Tap | Empty canvas | Deselect |
| Drag | Inside selected rect | Move it |
| Drag | A handle of selected rect | Resize (8 handles: corners + edges) |
| Drag | Empty canvas while something is selected | Deselect, then draw |

- Hit-testing for selection uses the rect outline plus a 12 pt slop so thin rects are tappable. Overlapping rects: topmost (most recently created) wins; tapping again cycles to the one beneath.
- Move/resize clamps the rect inside the screenshot bounds.

### 5.3 Selection affordances

- Selected rect: solid stroke, 8 round handles, subtle shadow — Apple Markup feel.
- A floating action bar appears adjacent to the selection: **Edit Comment** (reopens the comment sheet pre-filled) and **Delete** (removes immediately; the drawing cost of recreating a rect is low enough that no confirmation is needed).

### 5.4 Badges and color

- Every annotation shows a **numbered badge** — a filled circle in its severity color with a white number — pinned to the rect's top-leading corner, clamped within the image bounds.
- Numbers are **derived from creation order across the whole session**, never stored. Deleting an annotation renumbers all subsequent ones automatically.
- Severity → color (fixed, also used in the PDF):

| Severity | Color |
|---|---|
| Low | System yellow |
| Medium | System orange |
| High | System red |

- Rect style: 2 pt stroke in severity color + 8% severity-color fill, continuous-corner radius 4 pt.

---

## 6. Comment Sheet

- Presented as a medium-detent sheet immediately after a rect is committed (and when editing an existing annotation).
- Contents, top to bottom:
  - Grabber + title ("Issue #7").
  - **Severity** segmented control: Low / Medium / High. Defaults to **Low** on new annotations.
  - **Comment**: multi-line `TextEditor`, focused automatically with keyboard up, growing with content (sheet expands to large detent as needed). Placeholder: "Describe the issue…".
  - **Save** button — disabled until the comment text is non-empty (trimmed).
- **Cancel / swipe-down on a new annotation removes the rectangle.** This is the invariant: every annotation in the session has a non-empty comment. No orphan handling exists anywhere downstream.
- Cancel while *editing* an existing annotation discards the edits but keeps the annotation.
- The severity control updates the rect's live preview color underneath the sheet as it changes.

---

## 7. Session Review Screen

Reached from **Review** in the inspector top bar. The pre-export checkpoint and the home of the two terminal actions.

- Scrollable list grouped by screen ("Screen 1 · 3 issues"), each row: cropped thumbnail of the annotated region, numbered severity badge, severity label, full comment text (multi-line).
- Tapping a row jumps back to that screen on the canvas with the annotation selected, ready to edit.
- Footer actions:
  - **Generate PDF** (primary, prominent) — disabled when the session has zero annotations.
  - **End Session** (destructive style) — confirmation alert: "End session? All screens and annotations will be discarded." Destroys the session and dismisses the overlay window.

---

## 8. PDF Report

### 8.1 Document structure

```
Page 1            Cover
Pages 2…N+1       One page per annotation, ordered by issue number
                  (which already groups them by screen)
```

No per-screen overview pages.

### 8.2 Page format

- **Landscape A4** (842 × 595 pt), fixed margins (~36 pt).

### 8.3 Cover page

- Report title ("Design Review"), session date.
- Metadata block (all auto-captured):
  - App name, marketing version, build number (host bundle).
  - Device model, iOS version, screen size in points + scale.
- Summary line: *N issues across M screens*, with per-severity counts as colored chips (e.g. ● 2 High ● 1 Medium ● 4 Low).

### 8.4 Annotation page (the core spread)

```
┌──────────────────────────────────────────────────────────────┐
│  Issue #7 · Screen 2                            ● High        │
│ ┌──────────────────┐  ┌────────────────────────────────────┐ │
│ │                  │  │  Severity chip   Captured 14:32     │ │
│ │   full           │  │                                     │ │
│ │   screenshot     │  │  Comment text, multi-line,          │ │
│ │   (this rect     │  │  rendered at a comfortable          │ │
│ │   full strength, │  │  reading size…                      │ │
│ │   others dimmed) │  │                                     │ │
│ │                  │  │                                     │ │
│ └──────────────────┘  └────────────────────────────────────┘ │
│                                            DesignReviewKit · 3/9 │
└──────────────────────────────────────────────────────────────┘
```

- **Left ~45%**: the full screenshot, aspect-fit. This issue's rectangle and badge drawn at full strength; all other annotations on that screen drawn ghosted (25% opacity). The reader always has full-screen context.
- **Right ~55%**: header row (issue number, severity chip in severity color, capture timestamp), then the comment in a clean text block.
- Rectangles and badges are drawn **vectorially** into the PDF from stored geometry (not baked into the bitmap) — crisp at any zoom.
- **Overflow**: if a comment exceeds the column, it continues on a follow-on page titled "Issue #7 · continued" with text only (rare; comments are typically short).
- Footer on every page: app name · page x of y.

### 8.5 Generation

- `UIGraphicsPDFRenderer` with Core Graphics + `NSAttributedString` drawing (vector text, vector shapes, bitmap screenshots).
- PDF document metadata (title, creator) set via renderer format.
- Generated off the main actor; the review screen shows a progress state for large sessions.
- Written to a temp file: `DesignReview-<AppName>-<yyyy-MM-dd-HHmm>.pdf`.

### 8.6 Coordinate model (the detail that makes this all work)

Annotation rects are stored in **normalized coordinates** (0…1 relative to the screenshot's point size), converted at the canvas and PDF layers. This makes canvas rendering, thumbnail crops, and PDF scaling trivially consistent and rotation/size-class proof.

---

## 9. Preview & Share

1. **Generate PDF** → progress → full-screen PDF preview (`PDFView` via `PDFKit`), so the designer sees exactly what will be sent.
2. Toolbar: **Share** (presents `UIActivityViewController` with the file URL — AirDrop, Slack, Mail, Save to Files all work for free) and **Done** (returns to the review screen).
3. Sharing does not end the session. The temp file is cleaned up when the session ends or a new export replaces it.

---

## 10. Visual Design (Apple-esque)

- The inspector should feel like a first-party Apple tool: SF Symbols, system materials (`.ultraThinMaterial` bars), continuous corners, spring animations on selection/handles, haptics (light impact on rect commit, selection changed on select).
- Supports light and dark appearance (the inspector chrome follows the system; the screenshot is whatever was captured).
- The annotation canvas dims the area around the screenshot with a subtle backdrop so the capture reads as "a document being marked up", not "the live app".
- All inspector strings are English-only for v1 (internal tool).

---

## 11. Data Model

```swift
struct ReviewSession {
    let startedAt: Date
    let appMetadata: AppMetadata          // name, version, build
    let deviceMetadata: DeviceMetadata    // model, OS, screen size, scale
    var screens: [CapturedScreen]
}

struct CapturedScreen: Identifiable {
    let id: UUID
    let imageData: Data                   // JPEG-compressed capture
    let imagePointSize: CGSize
    let capturedAt: Date
    var annotations: [Annotation]
}

struct Annotation: Identifiable {
    let id: UUID
    var normalizedRect: CGRect            // 0…1 in screenshot space
    var severity: Severity                // .low / .medium / .high
    var comment: String                   // non-empty by invariant
    let createdAt: Date                   // session-wide ordering → issue number
}
```

Issue numbers are computed: all annotations across all screens sorted by `createdAt`, index + 1.

---

## 12. Edge Cases & Policies

| Case | Policy |
|---|---|
| Drag commits < 16×16 pt | Discarded silently |
| Comment sheet cancelled on new rect | Rect removed — no orphan annotations exist |
| Delete annotation #2 of 9 | #3–9 renumber automatically (numbers are derived) |
| Overlapping rects, tap | Topmost wins; repeat taps cycle downward |
| Badge near screenshot edge | Clamped inside image bounds |
| `beginCapture` while inspector visible | No-op |
| Screen saved with zero annotations | Kept in session, contributes no PDF pages |
| Generate PDF with zero annotations | Button disabled |
| Orientation/size change between captures | Each screen stores its own size; pages scale independently |
| App backgrounded mid-session | Session survives (in memory) until process death |
| Process death | Session lost — accepted v1 trade-off |
| End Session | Confirmation alert (destructive, unrecoverable) |
| Memory pressure with many screens | JPEG-compressed storage; decode per active screen |

---

## 13. Out of Scope (v1) / Future

- Pencil/freehand, arrows, text labels on canvas — rectangle only.
- Disk persistence / crash recovery of sessions (flagged: debug builds crash; revisit if loss is felt in practice).
- Undo/redo (move/resize + delete + cheap redraw judged sufficient).
- Reviewer name on the cover.
- Per-screen overview pages in the PDF.
- View-hierarchy awareness (snapping rects to real views).
- Localization.
