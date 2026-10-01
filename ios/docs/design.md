# Design system

The iOS app continues the visual language of the web build so the two feel like one product:
near-black glass, one violet accent with cyan support, generous radii, and a single spring
curve for everything that moves.

## Tokens (`Design/Theme.swift`)

| Token | Value | Use |
|---|---|---|
| `background` | `#05060B` | backdrop under the glass |
| `glass` / `glassStrong` / `glassBright` | white at 5.5 / 8.5 / 12 % | surface fills |
| `border` / `borderBright` | white at 11 / 18 % | hairlines |
| `text` / `muted` / `mutedDim` | `#F5F7FC` / `#9AA4BD` / `#6B7389` | type |
| `violet` → `cyan` | `#8B5CF6` → `#22D3EE` | accent gradient |
| `green` / `amber` / `red` / `pink` | `#34D399` / `#FBBF24` / `#FB7185` / `#F472B6` | states |

Radii: 26 / 18 / 13 pt and a full pill. Type is the system font in `rounded` design for text
and `monospaced` for anything where one wrong glyph matters — addresses, hashes, words.

State colours are centralised: a `ScanState` and a `Verification` each map to exactly one
colour, so "verification required" is amber everywhere it appears.

## Glass

`GlassSurface` is a `.ultraThinMaterial` fill, a tinted overlay, and a border that runs from
`borderBright` at the top to `border` at the bottom — the top-lit edge is what makes it read as
glass rather than as a grey box. `GlassBackdrop` puts three blurred colour clouds behind
everything and drifts them over 22 seconds. It is cheap (three blurred circles) and it is the
reason the material has something to blur.

## Motion (`Design/Motion.swift`)

| Preset | Curve | Used for |
|---|---|---|
| `smooth` | spring 0.42 / 0.86 | layout changes, drawer, filters |
| `snappy` | spring 0.28 / 0.78 | button presses, toggles |
| `bouncy` | spring 0.5 / 0.68 | tab selection pill |
| `sweep` | ease-in-out 1.6 s | the scan sweep |
| `shimmer` | linear 2.2 s | loading sheen |

Lists appear with a 50 ms stagger (`appearIn(index)`), the tab bar morphs its pill with
`matchedGeometryEffect`, and the selected tab changes have a selection haptic. Numbers use
`.contentTransition(.numericText())` so a rescan does not jump.

## Icons

`Design/Icons.swift` draws all 28 glyphs as `Path`s on a 24×24 grid with 1.8 pt round-capped
strokes. Nothing is borrowed from SF Symbols: the app should not look like every other app
that ran out of time to draw its own icons. `IconView` takes size, stroke weight and colour, so
one glyph serves a 12 pt chip and a 40 pt header mark without a second asset.

## The three tabs and the drawer

The bottom bar is hand-built rather than `TabView`'s, because the design needs a pill that
morphs between tabs, glyph weight that changes with selection, and a blur that sits over the
content. Everything that is not one of the three tabs lives in the side drawer — scan history,
security, settings, about — which is opened from the header and dismissed by tapping outside,
the close button, or dragging it to the left.
