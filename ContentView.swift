let nextIndex = (currentIndex + 1) % songs.count
let progress = -offset / cardWidth // -1 ile 0 arası
cardView(for: songs[nextIndex], at: 1)
    .offset(x: spacing - (abs(progress) * spacing))
    .scaleEffect(0.8 + (abs(progress) * 0.2))
    .blur(radius: max(0, 2.67 * (1 - abs(progress))))
    .opacity(0.8 + (abs(progress) * 0.2)) 