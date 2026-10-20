# How does the 5×7 procedural font work?

- **Project:** PAC-MAN — Metal Arcade
- **Recorded:** 2026-10-20 (+08:00, Asia/Kuala_Lumpur)
- **Last updated:** 2026-10-20

**Short answer:** every character is a seven-byte bitmap. Each of the five bits in
each row becomes one small rectangle, and every rectangle becomes two triangles.
The GPU sees only coloured triangles — there is no font file, no glyph atlas, and
no texture sampling anywhere in the text path. That is why the font stays sharp
as the window scales.

## The glyph data

- [`PixelFont.swift`](../../Sources/PacManArcade/PixelFont.swift) — `PixelFont`
  declares a 5 × 7 cell: `glyphWidth` is 5, `glyphHeight` is 7. The `glyphs`
  dictionary maps a `Character` to seven `UInt8` values, one per row.

Here is the entry for `A`:

```swift
"A": [0b01110,
      0b10001,
      0b10001,
      0b11111,
      0b10001,
      0b10001,
      0b10001],
```

Read the binary literals as pictures — `1` is ink, `0` is empty:

```text
.###.
#...#
#...#
#####
#...#
#...#
#...#
```

Only the lower five bits of each byte are used. The mask in `draw` is
`1 << (glyphWidth - 1 - column)`, so the most significant of those five bits is
the leftmost column. The table is deliberately uppercase-only: the dictionary
contains `A`–`Z`, `0`–`9`, and a small set of punctuation (`.`, `,`, `:`, `-`,
`/`, `'`, `+`, `!`, `?`). Any character not in the table is drawn as seven empty
rows, and the whole string is uppercased before lookup.

## Drawing a string

- [`PixelFont.swift`](../../Sources/PacManArcade/PixelFont.swift) — `draw` is the
  whole renderer for text.

It works in five steps:

1. Uppercase the string.
2. Measure it with `width`, which returns
   `count × 5 × pixelSize + (count − 1) × spacing`. Spacing defaults to
   `pixelSize`, i.e. one blank pixel column between glyphs.
3. Set `cursorX` according to the `TextAlignment`: left, centre, or right.
4. For every glyph, walk its seven rows and five columns. When a bit is set,
   call `Canvas.addRect` at
   `cursorX + column × pixelSize`, `y + row × pixelSize`, with a width and height
   of `pixelSize + 0.02`.
5. Advance `cursorX` by `5 × pixelSize + spacing` and repeat.

The extra `0.02` in the rectangle size is a deliberate overlap. Adjacent quads
share an edge; without the overlap, floating-point rounding can leave a hairline
seam between two supposedly touching pixels.

`drawGlow` is not a blur. It simply calls `draw` three times: twice at small
offsets in a translucent glow colour, then once at the original position in the
real colour. The layered quads produce the neon halo used by the title and the
`READY!` prompt.

## From a lit bit to a pixel on screen

Each `addRect` goes through
[`Canvas.swift`](../../Sources/PacManArcade/Canvas.swift) — `addRect` builds a
quad, `addQuad` splits it into two triangles, and `addTriangle` appends three
vertices of `x, y, r, g, b, a`. The whole frame's vertex list is copied into one
buffer and submitted in a single draw call. The GPU then runs the two tiny
shaders in [`MetalShaders.swift`](../../Sources/PacManArcade/MetalShaders.swift) —
`MetalShaderSource` — which scale the 2D position, convert it to clip space, and
output the vertex colour. No texture coordinates exist, so there is no glyph
texture to magnify or blur.

The font object itself is created once as a renderer-owned helper:
[`Renderer.swift`](../../Sources/PacManArcade/Renderer.swift) — `font` is a lazy
`PixelFont` sharing the frame's `Canvas`, so glyph rectangles are appended to the
same triangle stream as the maze and characters.

## What "crisp at any window size" means

The game is composed at an 896 × 1092 design resolution and uniformly scaled to
the drawable. Text is geometry, so scaling changes the coordinates of the
rectangles rather than resampling a bitmap. A glyph edge is a real triangle edge:
there is no pixel grid in a texture to reveal or interpolate. That is the sense in
which it stays crisp.

It does **not** mean every stem lands exactly on a physical pixel. At a
non-integer scale, a rectangle can span pixel boundaries; 4× MSAA antialiases
those edges. The result stays sharp and legible, but it is geometric scaling, not
integer pixel-art snapping. If exact pixel-grid alignment were required, the
renderer would need to snap positions and sizes to whole physical pixels.

## Why build a font this way?

- **No assets.** The glyph table is code, which satisfies the project's
  procedural-assets rule and avoids font licensing.
- **One pipeline.** Text is just more triangles, so it needs no second shader,
  texture binding, or draw call.
- **Small and predictable.** The data is 7 bytes per glyph, and the renderer does
  no shaping or layout beyond advancing a cursor.
- **Consistent style.** The same chunky pixel grid is used for the HUD, the
  title, the score, and the prompts.

The trade-offs are equally clear: uppercase-only, no kerning, no ligatures, no
Unicode coverage, and no anti-aliased font hinting beyond MSAA. For an arcade HUD
that is a feature rather than a limitation.

To add a character, add an entry to `glyphs` with seven five-bit rows, using
`1` for ink and `0` for empty, then use it in any string. The existing `draw`
path picks it up automatically; no atlas or font file needs regenerating.
