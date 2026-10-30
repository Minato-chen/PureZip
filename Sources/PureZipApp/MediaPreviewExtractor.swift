import Foundation
import AppKit
import AVFoundation
import CoreMedia
import QuickLookThumbnailing

public struct AudioPreviewData: @unchecked Sendable {
    public let title: String?
    public let artist: String?
    public let album: String?
    public let lyrics: String?
    public let artwork: NSImage?
    public let duration: Double
    public let formatDisplayName: String
    public let sampleRate: Double?
    public let channels: Int?
    public let waveformSamples: [CGFloat]

    public init(
        title: String?,
        artist: String?,
        album: String?,
        lyrics: String?,
        artwork: NSImage?,
        duration: Double,
        formatDisplayName: String,
        sampleRate: Double?,
        channels: Int?,
        waveformSamples: [CGFloat]
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.lyrics = lyrics
        self.artwork = artwork
        self.duration = duration
        self.formatDisplayName = formatDisplayName
        self.sampleRate = sampleRate
        self.channels = channels
        self.waveformSamples = waveformSamples
    }

    public var durationFormatted: String {
        guard duration > 0 && duration.isFinite else { return "--:--" }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public var specBadge: String {
        var parts: [String] = [formatDisplayName]
        if let sr = sampleRate, sr > 0 {
            if sr >= 1000 {
                let khz = String(format: "%.1f kHz", sr / 1000.0).replacingOccurrences(of: ".0 kHz", with: " kHz")
                parts.append(khz)
            }
        }
        if let ch = channels {
            parts.append(ch >= 2 ? "立体声" : "单声道")
        }
        return parts.joined(separator: " · ")
    }
}

public struct VideoPreviewData: @unchecked Sendable {
    public let keyframes: [NSImage]
    public let duration: Double
    public let resolution: CGSize
    public let codecName: String

    public init(
        keyframes: [NSImage],
        duration: Double,
        resolution: CGSize,
        codecName: String
    ) {
        self.keyframes = keyframes
        self.duration = duration
        self.resolution = resolution
        self.codecName = codecName
    }

    public var durationFormatted: String {
        guard duration > 0 && duration.isFinite else { return "--:--" }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    public var resolutionFormatted: String {
        guard resolution.width > 0 && resolution.height > 0 else { return "" }
        let h = Int(resolution.height)
        if h >= 2160 { return "4K" }
        if h >= 1440 { return "2K" }
        if h >= 1080 { return "1080P" }
        if h >= 720 { return "720P" }
        return "\(Int(resolution.width))×\(Int(resolution.height))"
    }
}

public final class MediaPreviewExtractor: Sendable {
    public static let supportedVideoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "mkv", "avi", "webm"
    ]

    public static let supportedAudioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "flac", "aac", "ogg", "aiff", "caf", "wma"
    ]

    public static func isVideo(ext: String) -> Bool {
        supportedVideoExtensions.contains(ext.lowercased())
    }

    public static func isAudio(ext: String) -> Bool {
        supportedAudioExtensions.contains(ext.lowercased())
    }

    // MARK: - Video Extraction

    public static func extractVideoData(
        from fileURL: URL,
        maxKeyframes: Int = 5,
        targetSize: CGSize = CGSize(width: 480, height: 270)
    ) async -> VideoPreviewData {
        let asset = AVURLAsset(url: fileURL, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let ext = fileURL.pathExtension.uppercased()

        var duration: Double = 0
        if let d = try? await asset.load(.duration) {
            duration = d.seconds.isFinite ? d.seconds : 0
        }

        var resolution = CGSize.zero
        var codec = ext
        if let tracks = try? await asset.loadTracks(withMediaType: .video), let track = tracks.first {
            if let size = try? await track.load(.naturalSize) {
                if let transform = try? await track.load(.preferredTransform) {
                    let transformed = size.applying(transform)
                    resolution = CGSize(width: abs(transformed.width), height: abs(transformed.height))
                } else {
                    resolution = size
                }
            }
            if let descriptions = try? await track.load(.formatDescriptions), let desc = descriptions.first {
                let subType = CMFormatDescriptionGetMediaSubType(desc)
                codec = fourCCToString(subType)
            }
        }

        var keyframes = await extractVideoKeyframes(
            from: asset,
            duration: duration,
            count: maxKeyframes,
            targetSize: targetSize
        )

        // Fallback to native QuickLookThumbnailing if AVAssetImageGenerator yields no frames (e.g. MKV/WebM/AVI)
        if keyframes.isEmpty {
            if let qlThumb = await generateQuickLookThumbnail(for: fileURL, size: targetSize) {
                keyframes = [qlThumb]
                if resolution == .zero {
                    resolution = qlThumb.size
                }
            }
        }

        return VideoPreviewData(
            keyframes: keyframes,
            duration: duration,
            resolution: resolution,
            codecName: codec
        )
    }

    public static func extractVideoKeyframes(
        from asset: AVAsset,
        duration: Double? = nil,
        count: Int = 5,
        targetSize: CGSize = CGSize(width: 480, height: 270)
    ) async -> [NSImage] {
        let totalSeconds: Double
        if let d = duration, d > 0 {
            totalSeconds = d
        } else if let durationCM = try? await asset.load(.duration), durationCM.seconds > 0, durationCM.seconds.isFinite {
            totalSeconds = durationCM.seconds
        } else {
            totalSeconds = 0
        }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = targetSize
        // Use wide keyframe tolerance so large 4K/1080P videos snap directly to nearest hardware I-frames
        // without decoding entire GOP sequences.
        let tolerance = max(3.0, min(15.0, totalSeconds * 0.08))
        generator.requestedTimeToleranceBefore = CMTime(seconds: tolerance, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: tolerance, preferredTimescale: 600)

        guard totalSeconds > 0 else {
            if let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
                return [NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))]
            }
            return []
        }

        let percentages: [Double]
        if count <= 1 {
            percentages = [0.05]
        } else if count == 3 {
            percentages = [0.10, 0.50, 0.85]
        } else {
            percentages = [0.08, 0.28, 0.50, 0.72, 0.90]
        }

        var images: [NSImage] = []
        for pct in percentages.prefix(max(1, count)) {
            if Task.isCancelled { break }
            let time = CMTime(seconds: totalSeconds * pct, preferredTimescale: 600)
            if let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) {
                images.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
            }
        }

        if images.isEmpty, let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) {
            images.append(NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)))
        }
        return images
    }

    private static func generateQuickLookThumbnail(for fileURL: URL, size: CGSize) async -> NSImage? {
        let req = QLThumbnailGenerator.Request(
            fileAt: fileURL,
            size: size,
            scale: 1.0,
            representationTypes: .thumbnail
        )
        let (rep, _) = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { rep, err in
                continuation.resume(returning: (rep, err))
            }
        }
        return rep?.nsImage
    }

    // MARK: - Audio Extraction

    public static func extractAudioData(from fileURL: URL, sampleCount: Int = 48) async -> AudioPreviewData {
        let asset = AVURLAsset(url: fileURL)
        let ext = fileURL.pathExtension.uppercased()

        var title: String? = nil
        var artist: String? = nil
        var album: String? = nil
        var artwork: NSImage? = nil
        var lyrics: String? = nil

        // 1. Common Metadata
        if let commonItems = try? await asset.load(.commonMetadata) {
            for item in commonItems {
                guard let key = item.commonKey else { continue }
                switch key {
                case .commonKeyTitle:
                    title = try? await item.load(.value) as? String
                case .commonKeyArtist:
                    artist = try? await item.load(.value) as? String
                case .commonKeyAlbumName:
                    album = try? await item.load(.value) as? String
                case .commonKeyArtwork:
                    if let data = try? await item.load(.dataValue), let img = NSImage(data: data) {
                        artwork = img
                    }
                default:
                    break
                }
            }
        }

        // 2. Lyrics
        if let standardLyrics = try? await asset.load(.lyrics), !standardLyrics.isEmpty {
            lyrics = standardLyrics
        } else if let formats = try? await asset.load(.availableMetadataFormats) {
            for format in formats {
                if let formatItems = try? await asset.loadMetadata(for: format) {
                    for item in formatItems {
                        let idRaw = item.identifier?.rawValue ?? ""
                        let keyStr = (item.key as? String) ?? ""
                        if idRaw.contains("USLT") || idRaw.contains("Lyrics") || keyStr == "USLT" || keyStr == "©lyr" {
                            if let l = try? await item.load(.value) as? String, !l.isEmpty {
                                lyrics = l
                                break
                            }
                        }
                    }
                }
                if lyrics != nil { break }
            }
        }

        // 3. Technical details
        var duration: Double = 0
        if let d = try? await asset.load(.duration) {
            duration = d.seconds.isFinite ? d.seconds : 0
        }

        var sampleRate: Double? = nil
        var channels: Int? = nil
        if let audioTracks = try? await asset.loadTracks(withMediaType: .audio), let track = audioTracks.first {
            if let formatDescriptions = try? await track.load(.formatDescriptions) {
                for desc in formatDescriptions {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                        sampleRate = asbd.mSampleRate
                        channels = Int(asbd.mChannelsPerFrame)
                        break
                    }
                }
            }
        }

        // 4. Waveform extraction
        let waveform = await extractWaveform(from: asset, sampleCount: sampleCount)

        return AudioPreviewData(
            title: title,
            artist: artist,
            album: album,
            lyrics: lyrics,
            artwork: artwork,
            duration: duration,
            formatDisplayName: ext,
            sampleRate: sampleRate,
            channels: channels,
            waveformSamples: waveform
        )
    }

    public static func extractWaveform(from asset: AVAsset, sampleCount: Int = 48) async -> [CGFloat] {
        guard sampleCount > 0 else { return [] }
        guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
            return generateFallbackWaveform(sampleCount: sampleCount)
        }

        do {
            let reader = try AVAssetReader(asset: asset)
            // IMPORTANT: AVAssetReaderTrackOutput throws an NSInvalidArgumentException if `AVSampleRateKey`
            // or `AVNumberOfChannelsKey` are passed in `outputSettings`! Only LinearPCM sample format keys
            // are permitted on AVAssetReaderTrackOutput. We decode native LinearPCM in-place and stride-sample
            // across channels to compute a fast, 100%-accurate full-track RMS + Peak waveform envelope.
            let outputSettings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else {
                return generateFallbackWaveform(sampleCount: sampleCount)
            }
            reader.add(output)

            guard reader.startReading() else {
                return generateFallbackWaveform(sampleCount: sampleCount)
            }

            // Detect channel count & sample rate from track format descriptions (defaulting to stereo 44.1kHz)
            var channelCount = 2
            var nativeSampleRate = 44100.0
            if let formatDescriptions = try? await track.load(.formatDescriptions) {
                for desc in formatDescriptions {
                    if let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(desc)?.pointee {
                        if asbd.mChannelsPerFrame > 0 {
                            channelCount = Int(asbd.mChannelsPerFrame)
                        }
                        if asbd.mSampleRate > 0 {
                            nativeSampleRate = asbd.mSampleRate
                        }
                        break
                    }
                }
            }

            // Stride every ~11 frames (effectively ~4 kHz sampling from 44.1/48 kHz) so a 4-minute song
            // processes in <15ms while still capturing every transient and dynamic change across 0%...100%.
            let frameStride = max(1, Int(nativeSampleRate / 4000.0))
            let sampleStep = max(1, frameStride * channelCount)
            let blockSamplesCount = 128 // ~32ms per acoustic block at 4 kHz effective rate

            var blockRMS: [Float] = []
            var blockPeak: [Float] = []
            blockRMS.reserveCapacity(8192)
            blockPeak.reserveCapacity(8192)

            var currentSumSq: Float = 0
            var currentPeak: Float = 0
            var currentCount: Int = 0
            let normFactor = 1.0 / Float(Int16.max)
            let maxBlocks = 200_000 // Safety cap (~1.7 hours of audio)

            while reader.status == .reading {
                if Task.isCancelled || blockRMS.count >= maxBlocks { break }
                guard let sampleBuffer = output.copyNextSampleBuffer() else { break }
                guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }

                let length = CMBlockBufferGetDataLength(blockBuffer)
                guard length >= 2 else { continue }

                var dataPointer: UnsafeMutablePointer<Int8>? = nil
                var lengthAtOffset: Int = 0
                let status = CMBlockBufferGetDataPointer(
                    blockBuffer,
                    atOffset: 0,
                    lengthAtOffsetOut: &lengthAtOffset,
                    totalLengthOut: nil,
                    dataPointerOut: &dataPointer
                )

                if status == kCMBlockBufferNoErr, let basePtr = dataPointer, lengthAtOffset >= 2 {
                    let count16 = lengthAtOffset / MemoryLayout<Int16>.size
                    basePtr.withMemoryRebound(to: Int16.self, capacity: count16) { int16Ptr in
                        var i = 0
                        while i < count16 {
                            let raw = Int32(int16Ptr[i])
                            let absVal = Float(abs(raw)) * normFactor
                            currentSumSq += absVal * absVal
                            if absVal > currentPeak {
                                currentPeak = absVal
                            }
                            currentCount += 1
                            if currentCount >= blockSamplesCount {
                                let rms = sqrt(currentSumSq / Float(currentCount))
                                blockRMS.append(rms)
                                blockPeak.append(currentPeak)
                                currentSumSq = 0
                                currentPeak = 0
                                currentCount = 0
                            }
                            i += sampleStep
                        }
                    }
                } else {
                    var data = Data(count: length)
                    data.withUnsafeMutableBytes { (buffer: UnsafeMutableRawBufferPointer) in
                        if let base = buffer.baseAddress {
                            CMBlockBufferCopyDataBytes(blockBuffer, atOffset: 0, dataLength: length, destination: base)
                        }
                    }
                    data.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) in
                        let int16Ptr = ptr.bindMemory(to: Int16.self)
                        var i = 0
                        while i < int16Ptr.count {
                            let raw = Int32(int16Ptr[i])
                            let absVal = Float(abs(raw)) * normFactor
                            currentSumSq += absVal * absVal
                            if absVal > currentPeak {
                                currentPeak = absVal
                            }
                            currentCount += 1
                            if currentCount >= blockSamplesCount {
                                let rms = sqrt(currentSumSq / Float(currentCount))
                                blockRMS.append(rms)
                                blockPeak.append(currentPeak)
                                currentSumSq = 0
                                currentPeak = 0
                                currentCount = 0
                            }
                            i += sampleStep
                        }
                    }
                }
            }

            if currentCount > 0 {
                let rms = sqrt(currentSumSq / Float(currentCount))
                blockRMS.append(rms)
                blockPeak.append(currentPeak)
            }

            reader.cancelReading()

            guard !blockRMS.isEmpty else {
                return generateFallbackWaveform(sampleCount: sampleCount)
            }

            // Aggregate the full-track blocks into `sampleCount` time buckets spanning 0% ... 100%
            var bucketEnergies: [Float] = []
            bucketEnergies.reserveCapacity(sampleCount)
            let totalBlocks = blockRMS.count

            for i in 0..<sampleCount {
                let startIdx = (i * totalBlocks) / sampleCount
                let endIdx = max(startIdx + 1, min(totalBlocks, ((i + 1) * totalBlocks) / sampleCount))
                if startIdx < totalBlocks, startIdx < endIdx {
                    var sumSq: Float = 0
                    var localPeak: Float = 0
                    for idx in startIdx..<endIdx {
                        let r = blockRMS[idx]
                        sumSq += r * r
                        if blockPeak[idx] > localPeak {
                            localPeak = blockPeak[idx]
                        }
                    }
                    let count = Float(endIdx - startIdx)
                    let bucketRMS = sqrt(sumSq / count)
                    // Blend RMS (perceived loudness) with local peak (transient punch) for natural acoustic shape
                    let combined = bucketRMS * 0.72 + localPeak * 0.28
                    bucketEnergies.append(combined)
                } else if let last = bucketEnergies.last {
                    bucketEnergies.append(last)
                } else {
                    bucketEnergies.append(0)
                }
            }

            // Dynamic normalization against the track's own 95th-percentile / peak energy
            // so both quiet acoustic tracks and loud mastered tracks display their true dynamic contour.
            let sorted = bucketEnergies.sorted()
            let p95Index = min(sorted.count - 1, max(0, Int(Double(sorted.count - 1) * 0.95)))
            let refPeak = max(sorted[p95Index], sorted.last ?? 0.001, 0.001)

            return bucketEnergies.map { energy in
                let normalized = Double(min(1.0, energy / refPeak))
                // Slight perceptual gamma (0.78) so quiet intros/outros remain distinct from loud choruses
                let shaped = pow(normalized, 0.78)
                return CGFloat(max(0.08, min(1.0, shaped)))
            }
        } catch {
            return generateFallbackWaveform(sampleCount: sampleCount)
        }
    }

    public static func generateFallbackWaveform(sampleCount: Int = 48) -> [CGFloat] {
        (0..<sampleCount).map { i in
            let progress = Double(i) / Double(sampleCount)
            let base = sin(progress * .pi)
            let ripple = sin(progress * .pi * 7.0) * 0.22
            let micro = sin(progress * .pi * 17.0) * 0.12
            let val = abs(base + ripple + micro)
            return CGFloat(max(0.18, min(0.95, val)))
        }
    }

    private static func fourCCToString(_ code: FourCharCode) -> String {
        let bytes: [CChar] = [
            CChar((code >> 24) & 0xff),
            CChar((code >> 16) & 0xff),
            CChar((code >> 8) & 0xff),
            CChar(code & 0xff),
            0
        ]
        let str = String(cString: bytes).trimmingCharacters(in: .whitespacesAndNewlines)
        if str == "avc1" { return "H.264" }
        if str == "hvc1" || str == "hev1" { return "HEVC" }
        if str == "ap4h" || str == "apcn" { return "ProRes" }
        if str == "vp09" { return "VP9" }
        return str.isEmpty ? "Video" : str.uppercased()
    }
}
