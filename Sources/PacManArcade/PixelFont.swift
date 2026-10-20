import Foundation

enum TextAlignment {
    case left
    case center
    case right
}

/// A compact 5x7 pixel font. It is drawn as quads, so it stays crisp at
/// any window size and needs no font assets or text textures.
final class PixelFont {
    static let glyphWidth = 5
    static let glyphHeight = 7

    private static let glyphs: [Character: [UInt8]] = [
        "A": [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        "B": [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110],
        "C": [0b01111, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b01111],
        "D": [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110],
        "E": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111],
        "F": [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000],
        "G": [0b01111, 0b10000, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111],
        "H": [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001],
        "I": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111],
        "J": [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100],
        "K": [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001],
        "L": [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11111],
        "M": [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001],
        "N": [0b10001, 0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001],
        "O": [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        "P": [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000],
        "Q": [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101],
        "R": [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001],
        "S": [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110],
        "T": [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100],
        "U": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110],
        "V": [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b00100],
        "W": [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001],
        "X": [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001],
        "Y": [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100],
        "Z": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111],
        "0": [0b01110, 0b10001, 0b10011, 0b10101, 0b11001, 0b10001, 0b01110],
        "1": [0b00100, 0b01100, 0b00100, 0b00100, 0b00100, 0b00100, 0b11111],
        "2": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b01000, 0b11111],
        "3": [0b11111, 0b00010, 0b00100, 0b00010, 0b00001, 0b10001, 0b01110],
        "4": [0b00010, 0b00110, 0b01010, 0b10010, 0b11111, 0b00010, 0b00010],
        "5": [0b11111, 0b10000, 0b11110, 0b00001, 0b00001, 0b10001, 0b01110],
        "6": [0b00110, 0b01000, 0b10000, 0b11110, 0b10001, 0b10001, 0b01110],
        "7": [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000],
        "8": [0b01110, 0b10001, 0b10001, 0b01110, 0b10001, 0b10001, 0b01110],
        "9": [0b01110, 0b10001, 0b10001, 0b01111, 0b00001, 0b00010, 0b01100],
        "!": [0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00000, 0b00100],
        "?": [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100],
        ".": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100],
        ",": [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00100, 0b01000],
        ":": [0b00000, 0b00100, 0b00100, 0b00000, 0b00100, 0b00100, 0b00000],
        "-": [0b00000, 0b00000, 0b00000, 0b11111, 0b00000, 0b00000, 0b00000],
        "/": [0b00001, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b10000],
        "'": [0b00100, 0b00100, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000],
        "+": [0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000]
    ]

    private let canvas: Canvas

    init(canvas: Canvas) {
        self.canvas = canvas
    }

    func width(of text: String, pixelSize: CGFloat, letterSpacing: CGFloat? = nil) -> CGFloat {
        let count = text.count
        guard count > 0 else { return 0 }
        let spacing = letterSpacing ?? pixelSize
        return CGFloat(count) * CGFloat(Self.glyphWidth) * pixelSize + CGFloat(count - 1) * spacing
    }

    func draw(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        pixelSize: CGFloat,
        color: Color,
        alignment: TextAlignment = .left,
        letterSpacing: CGFloat? = nil
    ) {
        let uppercase = text.uppercased()
        guard !uppercase.isEmpty else { return }
        let totalWidth = width(of: uppercase, pixelSize: pixelSize, letterSpacing: letterSpacing)
        var cursorX: CGFloat
        switch alignment {
        case .left: cursorX = x
        case .center: cursorX = x - totalWidth * 0.5
        case .right: cursorX = x - totalWidth
        }

        let spacing = letterSpacing ?? pixelSize
        for character in uppercase {
            let glyph = Self.glyphs[character] ?? [UInt8](repeating: 0, count: 7)
            for (row, bits) in glyph.enumerated() {
                for column in 0..<Self.glyphWidth {
                    let mask = UInt8(1 << (Self.glyphWidth - 1 - column))
                    guard bits & mask != 0 else { continue }
                    canvas.addRect(
                        x: cursorX + CGFloat(column) * pixelSize,
                        y: y + CGFloat(row) * pixelSize,
                        width: pixelSize + 0.02,
                        height: pixelSize + 0.02,
                        color: color
                    )
                }
            }
            cursorX += CGFloat(Self.glyphWidth) * pixelSize + spacing
        }
    }

    func drawGlow(
        _ text: String,
        x: CGFloat,
        y: CGFloat,
        pixelSize: CGFloat,
        color: Color,
        alignment: TextAlignment = .left,
        glowColor: Color
    ) {
        draw(text, x: x + pixelSize * 0.28, y: y + pixelSize * 0.28, pixelSize: pixelSize, color: glowColor, alignment: alignment)
        draw(text, x: x - pixelSize * 0.16, y: y - pixelSize * 0.16, pixelSize: pixelSize, color: glowColor, alignment: alignment)
        draw(text, x: x, y: y, pixelSize: pixelSize, color: color, alignment: alignment)
    }
}
