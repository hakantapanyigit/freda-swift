//
//  ContentView.swift
//  Freda Swift
//
//  Created by Hakan Tapanyiğit on 1.02.2025.
//

import SwiftUI
import AVFoundation
import AVKit
import MediaPlayer
import UIKit

struct Song: Identifiable {
    let id = UUID()
    let title: String
    let category: String
    let coverImageURL: URL
    let audioFileURL: URL
    let duration: TimeInterval
    let description: String
    let backgroundColor: Color
}

class AudioPlayer: NSObject, ObservableObject {
    private var audioPlayer: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var playerItemContext = 0
    @Published var isPlaying = false
    @Published var currentSong: Song?
    
    override init() {
        super.init()
        activateAudioSession()
        setupRemoteTransportControls()
        setupNotifications()
    }
    
    private func activateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)
            print("Successfully activated audio session")
        } catch {
            print("Failed to activate audio session: \(error)")
        }
    }
    
    private func setupNotifications() {
        // Uygulama arka plana geçtiğinde
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance()
        )
        
        // Kulaklık takılıp çıkarıldığında
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleRouteChange),
            name: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance()
        )
    }
    
    @objc private func handleInterruption(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }
        
        switch type {
        case .began:
            // Ses kesildiğinde (örn: telefon geldiğinde)
            audioPlayer?.pause()
            isPlaying = false
        case .ended:
            guard let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt else { return }
            let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
            if options.contains(.shouldResume) {
                // Kesinti bittiğinde devam et
                audioPlayer?.play()
                isPlaying = true
            }
        @unknown default:
            break
        }
    }
    
    @objc private func handleRouteChange(notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }
        
        switch reason {
        case .oldDeviceUnavailable:
            // Kulaklık çıkarıldığında
            audioPlayer?.pause()
            isPlaying = false
        default:
            break
        }
    }
    
    private func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()
        
        commandCenter.playCommand.addTarget { [weak self] _ in
            if let currentSong = self?.currentSong {
                self?.play(song: currentSong)
                return .success
            }
            return .commandFailed
        }
        
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            self?.pause()
            return .success
        }
        
        commandCenter.togglePlayPauseCommand.addTarget { [weak self] _ in
            if let currentSong = self?.currentSong {
                if self?.isPlaying == true {
                    self?.pause()
                } else {
                    self?.play(song: currentSong)
                }
                return .success
            }
            return .commandFailed
        }
    }
    
    func play(song: Song) {
        print("Attempting to play song: \(song.title)")
        
        // Eğer aynı şarkıyı çalıyorsak
        if currentSong?.id == song.id {
            if isPlaying {
                pause()
            } else {
                resumePlayback()
            }
            return
        }
        
        // Önceki oynatıcıyı temizle
        stop()
        
        // Audio session'ı aktifleştir
        activateAudioSession()
        
        // URL'yi kontrol et
        guard let url = URL(string: song.audioFileURL.absoluteString) else {
            print("Invalid URL for song: \(song.title)")
            return
        }
        
        // Asset'i yükle
        let asset = AVAsset(url: url)
        playerItem = AVPlayerItem(asset: asset)
        
        // Player'ı oluştur
        audioPlayer = AVPlayer(playerItem: playerItem)
        audioPlayer?.automaticallyWaitsToMinimizeStalling = false
        
        // Gözlemcileri ekle
        setupPlayerObservers()
        
        // Oynatmaya başla
        resumePlayback()
        currentSong = song
        updateNowPlaying(for: song)
    }
    
    private func setupPlayerObservers() {
        // Periyodik zaman gözlemcisi
        let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserverToken = audioPlayer?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.updateNowPlayingTime(time: time)
        }
        
        // Şarkı bittiğinde
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main) { [weak self] _ in
                self?.handlePlaybackEnded()
            }
        
        // Player durumu değiştiğinde
        playerItem?.addObserver(self,
                              forKeyPath: #keyPath(AVPlayerItem.status),
                              options: [.old, .new],
                              context: &playerItemContext)
    }
    
    override func observeValue(forKeyPath keyPath: String?,
                             of object: Any?,
                             change: [NSKeyValueChangeKey : Any]?,
                             context: UnsafeMutableRawPointer?) {
        guard context == &playerItemContext else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
            return
        }
        
        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }
            
            switch status {
            case .readyToPlay:
                print("Player item is ready to play")
                resumePlayback()
            case .failed:
                print("Player item failed: \(String(describing: playerItem?.error))")
            case .unknown:
                print("Player item status is unknown")
            @unknown default:
                print("Unknown player item status")
            }
        }
    }
    
    private func resumePlayback() {
        audioPlayer?.play()
        isPlaying = true
        print("Playback resumed")
    }
    
    private func handlePlaybackEnded() {
        isPlaying = false
        currentSong = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("Playback ended")
    }
    
    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        print("Playback paused")
    }
    
    func stop() {
        audioPlayer?.pause()
        audioPlayer?.seek(to: .zero)
        removePlayerObservers()
        audioPlayer = nil
        playerItem = nil
        isPlaying = false
        currentSong = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        print("Playback stopped")
    }
    
    private func removePlayerObservers() {
        if let token = timeObserverToken {
            audioPlayer?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        
        playerItem?.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
    
    private func updateNowPlayingTime(time: CMTime) {
        guard let song = currentSong else { return }
        var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = time.seconds
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = song.duration
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = audioPlayer?.rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func updateNowPlaying(for song: Song) {
        var nowPlayingInfo = [String: Any]()
        
        // Şarkı bilgileri
        nowPlayingInfo[MPMediaItemPropertyTitle] = song.title.replacingOccurrences(of: "\n", with: " ")
        nowPlayingInfo[MPMediaItemPropertyArtist] = song.category
        
        // Kapak fotoğrafı
        if let imageURL = URL(string: song.coverImageURL.absoluteString) {
            URLSession.shared.dataTask(with: imageURL) { data, _, _ in
                if let data = data, let image = UIImage(data: data) {
                    let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
                    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
                }
            }.resume()
        }
        
        // Süre bilgileri
        if let player = audioPlayer {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime().seconds
            nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = song.duration
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        }
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
}

struct ContentView: View {
    @StateObject private var audioPlayer = AudioPlayer()
    @State private var selectedTab = 0
    @State private var currentSongIndex = 0
    @State private var dragOffset: CGFloat = 0
    @State private var swipeProgress: CGFloat = 0
    @State private var songs = [
        Song(
            title: "Voyage In\nSpace",
            category: "Emotional",
            coverImageURL: URL(string: "https://flappybird.proje.app/upload/album-art-1.png")!,
            audioFileURL: URL(string: "https://flappybird.proje.app/upload/track1.mp3")!,
            duration: 180,
            description: "After a fckn hard day, you\nneed this.",
            backgroundColor: Color(hex: "95957D")
        ),
        Song(
            title: "Defeat Mental\nBreakdown",
            category: "Focus",
            coverImageURL: URL(string: "https://flappybird.proje.app/upload/album-art-2.png")!,
            audioFileURL: URL(string: "https://flappybird.proje.app/upload/track2.mp3")!,
            duration: 240,
            description: "After a fckn hard day, you\nneed this.",
            backgroundColor: Color(hex: "DADADA")
        ),
        Song(
            title: "777 Spiritual\nGrowth",
            category: "Meditation",
            coverImageURL: URL(string: "https://flappybird.proje.app/upload/album-art-3.png")!,
            audioFileURL: URL(string: "https://flappybird.proje.app/upload/track3.mp3")!,
            duration: 300,
            description: "After a fckn hard day, you\nneed this.",
            backgroundColor: Color(hex: "F85C3A")
        )
    ]

    var body: some View {
        ZStack {
            // Renk interpolasyonu
            let currentColor = songs[currentSongIndex].backgroundColor
            let nextColor = songs[(currentSongIndex + 1) % songs.count].backgroundColor
            Color.interpolate(from: currentColor, to: nextColor, progress: -swipeProgress)
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                mainContent
                    .padding(.top, 40)
                tabBar
            }
        }
    }
    
    var mainContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            CustomSwiper(songs: songs, currentIndex: $currentSongIndex, swipeProgress: $swipeProgress)
                .padding(.horizontal)
            
            VStack(alignment: .leading, spacing: 24) {
                // Latest and Title
                VStack(alignment: .leading, spacing: 4) {
                    Text("Latest")
                        .foregroundColor(.black.opacity(0.5))
                        .font(.system(size: 16, weight: .regular))
                    
                    HStack {
                        Text(songs[currentSongIndex].title)
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundColor(.black)
                        
                        Spacer()
                        
                        PlayButton(song: songs[currentSongIndex], audioPlayer: audioPlayer)
                            .frame(width: 40, height: 40)
                    }
                }
                
                // Waveform
                WaveformView()
                    .frame(height: 63)
                
                // Categories
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 25) {
                        ForEach(["Moments", "Emotional", "Motivation", "Headache"], id: \.self) { category in
                            Text(category)
                                .font(.system(size: 16))
                                .foregroundColor(category == "Emotional" ? .black : .black.opacity(0.5))
                                .fontWeight(category == "Emotional" ? .semibold : .light)
                        }
                    }
                }
                
                // Featured Card
                FeaturedCard(song: songs[1], audioPlayer: audioPlayer)
            }
            .padding(.horizontal)
            
            Spacer()
        }
    }
    
    var tabBar: some View {
        HStack(spacing: 0) {
            TabBarButton(image: "house.fill", title: "Home", isSelected: selectedTab == 0)
                .onTapGesture { selectedTab = 0 }
            
            TabBarButton(image: "waveform", title: "Vibes", isSelected: selectedTab == 1)
                .onTapGesture { selectedTab = 1 }
            
            // Center Play Button
            Button(action: {}) {
                ZStack {
                    Capsule()
                        .fill(.white)
                        .frame(width: 88, height: 44)
                    
                    Image(systemName: "play.fill")
                        .foregroundColor(.black)
                        .font(.title2)
                }
            }
            
            TabBarButton(image: "book.fill", title: "StoryLab", isSelected: selectedTab == 3)
                .onTapGesture { selectedTab = 3 }
            
            TabBarButton(image: "gearshape.fill", title: "Settings", isSelected: selectedTab == 4)
                .onTapGesture { selectedTab = 4 }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 30)
        .background(
            Color.interpolate(from: songs[currentSongIndex].backgroundColor, 
                            to: songs[(currentSongIndex + 1) % songs.count].backgroundColor, 
                            progress: -swipeProgress)
        )
    }
}

struct WaveformView: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<35, id: \.self) { index in
                Rectangle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 1, height: index % 2 == 0 ? 63 : 32)
            }
        }
    }
}

struct FeaturedCard: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayer
    
    var body: some View {
        ZStack {
            Color.black
            
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Advanced Brain\nFunction")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    
                    Text("After a fckn hard day, you\nneed this.")
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.5))
                    
                    Spacer()
                    
                    PlayButton(song: song, audioPlayer: audioPlayer)
                        .frame(width: 32, height: 32)
                }
                .padding()
                
                Spacer()
                
                AsyncImage(url: song.coverImageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray
                }
                .frame(width: 164, height: 144)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .padding(8)
            }
        }
        .frame(height: 160)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

struct TabBarButton: View {
    let image: String
    let title: String
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: image)
                .font(.system(size: 20))
                .foregroundColor(isSelected ? .black : .black.opacity(0.75))
            
            Text(title)
                .font(.system(size: 12))
                .foregroundColor(isSelected ? .black : .black.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }
}

struct PlayButton: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayer
    
    var isPlayingThisSong: Bool {
        audioPlayer.isPlaying && audioPlayer.currentSong?.id == song.id
    }
    
    var body: some View {
        Circle()
            .fill(Color.white)
            .overlay(
                Image(systemName: isPlayingThisSong ? "pause.fill" : "play.fill")
                    .foregroundColor(.black)
            )
            .onTapGesture {
                if isPlayingThisSong {
                    audioPlayer.stop()
                } else {
                    audioPlayer.play(song: song)
                }
            }
    }
}

struct CustomSwiper: View {
    let songs: [Song]
    @Binding var currentIndex: Int
    @State private var offset: CGFloat = 0
    @State private var isDragging = false
    @Binding var swipeProgress: CGFloat
    
    private let cardWidth: CGFloat = 160
    private let spacing: CGFloat = 45
    
    var body: some View {
        ZStack {
            // Arka plandaki kartlar (sabit)
            ForEach((2..<min(4, songs.count)).reversed(), id: \.self) { offset in
                let index = (currentIndex + offset) % songs.count
                cardView(for: songs[index], at: offset)
            }
            
            // İkinci kart (dinamik animasyonlu)
            if songs.count > 1 {
                let nextIndex = (currentIndex + 1) % songs.count
                let progress = -offset / cardWidth // -1 ile 0 arası
                cardView(for: songs[nextIndex], at: 1)
                    .offset(x: spacing * (1 - abs(progress)))
                    .scaleEffect(0.8 + (abs(progress) / 4))
                    .blur(radius: max(0, 2.67 * (1 - abs(progress))))
                    .opacity(0.8 + (abs(progress) * 0.2))
                    .animation(.spring(response: 0.6, dampingFraction: 0.8), value: offset)
            }
            
            // Aktif kart (sürüklenebilir)
            cardView(for: songs[currentIndex], at: 0)
                .offset(x: offset)
                .scaleEffect(1.0 + (offset / cardWidth * 0.2))
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: offset)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            isDragging = true
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                offset = min(0, gesture.translation.width)
                                swipeProgress = offset / cardWidth
                            }
                        }
                        .onEnded { gesture in
                            isDragging = false
                            let threshold = cardWidth * 0.4
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                if gesture.translation.width < -threshold {
                                    currentIndex = (currentIndex + 1) % songs.count
                                }
                                offset = 0
                                swipeProgress = 0
                            }
                        }
                )
        }
        .frame(height: 200)
    }
    
    private func cardView(for song: Song, at position: Int) -> some View {
        AsyncImage(url: song.coverImageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
        } placeholder: {
            Color.black
        }
        .frame(width: cardWidth, height: cardWidth)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white, lineWidth: 2)
        )
        .offset(x: CGFloat(position) * spacing)
        .scaleEffect(1.0 - CGFloat(position) * 0.2)
        .blur(radius: CGFloat(position) * 2.67)
        .opacity(1.0 - CGFloat(position) * 0.2)
        .zIndex(Double(4 - position))
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
    
    static func interpolate(from: Color, to: Color, progress: CGFloat) -> Color {
        let clampedProgress = max(0, min(1, abs(progress)))
        
        // UIColor'a dönüştür
        let fromComponents = from.components()
        let toComponents = to.components()
        
        // Renk bileşenlerini interpolate et
        let r = fromComponents.red + (toComponents.red - fromComponents.red) * clampedProgress
        let g = fromComponents.green + (toComponents.green - fromComponents.green) * clampedProgress
        let b = fromComponents.blue + (toComponents.blue - fromComponents.blue) * clampedProgress
        let a = fromComponents.alpha + (toComponents.alpha - fromComponents.alpha) * clampedProgress
        
        return Color(red: r, green: g, blue: b, opacity: a)
    }
    
    func components() -> (red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        let uiColor = UIColor(self)
        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }
}

#Preview {
    ContentView()
}
