import Foundation
import CoreGraphics
import AppKit

/// Farbpalette und Licht-Einschätzung eines Fotos – hilft, einen Look nachzubauen.
struct LookAnalysis {
    struct Swatch: Identifiable {
        let id = UUID()
        let color: NSColor
        let hex: String
        let share: Double
    }

    let palette: [Swatch]
    let tonality: String      // Low-Key / Mittlere Tonwerte / High-Key
    let contrast: String      // harter / mittlerer / weicher Kontrast
    let temperature: String   // warm / neutral / kühl
    let saturation: String    // fast monochrom / zurückhaltend / kräftig

    var summary: [String] { [tonality, contrast, temperature, saturation] }
}

enum LookAnalyzer {
    static func analyze(_ image: CGImage) -> LookAnalysis? {
        let size = 48
        var buf = [UInt8](repeating: 0, count: size * size * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { ptr in
            guard let ctx = CGContext(data: ptr.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                      bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard ok else { return nil }

        let n = size * size
        var lums = [Double](); lums.reserveCapacity(n)
        var sumR = 0.0, sumB = 0.0, sumSat = 0.0
        // Farb-Buckets (4 Bit je Kanal) für die Palette
        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        for i in stride(from: 0, to: buf.count, by: 4) {
            let r = Double(buf[i]) / 255, g = Double(buf[i + 1]) / 255, b = Double(buf[i + 2]) / 255
            lums.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            sumR += r; sumB += b
            let mx = max(r, g, b), mn = min(r, g, b)
            sumSat += mx > 0 ? (mx - mn) / mx : 0
            let key = (Int(buf[i]) >> 4) << 8 | (Int(buf[i + 1]) >> 4) << 4 | (Int(buf[i + 2]) >> 4)
            var e = buckets[key] ?? (0, 0, 0, 0)
            e.count += 1; e.r += r; e.g += g; e.b += b
            buckets[key] = e
        }
        let mean = lums.reduce(0, +) / Double(n)
        let std = (lums.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(n)).squareRoot()
        let warmth = (sumR - sumB) / Double(n)
        let sat = sumSat / Double(n)

        // Palette: häufigste Buckets, die sich deutlich voneinander unterscheiden
        var picked: [(r: Double, g: Double, b: Double, count: Int)] = []
        for (_, e) in buckets.sorted(by: { $0.value.count > $1.value.count }) {
            let c = (r: e.r / Double(e.count), g: e.g / Double(e.count), b: e.b / Double(e.count), count: e.count)
            let distinct = picked.allSatisfy { p in
                abs(p.r - c.r) + abs(p.g - c.g) + abs(p.b - c.b) > 0.18
            }
            if distinct { picked.append(c) }
            if picked.count == 5 { break }
        }
        let total = Double(picked.reduce(0) { $0 + $1.count })
        let palette = picked.map { c in
            LookAnalysis.Swatch(
                color: NSColor(srgbRed: c.r, green: c.g, blue: c.b, alpha: 1),
                hex: String(format: "#%02X%02X%02X", Int(c.r * 255), Int(c.g * 255), Int(c.b * 255)),
                share: total > 0 ? Double(c.count) / total : 0)
        }

        let tonality = mean < 0.3 ? "Low-Key" : (mean > 0.62 ? "High-Key" : "Mittlere Tonwerte")
        let contrast = std > 0.24 ? "harter Kontrast" : (std < 0.13 ? "weicher Kontrast" : "mittlerer Kontrast")
        let temperature = warmth > 0.05 ? "warm" : (warmth < -0.03 ? "kühl" : "neutral")
        let saturation = sat < 0.12 ? "fast monochrom" : (sat > 0.45 ? "kräftige Farben" : "zurückhaltende Farben")
        return LookAnalysis(palette: palette, tonality: tonality, contrast: contrast,
                            temperature: temperature, saturation: saturation)
    }
}
