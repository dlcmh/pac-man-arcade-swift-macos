# Metal Crash Course

**Audience:** someone who knows how to build for the web — or has written ordinary
CPU code — and has never touched a GPU API. No Metal, shader, or linear-algebra
knowledge is assumed.

This is not a general Metal textbook. It is a guided tour of the Metal concepts
this repository actually uses, in roughly the order a frame encounters them. By
the end you should be able to open `Renderer.swift`, `Canvas.swift`, and
`MetalShaders.swift` and follow what every line is doing.

The one-sentence version:

> Sixty times a second, the CPU turns the game state into a flat list of coloured
> triangles, hands that list to the GPU in one buffer, and the GPU runs two tiny
> programs to position and colour those triangles on screen.

---

## 1. What Metal is — and is not

Metal is Apple's low-level API for talking to the GPU. The closest web
equivalents are **WebGL** (older, OpenGL-shaped) or **WebGPU** (newer, much closer
in spirit). It is not a game engine, a scene graph, or a drawing library. Metal
knows nothing about Pac-Man, ghosts, sprites, cameras, or physics. It knows about
buffers of bytes, shader programs, and draw calls.

Three Apple frameworks appear in this project:

| Framework | Job here |
| --- | --- |
| **AppKit** | The window, menu, keyboard events, and `UserDefaults` |
| **MetalKit** | `MTKView`, a convenient AppKit view that owns a Metal drawable and calls us once per frame |
| **Metal** | The actual GPU device, buffers, pipelines, command buffers, and shaders |

A useful way to think about the division of labour: the GPU is an extremely wide,
fairly dumb workforce. It is brilliant at doing the same small calculation to
millions of vertices or pixels at once. It is bad at branching, game rules, and
doing one thing at a time. So this project gives it exactly one job: **paint
triangles**.

### What the GPU does *not* do here

- It does not move Pac-Man, choose ghost directions, detect collisions, or keep
  score. Those are CPU-side Swift in `PacManCore`.
- It does not synthesise audio. `AVAudioEngine` does that on the CPU.
- It does not use compute shaders, lighting, textures, or a 3D camera.
- It does not own the game loop. `MTKView` schedules frames; `PacManCore` decides
  what happens inside them.

If you have read [Code Q&A question 3](QA.md#3-is-metal-used-for-all-computations),
this is the long version of that answer.

---

## 2. The mental model: a print shop

Metal's object names sound intimidating. They map to a simple workflow:

| Metal object | Print-shop analogy | In this project |
| --- | --- | --- |
| `MTLDevice` | The printing press | Created once from the system GPU |
| `MTLCommandQueue` | The queue of print jobs | One queue, created at startup |
| `MTLBuffer` | A tray of pre-printed forms | Vertex data and uniforms |
| `MTLRenderPipelineState` | The configured machine: which inks, which plates, what finishing | Shaders + blending + sample count, built once |
| Drawable / texture | The sheet of paper being printed | The `CAMetalLayer` drawable supplied by `MTKView` |
| `MTLCommandBuffer` | One job ticket | All GPU work for one frame |
| `MTLRenderCommandEncoder` | The operator writing instructions for that ticket | Records the pipeline, buffers, and draw call |
| `MTKView` | The shop front that keeps asking for another print | Calls `draw(in:)` continuously |

There is one more concept worth naming now: **uniforms**. These are a small packet
of values that stay constant for a whole draw call — the same for every vertex.
Here they hold the screen size, scale, and centring offset used to letterbox the
896 × 1092 design onto whatever window size you have.

### Web-developer translation table

| Web idea | This project |
| --- | --- |
| `<canvas>` backing store | The Metal drawable texture |
| `requestAnimationFrame` | `MTKView` calling `GameView.draw(in:)` at (nominally) 60 Hz |
| Canvas 2D paths and fills | `Canvas`, which expands everything into triangles |
| WebGL / WebGPU context | `MTLDevice` + `MTLCommandQueue` |
| A compiled shader program | `MTLRenderPipelineState` |
| `bufferData` with a typed array | Copying `[Float]` into an `MTLBuffer` |
| One `drawArrays` call | `encoder.drawPrimitives(type: .triangle, ...)` |
| CSS `object-fit: contain` | The scale/offset uniforms that letterbox the game |
| `devicePixelRatio` | `view.drawableSize` versus the window's point size |
| `gl.clear` | The render pass's clear colour |
| VSync / present | `commandBuffer.present(drawable)` |

The big difference from Canvas is that the browser's 2D API accepts high-level
shapes. Metal accepts only **vertices** and **draw calls**. Every circle, line,
letter, and scanline in this game has already been converted into triangles before
Metal sees it.

---

## 3. One frame at 30,000 feet

```text
MTKView fires the delegate at ~60 Hz
  └─ GameView.draw(in:)
       ├─ advance PacManGame in fixed 1/60 s steps
       ├─ drain gameplay events and play sounds
       └─ Renderer.render(game:in:)
            ├─ obtain the drawable + render pass from the view
            ├─ reset Canvas and append every triangle for the scene
            ├─ copy the vertex array into an MTLBuffer
            ├─ build uniforms (fit scale + centring offset)
            ├─ make a command buffer and render encoder
            ├─ set pipeline, vertex buffer, uniforms
            ├─ ONE drawPrimitives call for the whole frame
            └─ present(drawable) + commit
  └─ GPU asynchronously: vertex shader → rasterise → fragment shader → blend → screen
```

The central split is deliberate: **`GameView` advances the game, then `Renderer`
reads the finished state and draws it.** The renderer never writes gameplay state.
That rule is enforced by the architecture and is why the simulation can be tested
headlessly.

The entry point is
[`GameView.swift:90–120`](../Sources/PacManArcade/GameView.swift#L90-L120). The
renderer's frame is
[`Renderer.swift:78–152`](../Sources/PacManArcade/Renderer.swift#L78-L152).

---

## 4. Everything is a triangle

Look at [`Canvas.swift:36–73`](../Sources/PacManArcade/Canvas.swift#L36-L73). A
vertex is just six `Float` values:

```text
x, y, red, green, blue, alpha
```

That is 24 bytes per vertex. There are no texture coordinates, normals, indices, or
matrices. A triangle is written as three consecutive vertices. A rectangle is two
triangles; a circle is a fan of triangles; a thick line is a quad plus two round
caps; text is a collection of small rectangles. The pixel font, the ghost bodies,
the maze walls, and even the CRT scanlines all become the same six-float format.

The layout is defined on the Swift side by
[`Canvas.addVertex`](../Sources/PacManArcade/Canvas.swift#L55-L62) and consumed on
the GPU side by the `VertexIn` struct in
[`MetalShaders.swift:8–11`](../Sources/PacManArcade/MetalShaders.swift#L8-L11).
Those two definitions are a contract: if you change one, you must change the other.

### A concrete example: one dot

A dot is drawn as two concentric circles — a soft glow and a solid centre — in
[`Renderer.swift:283–305`](../Sources/PacManArcade/Renderer.swift#L283-L305).

`addCircle` uses 10 segments for a dot, so each circle is 10 triangles, and each
triangle is 3 vertices:

```text
2 circles × 10 triangles × 3 vertices = 60 vertices = 360 floats
```

A single dot is therefore 1,440 bytes of vertex data. The whole maze, actors, HUD,
and 273 scanlines are appended into one growing array every frame. That is the
**immediate mode** model: the CPU rebuilds the description of the entire scene from
scratch, rather than retaining GPU objects for each sprite.

This is a perfectly good trade for a small 2D game. It would be a poor trade for a
large 3D world with tens of thousands of objects, where you would keep geometry on
the GPU and reuse it.

### Why there is only one draw call

All of those triangles share the same vertex format, the same shaders, and the same
pipeline state. Nothing switches textures or materials mid-frame. So the renderer
can put the entire frame in one buffer and issue a single
[`drawPrimitives`](../Sources/PacManArcade/Renderer.swift#L143-L147) call.

Drawing order still matters. The scene is composed back-to-front:

[`Renderer.swift:86–96`](../Sources/PacManArcade/Renderer.swift#L86-L96)

1. backdrop and cabinet frame
2. maze walls
3. pellets and fruit
4. Pac-Man and ghosts
5. score popups
6. HUD text
7. overlays (READY!, pause, game over)
8. scanlines

There is no depth buffer. Later triangles simply paint over earlier ones — the
same painter's algorithm you would use with layered `<canvas>` elements or SVG.
The scanlines are last because they are a translucent darkening layer over
everything.

---

## 5. A frame in slow motion

### 5.1 Set-up happens once

At startup, `GameView` asks for the system GPU and configures the `MTKView`:

[`GameView.swift:23–45`](../Sources/PacManArcade/GameView.swift#L23-L45)

- `MTLCreateSystemDefaultDevice()` gets the GPU.
- `colorPixelFormat = .bgra8Unorm` chooses the drawable's pixel format.
- `sampleCount = 4` requests 4× MSAA when the GPU supports it, otherwise 1.
- `preferredFramesPerSecond = 60` and `enableSetNeedsDisplay = false` request a
  continuous 60 Hz redraw.
- `framebufferOnly = true` says the drawable will only be used as a render target,
  never read back or sampled. That is a legitimate optimisation.

`Renderer.init` then builds the long-lived objects:

[`Renderer.swift:28–76`](../Sources/PacManArcade/Renderer.swift#L28-L76)

1. Compile the Metal Shading Language source string into an `MTLLibrary`.
2. Look up the `vertex_main` and `fragment_main` functions.
3. Describe a render pipeline: which shader is which, blending on, the view's pixel
   format, and the view's sample count.
4. Build the pipeline state once.
5. Allocate three `MTLBuffer`s for vertex data.

**The shader is compiled at runtime.** The MSL lives in a Swift string in
[`MetalShaders.swift`](../Sources/PacManArcade/MetalShaders.swift), not in a `.metal`
file compiled by Xcode. That is why a successful `swift build` does not prove the
renderer will launch: a typo in the shader string is only discovered when
`Renderer.init` runs and the app tries to create the library.

### 5.2 The drawable and the render pass

`MTKView` owns a `CAMetalLayer` and vends a **drawable** — a texture that can be
presented to the display. It also supplies a **render pass descriptor**, which
describes the set of textures being rendered into and what to do at the start and
end of the pass.

[`Renderer.swift:78–84`](../Sources/PacManArcade/Renderer.swift#L78-L84)

The frame begins by asking for both. If either is unavailable — for example, the
window is minimised or the layer is not ready — the renderer simply returns and
tries again next frame. The pass clears to a near-black colour, which is why the
letterbox bars are black even before any triangles are drawn.

### 5.3 Build the scene on the CPU

The renderer resets the canvas and appends every primitive:

[`Renderer.swift:86–96`](../Sources/PacManArcade/Renderer.swift#L86-L96)

Each `draw…` method reads the current `PacManGame` and decides what that frame looks
like. For example, `drawPellets` uses the pellet positions, `drawPacman` uses the
mouth animation timer, and `drawGhost` switches colour based on frightened mode.
The GPU will never make those decisions; it only receives the resulting vertices.

### 5.4 Copy vertices into GPU-visible memory

After the scene is built, the CPU knows exactly how many vertices there are:

[`Renderer.swift:98–119`](../Sources/PacManArcade/Renderer.swift#L98-L119)

The renderer picks one of three pre-allocated buffers, grows it if this frame needs
more room, and copies the raw bytes from the Swift array into it. The buffers use
`.storageModeShared`, so both the CPU and the GPU can access that memory. On Apple
silicon this is unified memory; on Intel Macs the driver handles the details.

The three buffers and the semaphore implement **triple buffering**. The CPU can be
preparing frame N+1 while the GPU is still drawing frame N. The semaphore has a
value of 3, so the CPU blocks only when all three buffers are still in flight. Its
value is restored in the command buffer's completion handler after the GPU is done
with that frame. Without this, the CPU could overwrite vertex data the GPU is still
reading, producing flicker or torn geometry.

### 5.5 Letterboxing: design pixels to screen pixels

The game is authored at a fixed design resolution of **896 × 1092**. The window can
be any size and can be full screen, so the renderer computes a uniform scale that
fits the design inside the drawable, plus offsets that centre it:

[`Renderer.swift:121–131`](../Sources/PacManArcade/Renderer.swift#L121-L131)

```swift
let scale = min(drawableWidth / 896, drawableHeight / 1092)
let offsetX = (drawableWidth  - 896  * scale) / 2
let offsetY = (drawableHeight - 1092 * scale) / 2
```

`min` preserves the aspect ratio. If the window is wider than the design, there are
bars on the left and right; if it is taller, bars above and below. This is exactly
the idea behind `object-fit: contain` on the web, except it is done in the vertex
shader rather than by a layout engine.

Note that `drawableSize` is measured in **pixels**, not AppKit points. On a Retina
display the drawable is larger than the window's point size, which is why the
backing scale is handled for free as long as this calculation uses the drawable.

### 5.6 Encode the draw

Now the CPU records what the GPU should do:

[`Renderer.swift:133–151`](../Sources/PacManArcade/Renderer.swift#L133-L151)

1. Create a command buffer from the command queue.
2. Create a render command encoder from the pass descriptor.
3. Set the render pipeline state.
4. Bind the vertex buffer at index 0.
5. Bind the small uniforms struct at index 1.
6. Issue one triangle draw covering all vertices.
7. End encoding, present the drawable, and commit the command buffer.

The indices 0 and 1 are arbitrary but must match the `[[buffer(0)]]` and
`[[buffer(1)]]` attributes in the shader. This is the Metal equivalent of binding
attributes and uniforms before a WebGL draw.

### 5.7 The GPU takes over

Once committed, the command buffer is executed asynchronously. For each vertex,
the GPU runs `vertex_main` to produce a clip-space position and a colour. It then
rasterises each triangle into pixels (technically samples), interpolating the
colour across the triangle, and runs `fragment_main` for every covered sample. The
fragment shader simply returns the interpolated colour. Blending combines it with
whatever is already in the drawable.

If MSAA is active, the GPU shades multiple samples per pixel and resolves them into
the final drawable. That is what smooths the edges of diagonal maze walls and
circles without changing the game's pixel-art proportions.

Finally, the drawable is presented to the display. Because triple buffering is in
use, the CPU may already be several frames ahead by then.

---

## 6. The shaders, line by line

The complete MSL source is under 40 lines:
[`MetalShaders.swift:4–41`](../Sources/PacManArcade/MetalShaders.swift#L4-L41).

```metal
struct VertexIn {
    packed_float2 position;
    packed_float4 color;
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

struct Uniforms {
    float2 viewportSize;
    float2 scale;
    float2 offset;
};
```

`VertexIn` mirrors the six floats written by `Canvas`. `packed_float2` is important:
it means "two floats, tightly packed, no alignment padding", matching the raw Swift
array. `VertexOut.position` has the `[[position]]` attribute, which tells Metal this
is the required clip-space output. `color` is an ordinary varying that will be
interpolated and passed to the fragment shader.

```metal
vertex VertexOut vertex_main(const device VertexIn *vertices [[buffer(0)]],
                             constant Uniforms &uniforms [[buffer(1)]],
                             uint vertexID [[vertex_id]]) {
    VertexIn input = vertices[vertexID];
    float2 screenPosition = float2(input.position) * uniforms.scale + uniforms.offset;
    float2 ndc = float2((screenPosition.x / uniforms.viewportSize.x) * 2.0 - 1.0,
                        1.0 - (screenPosition.y / uniforms.viewportSize.y) * 2.0);
    ...
}
```

- `[[buffer(0)]]` is the vertex array bound in step 5.6.
- `[[buffer(1)]]` is the uniforms struct.
- `[[vertex_id]]` is the index Metal supplies automatically, from 0 to
  `vertexCount - 1`. There is no index buffer; the vertex shader just walks the
  array in order.
- The first line applies the letterbox transform, converting design coordinates to
  drawable pixels.
- The second line converts those pixels to **normalised device coordinates** (NDC),
  the `-1 … +1` square the rasteriser expects.

The Y flip deserves a moment. The game's design space uses screen-style coordinates:
`(0, 0)` is the top-left and Y grows downward. Metal clip space has Y pointing up
relative to that convention, so the shader uses `1.0 - (y / height) * 2.0`. If you
forget that flip, the entire game renders upside down.

The fragment shader is deliberately trivial:

```metal
fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
```

`[[stage_in]]` means "the interpolated outputs from the vertex shader". There is no
texture lookup, lighting, or discard. Since every vertex of a given triangle usually
has the same colour, the interpolation is invisible; its real purpose is to carry
colour through the pipeline.

> **Why `packed_float2` instead of `float2`?** `float2` has 8-byte alignment in MSL,
> while the Swift array stores two consecutive 4-byte floats. `packed_float2` tells
> the shader to read the bytes exactly as written. The `Uniforms` struct can use
> plain `float2` because both Swift's `SIMD2<Float>` and MSL's `float2` align each
> field to 8 bytes. Struct layout across the Swift/MSL boundary is a manual
> contract — there is no automatic reflection here.

---

## 7. Blending, MSAA, and the CRT look

The pipeline descriptor turns on straight-alpha blending:

[`Renderer.swift:47–60`](../Sources/PacManArcade/Renderer.swift#L47-L60)

```text
result = source.rgb * source.a + destination.rgb * (1 - source.a)
```

That is why a glow drawn with alpha `0.085` brightens the wall underneath instead
of replacing it, and why the final scanline pass can darken the whole image by 5.5%
per line. Order matters because there is no depth test; blending always reads
whatever was drawn before.

MSAA is configured on the view and mirrored by the pipeline's
`rasterSampleCount`. When 4× is available, each pixel keeps four colour samples and
the view resolves them into the final drawable. The extra samples cost memory and
bandwidth, but they make the many diagonal edges in the maze and characters much
less jagged. If a Mac does not support 4× sample counts, the game falls back to 1×
rather than failing.

The scanlines are not a post-processing shader. They are simply 273 translucent
one-pixel rectangles appended after the game world:
[`Renderer.swift:870–877`](../Sources/PacManArcade/Renderer.swift#L870-L877). That
is a good illustration of the immediate-mode approach: a visual effect that might
be a full-screen shader elsewhere is just more triangles here.

---

## 8. The performance bargain

This renderer makes several deliberate trade-offs:

| Choice | Cost | Benefit |
| --- | --- | --- |
| Rebuild all geometry every frame | CPU time and bus bandwidth | No retained scene graph, no per-object GPU state, trivially dynamic art |
| No index buffer | Duplicated vertices | Simpler vertex format and shader |
| One draw call | One very large vertex buffer | Minimal CPU driver overhead and state changes |
| No textures | More triangles for circles/letters | All art is procedural and resolution-independent |
| 4× MSAA | More samples and memory | Smoother edges |
| Three buffers + semaphore | ~7.2 MB of buffer memory | CPU and GPU can overlap safely |

For a scene this small, the CPU cost is modest and the simplicity is worth more than
micro-optimisation. If the game grew to tens of thousands of independently moving
objects, the next steps would be retaining static geometry (the maze) in a buffer,
batching dynamic geometry, or using instancing — none of which are needed at this
scale.

---

## 9. What this means when you change the renderer

- **Changing a shader is not caught by `swift build`.** The MSL is a runtime string.
  After any shader edit, launch the app and confirm it renders. A compile failure
  produces the "Metal initialization failed" alert.
- **Changing the vertex format is a two-file change.** The six-float layout in
  `Canvas.addVertex` and the `VertexIn` struct must agree. A mismatch can render
  garbage rather than fail loudly.
- **Changing the uniforms is also a two-file change.** Keep the Swift `Uniforms`
  struct and the MSL `Uniforms` struct in the same field order and alignment.
- **Changing draw order changes the image.** With no depth buffer, the last
  translucent layer wins. Insert new primitives where they belong in the back-to-front
  sequence.
- **Changing the pipeline is a startup decision.** Blend factors, pixel format, and
  sample count are baked into the pipeline state. If you change `sampleCount` on the
  view, the pipeline must be rebuilt with the same value.
- **Rendering has no automated test.** `PacManChecks` exercises the simulation, not
  pixels. Presentation changes require opening the app and looking at it.

These constraints are why `AGENTS.md` says a successful build is necessary but not
sufficient for rendering changes.

---

## 10. A guided reading path

Read these in order, ideally with the project open in an editor:

1. **[`MetalShaders.swift`](../Sources/PacManArcade/MetalShaders.swift)** — the whole
   GPU program. Start here because it is short and self-contained.
2. **[`Canvas.swift`](../Sources/PacManArcade/Canvas.swift)** — how a circle or a
   rectangle becomes triangles, and what six floats per vertex mean.
3. **[`Renderer.swift`](../Sources/PacManArcade/Renderer.swift)** — set-up once, then
   the per-frame sequence: gather drawable, build scene, upload, encode, present.
4. **[`GameView.swift`](../Sources/PacManArcade/GameView.swift)** — the `MTKView`
   delegate, fixed-step loop, and input handling.
5. **[`AppDelegate.swift`](../Sources/PacManArcade/AppDelegate.swift)** — the window
   and menu around the view.

### Three small experiments

Do these on a scratch branch; they are for learning, not for committing.

1. **Break the shader on purpose.** Remove a semicolon from
   `MetalShaders.swift`, run `swift build` (it succeeds), then launch the app. You
   will see why runtime shader compilation matters.
2. **Move a rectangle through the draw order.** Add a bright rectangle near the end
   of `drawPellets` and another at the end of `drawScanlines`. The second one appears
   on top of the scanlines; the first is darkened by them.
3. **Adjust the letterbox.** Change `scale` in `Renderer.render` to a constant and
   resize the window. The image stops fitting because the uniform no longer reflects
   the drawable size.

---

## 11. Glossary

| Term | Meaning |
| --- | --- |
| **GPU** | Graphics processing unit; a highly parallel processor for vertex and pixel work |
| **Metal** | Apple's low-level GPU API |
| **MetalKit** | Apple framework providing `MTKView` and drawable management |
| **MSL** | Metal Shading Language, a C++-like language for Metal shaders |
| **Shader** | A small program run on the GPU; here one per vertex and one per fragment |
| **Vertex** | A point with attributes; here position and colour |
| **Fragment** | A candidate pixel (sample) produced by rasterising a triangle |
| **Rasterisation** | Turning triangles into covered pixels/samples |
| **NDC** | Normalised device coordinates, the `-1 … +1` space before the viewport |
| **Drawable** | A texture supplied by the window system that can be presented |
| **Render pass** | A set of render targets and the actions taken at start/end |
| **Command buffer** | A recorded list of GPU work submitted as one unit |
| **Encoder** | The object that records render commands into a command buffer |
| **Pipeline state** | The compiled shader pair plus fixed-function state such as blending |
| **Uniform** | A value constant across a draw call, such as a transform |
| **Buffer** | A block of GPU-accessible memory; here the vertex and uniform data |
| **Texture** | An image-like GPU resource; this project does not use any for game art |
| **MSAA** | Multisample anti-aliasing; smoother edges via multiple samples per pixel |
| **Blending** | Combining a new fragment with the existing pixel using alpha |
| **Immediate mode** | Rebuilding and resubmitting all geometry every frame |
| **Triple buffering** | Cycling three buffers so CPU and GPU can work on different frames |
| **Semaphore** | A counter used here to stop the CPU overwriting in-flight GPU data |
| **Compute shader** | A GPU program for general computation; not used in this project |

---

## 12. Where to go next

- For why the game is split between CPU simulation and GPU rendering, see
  [Code Q&A question 3](QA.md#3-is-metal-used-for-all-computations).
- For the ghost AI that runs entirely on the CPU before any of this drawing happens,
  see [Code Q&A question 1](QA.md#1-how-do-the-ghosts-know-how-to-hunt-and-move-towards-pac-man).
- For the build, run, and verification workflow, see
  [CONTRIBUTING.md](../CONTRIBUTING.md).
- If you want a general Metal textbook after this, the concepts to search for next
  are vertex descriptors, index buffers, textures and samplers, depth testing,
  instancing, and compute pipelines. None of them are required to understand this
  game, but they are the natural next layer of the API.

The most useful thing to do now is to open the app, pause it, and trace one visible
object — a pellet, a ghost, a letter — from its game-state value through `Canvas`,
into the vertex buffer, through `vertex_main`, and out as pixels. Once that path is
clear, the rest of Metal is mostly variations on the same idea.
