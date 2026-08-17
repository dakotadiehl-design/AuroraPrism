# Aurora Custom Value-Thumb Fader

## Implementation brief for Grok

**Selected direction:** Option C - Value Thumb  
**Scope:** Replace Aurora's current narrow vertical fader presentation with a large, custom SwiftUI control. Preserve the existing `AuroraFader` public API and all programmer semantics.

The reference render is `Aurora_Custom_Value_Thumb_Fader_Render_Pack.pdf` in this directory. Treat its dimensions and states as the visual contract.

## Why this change is required

The current vertical fader uses an 8 pt track, a 20 x 8 pt thumb, and a 48 pt total width. Although its full geometry is draggable, the visible handle looks like a small standard-library control and is difficult to acquire confidently during live programming.

Relevant current implementation:

- `Sources/AuroraUI/Components/AuroraFader.swift`
- `Sources/AuroraUI/DesignSystem/AuroraMetrics.swift`
- `Sources/AuroraUI/Panels/Programmer/ProgrammerColorEngineView.swift`
- `Sources/AuroraUI/Previews/AuroraComponentGallery.swift`

## Required outcome

Build a reusable custom vertical fader whose thumb is the dominant interaction target:

- Wide, rounded value thumb with the percentage rendered inside it.
- Clearly visible recessed track and colored fill.
- Large hit target across the entire fader channel.
- Precise click, drag, keyboard, and accessibility behavior.
- Correct valued, hovered, focused, dragging, mixed, unavailable, and disabled states.
- Emitter-specific colors for White, Amber, UV, and neutral channels.
- No regression to horizontal `AuroraFader` / `AuroraMasterFader` behavior.

## Public API compatibility

Keep the existing initializer source-compatible:

```swift
public init(
    value: Binding<Double>,
    label: String = "",
    iconName: String? = nil,
    isEnabled: Bool = true,
    showsOwnedChrome: Bool = false,
    display: AuroraControlDisplayValue = .value(0),
    axis: Axis = .vertical
)
```

Do not move business logic into the control. `AuroraFader` remains a presentation and input component over a normalized `0...1` binding.

Add an optional accent parameter if `.tint(...)` cannot be read reliably inside the custom drawing:

```swift
public var accent: Color?
```

Prefer respecting SwiftUI's tint environment so existing call sites remain unchanged.

## Geometry specification

Use design tokens rather than literals in the view.

| Element | Standard | Performance density | Notes |
|---|---:|---:|---|
| Total control width | 72 pt | 80 pt | Includes thumb overflow and hit area |
| Visible channel width | 42 pt | 48 pt | Recessed well |
| Track/fill width | 12 pt | 14 pt | Centered in channel |
| Thumb width | 64 pt | 72 pt | Primary grab target |
| Thumb height | 30 pt | 34 pt | Large enough for value text |
| Thumb corner radius | 8 pt | 9 pt | Rounded rectangle, not capsule |
| Minimum vertical travel | 140 pt | 168 pt | Excludes label/value footer |
| Tick inset | 4 pt | 5 pt | Ticks sit inside channel edges |
| Focus ring | 2 pt | 2 pt | Outside thumb silhouette |

Add tokens to `AuroraMetrics` with descriptive names, for example:

```swift
public static let valueFaderWidth: CGFloat = 72
public static let valueFaderChannelWidth: CGFloat = 42
public static let valueFaderTrackWidth: CGFloat = 12
public static let valueFaderThumbWidth: CGFloat = 64
public static let valueFaderThumbHeight: CGFloat = 30
public static let valueFaderThumbRadius: CGFloat = 8
public static let valueFaderHeight: CGFloat = 160
```

Do not simply enlarge the existing capsule thumb. The selected design requires a structured thumb containing value text and a grip indicator.

## Vertical layout

Recommended hierarchy:

```text
VStack
  label/icon header
  GeometryReader
    channel well
    tick marks
    active fill
    value thumb
  ownership or mixed indicator
```

Remove the separate percentage label above or below the fader when the value is already present in the thumb. `ProgrammerColorEngineView` currently adds another percentage beneath Dimmer and emitter faders; remove that duplicate only for the new value-thumb presentation.

Long labels such as `COOL WHITE` must remain readable. Allow two lines or use an abbreviated display label (`COOL W.`) while preserving the full accessibility label.

## Value-to-position mapping

The thumb must remain entirely inside the channel at both endpoints. Calculate travel using the thumb height:

```swift
let thumbHalf = metrics.thumbHeight / 2
let travel = max(1, geometry.size.height - metrics.thumbHeight)
let thumbCenterY = thumbHalf + (1 - normalizedValue) * travel
```

Map pointer position using the same travel interval:

```swift
let local = min(travel, max(0, locationY - thumbHalf))
let proposed = 1 - Double(local / travel)
value = min(1, max(0, proposed))
```

Using the same equation in both directions prevents endpoint jumps and makes clicking directly on the thumb stable.

## Drag behavior

Use `DragGesture(minimumDistance: 0, coordinateSpace: .local)` on the full channel hit region.

Required behavior:

1. Mouse-down anywhere in the channel moves the value to that position and begins dragging.
2. Mouse-down on the thumb must not jump. Capture the initial thumb/value and drag translation, or retain the pointer-to-thumb offset.
3. Continue clamping to `0...1` when dragged beyond the channel.
4. Update continuously during drag; do not wait for mouse-up.
5. Set an `isDragging` state on change and clear it on end.
6. Do not add implicit animation while dragging. A short 80-120 ms ease-out is acceptable for click-to-position only.
7. Preserve the current live-binding rule: while interactive, render from `value`, not a potentially delayed `display` snapshot.

## Fine control and keyboard behavior

Implement:

- Arrow Up/Right: `+0.01`
- Arrow Down/Left: `-0.01`
- Shift + arrow: `+/-0.001`
- Option + arrow: `+/-0.05`
- Home: `0`
- End: `1`
- Double-click thumb: optional reset only if a caller supplies an explicit default value; otherwise do nothing.

Do not infer or hard-code channel defaults inside `AuroraFader`.

## Visual construction

### Channel

- Rounded rectangle using `AuroraColor.surfaceWell`.
- Subtle inner border using `AuroraColor.separatorStrong`.
- Optional top-to-bottom shading, but avoid glossy skeuomorphism.
- Five major ticks at 0, 25, 50, 75, and 100%; minor ticks may be added if they remain quiet.

### Active fill

- Runs from the bottom endpoint to the thumb center.
- Uses the control tint or explicit accent.
- Neutral Dimmer: Aurora accent or cool white.
- White/Cool White: pale icy white-blue.
- Amber: warm gold-orange.
- UV: saturated violet.
- Glow must be restrained and clipped to the channel.

### Thumb

- Large rounded rectangle with a raised surface gradient.
- 1 pt neutral border at rest.
- 2 pt accent/focus border when keyboard-focused.
- Slight brightness lift and shadow on hover.
- Slightly stronger outline, no scale bounce, while dragging.
- Centered percentage text using monospaced digits, e.g. `72%`.
- Small horizontal grip line below or behind the value.
- Text must remain readable against every emitter color; use dark text on light White/Amber thumbs and white text on UV/neutral dark thumbs.

## Semantic states

### Value

Render thumb at the bound value and show `0%...100%`.

### Mixed

- Position at midpoint for presentation only.
- Do not pretend the value is 50%.
- Thumb is outline-only or hatched.
- Text inside thumb is exactly `MIXED`.
- First pointer/keyboard edit establishes a real value and exits mixed state through the parent binding.

### Unavailable

- No draggable thumb.
- Desaturate channel to approximately 35% opacity.
- Show an em dash or `N/A` in a stationary center badge.
- Remove interaction and keyboard focus.

### Disabled

- Preserve the last value position.
- Reduce opacity to approximately 40%.
- Do not accept pointer, keyboard, or accessibility adjustments.

### Owned

Preserve `showsOwnedChrome`. Use a small ownership dot or accent edge on the thumb; do not change the displayed numeric value.

## Accessibility

Keep the current adjustable accessibility action and improve it:

- Label: full channel name, never an abbreviation.
- Value: percentage, `mixed`, or `unavailable`.
- Trait: adjustable.
- Increment/decrement step: 5% for accessibility actions unless product requirements specify otherwise.
- Entire control should be one accessibility element.
- Minimum effective pointer target is the full 72 x travel-area rectangle.
- Focus ring must be visible in Increase Contrast mode.
- Do not encode emitter identity only by color; labels remain mandatory.

## Integration changes

### `AuroraFader.swift`

- Refactor the vertical body into small private views/helpers: channel, fill, ticks, thumb, geometry mapping.
- Leave `horizontalBody` behavior unchanged.
- Add hover and dragging visuals without coupling to programmer state.
- Continue using `display.isInteractive` and the existing `clamped` behavior.

### `AuroraMetrics.swift`

- Add Option C metrics rather than silently changing generic horizontal/master tokens.
- Density-specific values may be exposed through a small private metrics struct in `AuroraFader`.

### `ProgrammerColorEngineView.swift`

- Remove `.frame(width: 40)` and `.frame(width: 44)` constraints from emitter faders; they currently prevent a 64 pt thumb from fitting.
- Use 8-12 pt spacing between 72 pt faders.
- Allow horizontal scrolling when the fixture exposes more emitters than fit in the panel. Do not shrink faders below their minimum usable width.
- Remove duplicate percentage labels beneath Dimmer and emitters.
- Preserve `trackColor(for:)` and ensure it reaches the custom fader via tint/accent.

### Component gallery

Add previews showing:

- Dimmer at 72%.
- Cool White at 84%.
- Amber at 46%.
- UV at 31%.
- Hovered/focused appearance where practical.
- Mixed, unavailable, disabled, and owned states.
- Standard and performance density.
- Eight-emitter overflow inside the real programmer layout.

## Tests required

Separate value/geometry math into testable pure helpers. Add tests for:

1. Values 0, 0.5, and 1 map to bottom, middle, and top without clipping.
2. Pointer positions map back to the same values within floating-point tolerance.
3. Values and pointer positions clamp outside bounds.
4. A thumb-origin drag has no initial jump.
5. Continuous binding updates occur during drag.
6. Mixed state does not report `50%`.
7. Unavailable and disabled states reject input.
8. Accessibility increments/decrements clamp correctly.
9. Existing horizontal fader tests remain unchanged and pass.
10. Programmer layout supports Dimmer plus at least six emitters without reducing the fader width.

If UI tests can reliably address the custom control, add an accessibility-driven test that increments Dimmer and confirms the displayed percentage changes.

## Acceptance checklist

- [ ] Thumb is at least 64 x 30 pt in standard density.
- [ ] Full channel is clickable and draggable.
- [ ] Dragging never jumps when initiated on the thumb.
- [ ] Value updates continuously with no parent-presentation lag.
- [ ] Thumb stays fully visible at 0% and 100%.
- [ ] Percentage is rendered inside the thumb using monospaced digits.
- [ ] Dimmer, Cool White, Amber, and UV are visually distinct.
- [ ] Mixed, unavailable, disabled, focused, hovered, dragging, and owned states render correctly.
- [ ] More emitters cause horizontal scrolling, not undersized controls.
- [ ] Keyboard and accessibility adjustment work.
- [ ] Horizontal/master faders are unchanged.
- [ ] Component gallery previews and geometry tests are included.
- [ ] Full `swift test` and Xcode app build pass.

## Non-goals

- Do not alter DMX value semantics, programmer command behavior, fixture capability detection, undo policy, or emitter ordering.
- Do not introduce AppKit `NSSlider` wrappers.
- Do not make this a programmer-only one-off view; it must remain a reusable AuroraUI component.
- Do not shrink the selected design back to fit the current 40/44 pt emitter columns.
