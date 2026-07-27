import Foundation

public enum ANSIColor: Equatable, Sendable {
    case `default`
    case ansi(Int)
    case indexed(Int)
    case rgb(UInt8, UInt8, UInt8)

    public var legacyCode: Int {
        switch self {
        case .default: return 0
        case .ansi(let code): return code
        case .indexed(let index): return 10_000 + index
        case .rgb(let red, let green, let blue):
            return 20_000 + (Int(red) << 16) + (Int(green) << 8) + Int(blue)
        }
    }
}

public struct ANSISegment: Equatable, Sendable {
    public let text: String
    /// Compatibility value: 0 for terminal default; ANSI SGR code for basic colors.
    public let colorCode: Int
    public let foreground: ANSIColor
    public let background: ANSIColor
    public let isBold: Bool
    public let isDim: Bool
    public let isItalic: Bool
    public let isUnderlined: Bool
    public let isInverted: Bool

    public init(
        text: String,
        foreground: ANSIColor = .default,
        background: ANSIColor = .default,
        isBold: Bool = false,
        isDim: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        isInverted: Bool = false
    ) {
        self.text = text
        self.foreground = foreground
        self.background = background
        self.isBold = isBold
        self.isDim = isDim
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.isInverted = isInverted
        self.colorCode = foreground.legacyCode
    }

    public init(text: String, colorCode: Int) {
        self.init(text: text, foreground: colorCode == 0 ? .default : .ansi(colorCode))
    }
}

public final class ANSIParser {
    private struct State: Equatable {
        var foreground: ANSIColor = .default
        var background: ANSIColor = .default
        var isBold = false
        var isDim = false
        var isItalic = false
        var isUnderlined = false
        var isInverted = false

        mutating func reset() { self = State() }
    }

    public init() {}

    /// Parses SGR (`ESC[...m`) sequences, including 16-color, 256-color and RGB colors.
    /// Non-printing CSI and OSC control sequences are removed from the result.
    public func parse(_ input: String) -> [ANSISegment] {
        var result: [ANSISegment] = []
        var state = State()
        var printable = ""
        let characters = Array(input)
        var index = 0

        func flush() {
            guard !printable.isEmpty else { return }
            let segment = ANSISegment(
                text: printable,
                foreground: state.foreground,
                background: state.background,
                isBold: state.isBold,
                isDim: state.isDim,
                isItalic: state.isItalic,
                isUnderlined: state.isUnderlined,
                isInverted: state.isInverted
            )
            if let last = result.last,
               last.foreground == segment.foreground,
               last.background == segment.background,
               last.isBold == segment.isBold,
               last.isDim == segment.isDim,
               last.isItalic == segment.isItalic,
               last.isUnderlined == segment.isUnderlined,
               last.isInverted == segment.isInverted {
                result[result.count - 1] = ANSISegment(
                    text: last.text + segment.text, foreground: segment.foreground, background: segment.background,
                    isBold: segment.isBold, isDim: segment.isDim, isItalic: segment.isItalic,
                    isUnderlined: segment.isUnderlined, isInverted: segment.isInverted
                )
            } else {
                result.append(segment)
            }
            printable = ""
        }

        while index < characters.count {
            guard characters[index] == "\u{001B}", index + 1 < characters.count else {
                printable.append(characters[index])
                index += 1
                continue
            }

            let kind = characters[index + 1]
            if kind == "[" {
                var end = index + 2
                while end < characters.count, !("@"..."~").contains(characters[end]) { end += 1 }
                guard end < characters.count else {
                    printable.append(characters[index])
                    index += 1
                    continue
                }
                if characters[end] == "m" {
                    flush()
                    let rawParameters = String(characters[(index + 2)..<end])
                    applySGR(rawParameters, to: &state)
                }
                index = end + 1
            } else if kind == "]" {
                // OSC ends with BEL or ST (ESC backslash).
                var end = index + 2
                while end < characters.count {
                    if characters[end] == "\u{0007}" { end += 1; break }
                    if characters[end] == "\u{001B}", end + 1 < characters.count, characters[end + 1] == "\\" { end += 2; break }
                    end += 1
                }
                index = end
            } else {
                // Two-byte escape controls (save cursor, reset, etc.) are non-printing.
                index += 2
            }
        }
        flush()
        return result
    }

    private func applySGR(_ rawParameters: String, to state: inout State) {
        let parameters = rawParameters.isEmpty ? [0] : rawParameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        var index = 0
        while index < parameters.count {
            let code = parameters[index]
            switch code {
            case 0: state.reset()
            case 1: state.isBold = true
            case 2: state.isDim = true
            case 3: state.isItalic = true
            case 4, 21: state.isUnderlined = true
            case 7: state.isInverted = true
            case 22: state.isBold = false; state.isDim = false
            case 23: state.isItalic = false
            case 24: state.isUnderlined = false
            case 27: state.isInverted = false
            case 30...37, 90...97: state.foreground = .ansi(code)
            case 39: state.foreground = .default
            case 40...47, 100...107: state.background = .ansi(code)
            case 49: state.background = .default
            case 38, 48:
                let foreground = code == 38
                guard index + 1 < parameters.count else { index += 1; continue }
                let mode = parameters[index + 1]
                if mode == 5, index + 2 < parameters.count {
                    let color = ANSIColor.indexed(max(0, min(255, parameters[index + 2])))
                    if foreground { state.foreground = color } else { state.background = color }
                    index += 2
                } else if mode == 2, index + 4 < parameters.count {
                    let color = ANSIColor.rgb(
                        UInt8(max(0, min(255, parameters[index + 2]))),
                        UInt8(max(0, min(255, parameters[index + 3]))),
                        UInt8(max(0, min(255, parameters[index + 4])))
                    )
                    if foreground { state.foreground = color } else { state.background = color }
                    index += 4
                }
            default: break
            }
            index += 1
        }
    }
}
