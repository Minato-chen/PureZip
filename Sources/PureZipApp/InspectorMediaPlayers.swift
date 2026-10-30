import SwiftUI
import AppKit
import AVFoundation
import AVKit
import ArchiveCore

// MARK: - Reusable Waveform Bars Component

public struct AcousticWaveformBarsView: View {
    public let samples: [CGFloat]
    public let progress: Double // 0.0 to 1.0
    public let barHeight: CGFloat
    public let gradientColors: [Color]
    public var onSeek: ((Double) -> Void)? = nil

    public init(
        samples: [CGFloat],
        progress: Double = 0.0,
        barHeight: CGFloat = 40,
        gradientColors: [Color] = [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.03, green: 0.40, blue: 0.90)],
        onSeek: ((Double) -> Void)? = nil
    ) {
        self.samples = samples.isEmpty ? MediaPreviewExtractor.generateFallbackWaveform(sampleCount: 48) : samples
        self.progress = progress
        self.barHeight = barHeight
        self.gradientColors = gradientColors
        self.onSeek = onSeek
    }

    public var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2.5) {
                ForEach(Array(samples.enumerated()), id: \.offset) { idx, amp in
                    let barProgress = Double(idx) / Double(samples.count)
                    let isPlayed = barProgress <= progress
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(
                            isPlayed ?
                                LinearGradient(colors: gradientColors, startPoint: .bottom, endPoint: .top) :
                                LinearGradient(colors: [Color.primary.opacity(0.28), Color.primary.opacity(0.12)], startPoint: .bottom, endPoint: .top)
                        )
                        .frame(height: max(4, barHeight * amp))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: barHeight, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let w = geo.size.width
                        guard w > 0 else { return }
                        let pct = max(0.0, min(1.0, Double(value.location.x / w)))
                        onSeek?(pct)
                    }
            )
        }
        .frame(height: barHeight)
    }
}

// MARK: - Native Video Player Surface for AppKit

struct NativeVideoPlayerView: NSViewRepresentable {
    let player: AVPlayer

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player
        view.controlsStyle = .none
        view.videoGravity = .resizeAspect
        view.showsFullScreenToggleButton = false
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        if nsView.player !== player {
            nsView.player = player
        }
    }
}

// MARK: - Inspector Video Player View

public struct InspectorVideoPlayerView: View {
    let url: URL
    let metadata: VideoPreviewData
    let entryName: String

    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var isMuted: Bool = true
    @State private var currentTime: Double = 0
    @State private var timeObserverToken: Any? = nil
    @State private var isHovering: Bool = false

    public init(url: URL, metadata: VideoPreviewData, entryName: String) {
        self.url = url
        self.metadata = metadata
        self.entryName = entryName
    }

    public var body: some View {
        ZStack {
            Color.black

            if let firstFrame = metadata.keyframes.first {
                Image(nsImage: firstFrame)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            if let p = player {
                NativeVideoPlayerView(player: p)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            // Center large Play overlay if paused
            if !isPlaying {
                Button {
                    togglePlay()
                } label: {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 44, weight: .light))
                        .foregroundStyle(.white.opacity(0.85))
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                }
                .buttonStyle(.plain)
            }

            // Bottom Player Floating Controls Bar
            VStack {
                Spacer()

                HStack(spacing: 10) {
                    // Play / Pause
                    Button {
                        togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)

                    // Scrubber Slider
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { newVal in
                                currentTime = newVal
                                seek(to: newVal)
                            }
                        ),
                        in: 0...max(0.1, metadata.duration)
                    )
                    .tint(Color(red: 0.05, green: 0.48, blue: 0.98))

                    // Time display
                    Text("\(formatTime(currentTime)) / \(metadata.durationFormatted)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)

                    // Mute / Unmute
                    Button {
                        toggleMute()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(isMuted ? Color.orange : Color.white)
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help(isMuted ? "已静音（点击开启声音）" : "声音已开启")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.70))
                .cornerRadius(8)
                .padding(8)
            }
        }
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: url) {
            teardownPlayer()
            setupPlayer()
        }
    }

    private func setupPlayer() {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        // Limit decoding resolution to compact Inspector card size so 4K/8K videos decode instantly with low memory
        item.preferredMaximumResolution = CGSize(width: 640, height: 360)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        let defaultMute = PureZipPreferences.shared.deskMediaAlwaysMute
        p.isMuted = defaultMute
        self.isMuted = defaultMute
        self.player = p

        let interval = CMTime(seconds: 0.2, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard let p = p else { return }
            self.currentTime = time.seconds
            if time.seconds >= (self.metadata.duration - 0.2) && self.metadata.duration > 0 {
                // Loop video
                p.seek(to: .zero)
                p.play()
            }
        }

        if PureZipPreferences.shared.deskVideoAutoPlay {
            p.play()
            self.isPlaying = true
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    private func togglePlay() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    private func toggleMute() {
        guard let p = player else { return }
        isMuted.toggle()
        p.isMuted = isMuted
    }

    private func seek(to seconds: Double) {
        guard let p = player else { return }
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.5, preferredTimescale: 600)
        p.seek(to: target, toleranceBefore: tolerance, toleranceAfter: tolerance)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

// MARK: - Inspector Audio Player View (Waveform Deck when no artwork)

public struct InspectorAudioPlayerView: View {
    let url: URL
    let metadata: AudioPreviewData
    let entryName: String

    @State private var player: AVPlayer? = nil
    @State private var isPlaying: Bool = false
    @State private var isMuted: Bool = true
    @State private var currentTime: Double = 0
    @State private var timeObserverToken: Any? = nil
    @State private var showLyrics: Bool = false
    @Environment(\.colorScheme) private var colorScheme

    public init(url: URL, metadata: AudioPreviewData, entryName: String) {
        self.url = url
        self.metadata = metadata
        self.entryName = entryName
    }

    private var progress: Double {
        guard metadata.duration > 0 else { return 0 }
        return max(0.0, min(1.0, currentTime / metadata.duration))
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // MARK: Top Deck (Cover Artwork OR Acoustic Waveform Deck)
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(colorScheme == .dark ? Color(white: 0.12) : Color(white: 0.94))
                    .shadow(color: Color.black.opacity(0.12), radius: 6, y: 3)

                if let artwork = metadata.artwork {
                    // Has Cover Artwork: Display album card + interactive real waveform
                    VStack(spacing: 10) {
                        Image(nsImage: artwork)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 126)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .shadow(color: Color.black.opacity(0.20), radius: 6, y: 2)

                        AcousticWaveformBarsView(
                            samples: metadata.waveformSamples,
                            progress: progress,
                            barHeight: 36,
                            gradientColors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.02, green: 0.38, blue: 0.88)],
                            onSeek: { pct in
                                let targetSeconds = pct * metadata.duration
                                seek(to: targetSeconds)
                            }
                        )
                        .padding(.horizontal, 14)
                    }
                    .padding(.vertical, 10)
                } else {
                    // Acoustic Waveform Deck
                    VStack(spacing: 12) {
                        HStack {
                            Image(systemName: "waveform.badge.magnifyingglass")
                                .font(.system(size: 15))
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                            Text("声学波形控制台")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(metadata.specBadge)
                                .font(.system(size: 10, weight: .semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(Color(red: 0.05, green: 0.48, blue: 0.98).opacity(0.18))
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                                .clipShape(Capsule())
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 14)

                        Spacer()

                        // Full interactive Waveform with click/drag seek
                        AcousticWaveformBarsView(
                            samples: metadata.waveformSamples,
                            progress: progress,
                            barHeight: 70,
                            gradientColors: [Color(red: 0.22, green: 0.62, blue: 1.0), Color(red: 0.02, green: 0.38, blue: 0.88)],
                            onSeek: { pct in
                                let targetSeconds = pct * metadata.duration
                                seek(to: targetSeconds)
                            }
                        )
                        .padding(.horizontal, 16)

                        Spacer()

                        Text("点击或拖动波形以调整播放进度")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(NSColor.tertiaryLabelColor))
                            .padding(.bottom, 12)
                    }
                }
            }
            .frame(height: 210)
            .padding(.horizontal, 20)

            // MARK: Track Title & Artist
            VStack(alignment: .leading, spacing: 3) {
                Text(metadata.title ?? entryName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                if let artist = metadata.artist {
                    Text(artist + (metadata.album.map { " · \($0)" } ?? ""))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 20)

            // MARK: Playback Controller Row (Play/Pause, Slider, Mute, Time)
            VStack(spacing: 6) {
                HStack(spacing: 10) {
                    // Play / Pause Circular Button
                    Button {
                        togglePlay()
                    } label: {
                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                    }
                    .buttonStyle(.plain)

                    // Scrubber Slider
                    Slider(
                        value: Binding(
                            get: { currentTime },
                            set: { newVal in
                                currentTime = newVal
                                seek(to: newVal)
                            }
                        ),
                        in: 0...max(0.1, metadata.duration)
                    )
                    .tint(Color(red: 0.05, green: 0.48, blue: 0.98))

                    // Mute / Unmute
                    Button {
                        toggleMute()
                    } label: {
                        Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isMuted ? Color.orange : Color.secondary)
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.plain)
                    .help(isMuted ? "默认静音（点击开启声音）" : "声音已开启")
                }

                HStack {
                    Text(formatTime(currentTime))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(metadata.durationFormatted)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 20)

            // MARK: Expandable Embedded Lyrics Section
            if let lyrics = metadata.lyrics, !lyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showLyrics.toggle()
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: showLyrics ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Color(red: 0.05, green: 0.48, blue: 0.98))
                            Text("内嵌歌词")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.primary)
                            Spacer()
                            Text(showLyrics ? "收起" : "展开")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if showLyrics {
                        ScrollView {
                            Text(lyrics)
                                .font(.system(size: 11.5, weight: .regular))
                                .lineSpacing(4)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 140)
                        .background(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.92))
                        .cornerRadius(8)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            teardownPlayer()
        }
        .onChange(of: url) {
            teardownPlayer()
            setupPlayer()
        }
    }

    private func setupPlayer() {
        let asset = AVURLAsset(url: url, options: [AVURLAssetPreferPreciseDurationAndTimingKey: false])
        let item = AVPlayerItem(asset: asset)
        let p = AVPlayer(playerItem: item)
        p.automaticallyWaitsToMinimizeStalling = false
        let defaultMute = PureZipPreferences.shared.deskMediaAlwaysMute
        p.isMuted = defaultMute
        self.isMuted = defaultMute
        self.player = p

        let interval = CMTime(seconds: 0.15, preferredTimescale: 600)
        timeObserverToken = p.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak p] time in
            guard let p = p else { return }
            self.currentTime = time.seconds
            if time.seconds >= (self.metadata.duration - 0.2) && self.metadata.duration > 0 {
                p.seek(to: .zero)
                p.pause()
                self.isPlaying = false
            }
        }
    }

    private func teardownPlayer() {
        if let token = timeObserverToken, let p = player {
            p.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
    }

    private func togglePlay() {
        guard let p = player else { return }
        if isPlaying {
            p.pause()
            isPlaying = false
        } else {
            p.play()
            isPlaying = true
        }
    }

    private func toggleMute() {
        guard let p = player else { return }
        isMuted.toggle()
        p.isMuted = isMuted
    }

    private func seek(to seconds: Double) {
        guard let p = player else { return }
        currentTime = seconds
        let target = CMTime(seconds: seconds, preferredTimescale: 600)
        p.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}
