import Foundation
import CoreFoundation

public enum LegacyFilenameEncoding: String, Codable, CaseIterable, Sendable, Hashable {
    case utf8
    case gb18030
    case gbk
    case cp932
    case cp949
    case cp950
    case latin1

    public var stringEncoding: String.Encoding {
        switch self {
        case .utf8:
            return .utf8
        case .gb18030:
            let cfEnc = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
        case .gbk:
            let cfEnc = CFStringEncoding(CFStringEncodings.GBK_95.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
        case .cp932:
            let cfEnc = CFStringEncoding(CFStringEncodings.dosJapanese.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
        case .cp949:
            let cfEnc = CFStringEncoding(CFStringEncodings.dosKorean.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
        case .cp950:
            let cfEnc = CFStringEncoding(CFStringEncodings.big5.rawValue)
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cfEnc))
        case .latin1:
            return .isoLatin1
        }
    }
}

/// Heuristic CJK filename decoder for legacy archive encodings
/// (`gbk`, `cp932`, `cp949`, `cp950`, `gb18030`).
public enum LegacyCJKFilenameDecoder {

    public struct CandidateScore: Sendable {
        public let encoding: LegacyFilenameEncoding
        public let decoded: String
        public let hanCount: Int
        public let kanaCount: Int
        public let hangulCount: Int
        public let boxOrReplacementCount: Int
        public let totalScore: Int
    }

    public static func decodePath(_ rawBytes: Data, utf8FlagSet: Bool = false) -> (path: String, encoding: LegacyFilenameEncoding) {
        if utf8FlagSet, let utf8 = String(data: rawBytes, encoding: .utf8) {
            return (utf8, .utf8)
        }
        // Fast ASCII check
        if rawBytes.allSatisfy({ $0 < 0x80 }), let ascii = String(data: rawBytes, encoding: .utf8) {
            return (ascii, .utf8)
        }
        // Valid UTF-8 without replacement characters is strongly preferred
        if let utf8 = String(data: rawBytes, encoding: .utf8), !utf8.contains("\u{FFFD}") {
            return (utf8, .utf8)
        }

        let candidates: [LegacyFilenameEncoding] = [.gb18030, .cp932, .cp949, .cp950]
        var best: CandidateScore?

        for candidate in candidates {
            guard let str = String(data: rawBytes, encoding: candidate.stringEncoding),
                  !str.isEmpty,
                  !str.contains("\u{FFFD}") else {
                continue
            }
            let scored = score(decoded: str, encoding: candidate)
            if let currentBest = best {
                if scored.totalScore > currentBest.totalScore {
                    best = scored
                }
            } else {
                best = scored
            }
        }

        if let winner = best {
            return (winner.decoded, winner.encoding)
        }
        let fallback = String(data: rawBytes, encoding: .isoLatin1) ?? ""
        return (fallback, .latin1)
    }

    public static func score(decoded: String, encoding: LegacyFilenameEncoding) -> CandidateScore {
        var han = 0
        var kana = 0
        var hangul = 0
        var boxOrBad = 0
        var asciiPathChars = 0

        for scalar in decoded.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) {
                han += 1
            } else if (0x3040...0x309F).contains(v) || (0x30A0...0x30FF).contains(v) {
                kana += 1
            } else if (0xAC00...0xD7AF).contains(v) || (0x1100...0x11FF).contains(v) {
                hangul += 1
            } else if (0x2500...0x257F).contains(v) || v == 0xFFFD || (v < 0x20 && v != 0x09) || (0xE000...0xF8FF).contains(v) {
                boxOrBad += 1
            } else if v < 0x7F {
                asciiPathChars += 1
            }
        }

        // Language-specific script affinity bonus
        var scriptBonus = 0
        switch encoding {
        case .gb18030, .gbk:
            scriptBonus = han * 4 - kana * 2 - hangul * 3
        case .cp932:
            scriptBonus = kana * 6 + han * 3 - hangul * 3
        case .cp949:
            scriptBonus = hangul * 6 + han * 2 - kana * 3
        case .cp950:
            scriptBonus = han * 3 - kana * 2 - hangul * 3
        default:
            break
        }

        let total = (han + kana + hangul) * 10 + scriptBonus + asciiPathChars - (boxOrBad * 25)
        return CandidateScore(
            encoding: encoding,
            decoded: decoded,
            hanCount: han,
            kanaCount: kana,
            hangulCount: hangul,
            boxOrReplacementCount: boxOrBad,
            totalScore: total
        )
    }
}
