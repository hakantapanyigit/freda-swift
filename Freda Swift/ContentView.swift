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
    let waveformPattern: [CGFloat]
}

class AudioPlayer: NSObject, ObservableObject {
    private var audioPlayer: AVPlayer?
    private var playerItem: AVPlayerItem?
    private var timeObserverToken: Any?
    private var playerItemContext = 0
    @Published var isPlaying = false
    @Published var currentSong: Song?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
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
        // Önce mevcut şarkıyı durdur
        stop()
        
        // Aynı şarkıysa sadece oynat/durdur
        if currentSong?.id == song.id {
            if isPlaying {
                isPlaying = false
            } else {
                audioPlayer?.play()
                isPlaying = true
            }
            return
        }
        
        // Yeni şarkı çalınacaksa
        currentSong = song
        duration = song.duration
        currentTime = 0
        
        // Önceki observer'ı temizle
        if let observer = timeObserverToken {
            audioPlayer?.removeTimeObserver(observer)
            timeObserverToken = nil
        }
        
        // Yeni player oluştur
        let playerItem = AVPlayerItem(url: song.audioFileURL)
        audioPlayer = AVPlayer(playerItem: playerItem)
        
        // Yeni time observer ekle
        timeObserverToken = audioPlayer?.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            self?.updateNowPlayingTime(time: time)
        }
        
        // Oynatmaya başla
        DispatchQueue.main.async { [weak self] in
            self?.audioPlayer?.play()
            self?.isPlaying = true
            self?.updateNowPlaying(for: song)
        }
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
        isPlaying = false
        
        // Time observer'ı temizle
        if let observer = timeObserverToken {
            audioPlayer?.removeTimeObserver(observer)
            timeObserverToken = nil
        }
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
    
    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        audioPlayer?.seek(to: cmTime) { [weak self] _ in
            self?.currentTime = time
            if self?.isPlaying == true {
                self?.audioPlayer?.play()
            }
        }
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
            duration: 69,
            description: "After a fckn hard day, you\nneed this.",
            backgroundColor: Color("95957D"),
            waveformPattern: [63, 45, 58, 32, 52, 38, 60, 42, 55, 35, 50, 40, 62, 48, 56, 30]
        ),
        Song(
            title: "Defeat Mental\nBreakdown",
            category: "Focus",
            coverImageURL: URL(string: "https://flappybird.proje.app/upload/album-art-2.png")!,
            audioFileURL: URL(string: "https://flappybird.proje.app/upload/track2.mp3")!,
            duration: 15,
            description: "After a fckn hard day, you\nneed this.",
            backgroundColor: Color("DADADA"),
            waveformPattern: [30, 50, 25, 45, 20, 40, 28, 48, 22, 42, 26, 46, 24, 44, 28, 47]
        ),
        Song(
            title: "777 Spiritual\nGrowth",
            category: "Meditation",
            coverImageURL: URL(string: "https://flappybird.proje.app/upload/album-art-3.png")!,
            audioFileURL: URL(string: "https://flappybird.proje.app/upload/track3.mp3")!,
            duration: 189,
            description: "After a fckn hard day, you\nneed this.",
            backgroundColor: Color("F85C3A"),
            waveformPattern: [40, 60, 35, 55, 45, 63, 38, 58, 42, 62, 36, 56, 44, 61, 39, 59]
        )
    ]

    var body: some View {
        ZStack {
            // Background Color
            Color.interpolate(from: songs[currentSongIndex].backgroundColor, 
                            to: songs[(currentSongIndex + 1) % songs.count].backgroundColor, 
                            progress: -swipeProgress)
                .ignoresSafeArea()
            
            // Main Content
            VStack(spacing: 0) {
                mainContent
                    .padding(.top, 20)
                tabBar
            }
            
            // Featured Card Overlay
            VStack {
                Spacer()
                FeaturedCard(song: songs[1], audioPlayer: audioPlayer)
                    .padding(.horizontal)
                    .padding(.bottom, 100)
            }
            .zIndex(2)
        }
    }
    
    var mainContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            CustomSwiper(songs: songs, currentIndex: $currentSongIndex, swipeProgress: $swipeProgress, audioPlayer: audioPlayer)
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
                WaveformView(audioPlayer: audioPlayer, song: songs[currentSongIndex])
                    .frame(height: 63)
                
                Spacer()
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
    @ObservedObject var audioPlayer: AudioPlayer
    let song: Song
    private let barWidth: CGFloat = 1
    private let barSpacing: CGFloat = 10
    @State private var isDragging = false
    @State private var tempCurrentTime: Double = 0
    
    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            let barCount = Int((availableWidth + barSpacing) / (barWidth + barSpacing))
            
            HStack(spacing: barSpacing) {
                ForEach(0..<barCount, id: \.self) { index in
                    let currentTime = isDragging ? tempCurrentTime : (audioPlayer.currentSong?.id == song.id ? audioPlayer.currentTime : 0)
                    let progress = currentTime / song.duration
                    let isPlayed = Double(index) / Double(barCount) <= progress
                    let height = getBarHeight(at: index, pattern: song.waveformPattern)
                    
                    Rectangle()
                        .fill(Color.white)
                        .opacity(isPlayed ? 1.0 : 0.5)
                        .frame(width: barWidth, height: height)
                        .animation(.easeInOut(duration: 0.3), value: isPlayed)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let progress = min(max(value.location.x / geometry.size.width, 0), 1)
                        tempCurrentTime = song.duration * progress
                    }
                    .onEnded { value in
                        isDragging = false
                        let progress = min(max(value.location.x / geometry.size.width, 0), 1)
                        let seekTime = song.duration * progress
                        audioPlayer.seek(to: seekTime)
                        tempCurrentTime = seekTime
                    }
            )
        }
        .frame(height: 63)
        .padding(.vertical, 20)
    }
    
    private func getBarHeight(at index: Int, pattern: [CGFloat]) -> CGFloat {
        pattern[index % pattern.count]
    }
}

struct FeaturedCard: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayer
    @State private var isExpanded = false
    @State private var dragOffset: CGFloat = 0
    @Namespace private var animation

    var body: some View {
        ZStack {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: isExpanded)
        .onTapGesture {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                isExpanded = true
            }
        }
    }
    
    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Categories
            categoryView(fontSize: 16)
                .padding(.vertical, 8)
            
            // Album Art Container with Background
            ZStack {
                Color.black
                    .matchedGeometryEffect(id: "background", in: animation, properties: .frame)
                    .clipShape(RoundedRectangle(cornerRadius: 32))
                    .ignoresSafeArea()
                
                VStack {
                    albumArtView(height: 300)
                        .padding(.top, 8)
                    
                    titleDescriptionView(titleSize: 32, descriptionSize: 16)
                        .padding(.top, 10)
                    
                    // Waveform
                    WaveformView(audioPlayer: audioPlayer, song: song)
                        .frame(height: 63)
                        .padding(.horizontal)
                        .matchedGeometryEffect(id: "waveform", in: animation)
                    
                    Spacer()
                    
                    // Controls
                    HStack(spacing: 40) {
                        Button(action: {}) {
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "xmark")
                                        .foregroundColor(.white)
                                )
                        }
                        
                        PlayButton(song: song, audioPlayer: audioPlayer)
                            .frame(width: 64, height: 64)
                            .matchedGeometryEffect(id: "playButton", in: animation)
                        
                        Button(action: {}) {
                            Circle()
                                .fill(.white.opacity(0.15))
                                .frame(width: 44, height: 44)
                                .overlay(
                                    Image(systemName: "arrow.clockwise")
                                        .foregroundColor(.white)
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 40)
                    .padding(.top, 20)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .offset(y: dragOffset)
        .opacity(1.0 - (dragOffset / 200.0))
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: dragOffset)
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    dragOffset = max(0, gesture.translation.height)
                }
                .onEnded { gesture in
                    let translation = gesture.translation.height
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                        if translation > 100 {
                            isExpanded = false
                        }
                        dragOffset = 0
                    }
                }
        )
    }
    
    private var collapsedView: some View {
        VStack(spacing: 0) {
            // Categories (collapsed)
            categoryView(fontSize: 12)
                .padding(.bottom, 8)
            
            // Content with background
            ZStack {
                Color.black
                    .matchedGeometryEffect(id: "background", in: animation, properties: .frame)
                
                HStack(spacing: 0) {
                    titleDescriptionView(titleSize: 18, descriptionSize: 12)
                        .padding()
                        .frame(maxWidth: .infinity)
                    
                    albumArtView(height: 144)
                        .frame(width: 164)
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24))
        }
        .frame(height: 200)
    }
    
    private func categoryView(fontSize: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 25) {
                ForEach(["Moments", "Emotional", "Motivation", "Headache"], id: \.self) { category in
                    Text(category)
                        .font(.system(size: fontSize))
                        .foregroundColor(category == "Emotional" ? .black : .black.opacity(0.5))
                        .fontWeight(category == "Emotional" ? .semibold : .light)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .matchedGeometryEffect(id: "category-\(category)", in: animation)
                }
            }
            .padding(.horizontal)
            .padding(.top, fontSize == 16 ? 20 : 8)
        }
    }
    
    private func titleDescriptionView(titleSize: CGFloat, descriptionSize: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Advanced Brain\nFunction")
                .font(.system(size: titleSize, weight: titleSize == 32 ? .bold : .medium))
                .foregroundColor(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .matchedGeometryEffect(id: "title", in: animation)
            
            Text("After a fckn hard day, you\nneed this.")
                .font(.system(size: descriptionSize))
                .foregroundColor(.white.opacity(0.7))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .matchedGeometryEffect(id: "description", in: animation)
            
            if titleSize == 18 {
                Spacer()
                PlayButton(song: song, audioPlayer: audioPlayer)
                    .frame(width: 32, height: 32)
                    .matchedGeometryEffect(id: "playButton", in: animation)
            }
        }
        .padding(.horizontal, titleSize == 32 ? 16 : 0)
    }
    
    private func albumArtView(height: CGFloat) -> some View {
        AsyncImage(url: song.coverImageURL) { image in
            image
                .resizable()
                .aspectRatio(contentMode: .fill)
                .matchedGeometryEffect(id: "albumArt", in: animation, properties: .frame)
        } placeholder: {
            Color.gray
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: height == 300 ? 24 : 16))
    }
}

struct DetailView: View {
    let song: Song
    @ObservedObject var audioPlayer: AudioPlayer
    @Binding var isPresented: Bool
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory = "Emotional"
    
    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Latest")
                        .foregroundColor(.white.opacity(0.5))
                        .font(.system(size: 16))
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 20)
                
                Text(song.title)
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 4)
                
                // Waveform
                WaveformView(audioPlayer: audioPlayer, song: song)
                    .frame(height: 63)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                // Categories
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 25) {
                        ForEach(["Moments", "Emotional", "Motivation", "Headache"], id: \.self) { category in
                            Text(category)
                                .font(.system(size: 16))
                                .foregroundColor(category == selectedCategory ? .white : .white.opacity(0.5))
                                .fontWeight(category == selectedCategory ? .semibold : .light)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 20)
                }
                
                // Album Art
                AsyncImage(url: song.coverImageURL) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray
                }
                .frame(maxWidth: .infinity)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
                .padding(.top, 20)
                
                // Description
                Text(song.description)
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 20)
                
                Spacer()
                
                // Controls
                HStack(spacing: 40) {
                    Button(action: {}) {
                        Image(systemName: "xmark")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                    
                    PlayButton(song: song, audioPlayer: audioPlayer)
                        .frame(width: 64, height: 64)
                    
                    Button(action: {}) {
                        Image(systemName: "arrow.clockwise")
                            .font(.title2)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.bottom, 40)
            }
        }
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
    @State private var feedbackGenerator = UIImpactFeedbackGenerator(style: .soft)
    @State private var lastFeedbackProgress: CGFloat = 0
    @ObservedObject var audioPlayer: AudioPlayer
    
    private let cardWidth: CGFloat = 160
    private let spacing: CGFloat = 45
    private let feedbackThreshold: CGFloat = 0.1
    
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
                let progress = CGFloat(-offset / cardWidth) // -1 ile 0 arası
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
                                
                                // Swipe sırasında hafif feedback
                                let currentProgress = abs(swipeProgress)
                                if currentProgress - lastFeedbackProgress > feedbackThreshold {
                                    feedbackGenerator.prepare()
                                    feedbackGenerator.impactOccurred(intensity: 0.3)
                                    lastFeedbackProgress = currentProgress
                                }
                            }
                        }
                        .onEnded { gesture in
                            isDragging = false
                            let threshold = cardWidth * 0.4
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.8)) {
                                if gesture.translation.width < -threshold {
                                    // Swipe tamamlandığında güçlü feedback
                                    feedbackGenerator.prepare()
                                    feedbackGenerator.impactOccurred(intensity: 0.8)
                                    currentIndex = (currentIndex + 1) % songs.count
                                }
                                offset = 0
                                swipeProgress = 0
                                lastFeedbackProgress = 0
                            }
                        }
                )
        }
        .frame(height: 200)
        .onAppear {
            feedbackGenerator.prepare()
            // İlk şarkıyı çal
            if !songs.isEmpty {
                audioPlayer.play(song: songs[currentIndex])
            }
        }
        .onChange(of: currentIndex) { oldValue, newValue in
            // Güvenli şarkı değişimi
            guard newValue >= 0 && newValue < songs.count else { return }
            DispatchQueue.main.async {
                audioPlayer.play(song: songs[newValue])
            }
        }
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
    init(_ hex: String) {
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
