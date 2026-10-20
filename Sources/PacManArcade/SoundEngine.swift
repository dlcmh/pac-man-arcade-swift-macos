import AVFoundation
import Foundation

enum SoundEffect {
    case chompHigh
    case chompLow
    case powerPellet
    case ghostEaten(combo: Int)
    case fruit
    case extraLife
    case death
    case start
    case levelComplete
    case gameOver
}

/// Tiny procedural chiptune engine. All effects are synthesized at launch,
/// so the game has no external audio assets.
final class SoundEngine {
    private let engine = AVAudioEngine()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var nextPlayer = 0
    private var wakaHigh = true
    private var audioAvailable = false

    var isMuted = false {
        didSet {
            engine.mainMixerNode.outputVolume = isMuted ? 0 : 0.62
        }
    }

    init() {
        engine.mainMixerNode.outputVolume = 0.62

        for _ in 0..<6 {
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            players.append(player)
        }

        buildBuffers()

        do {
            engine.prepare()
            try engine.start()
            audioAvailable = true
            for player in players {
                player.play()
            }
        } catch {
            audioAvailable = false
        }
    }

    func play(_ effect: SoundEffect) {
        guard audioAvailable, !isMuted else { return }

        let key: String
        switch effect {
        case .chompHigh:
            key = "chompHigh"
        case .chompLow:
            key = "chompLow"
        case .powerPellet:
            key = "power"
        case .ghostEaten(let combo):
            key = "ghost\(min(max(combo, 0), 3))"
        case .fruit:
            key = "fruit"
        case .extraLife:
            key = "extraLife"
        case .death:
            key = "death"
        case .start:
            key = "start"
        case .levelComplete:
            key = "levelComplete"
        case .gameOver:
            key = "gameOver"
        }

        guard let buffer = buffers[key] else { return }
        let player = players[nextPlayer]
        nextPlayer = (nextPlayer + 1) % players.count
        player.stop()
        player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        player.play()
    }

    func playChomp() {
        play(wakaHigh ? .chompHigh : .chompLow)
        wakaHigh.toggle()
    }

    func stopAll() {
        for player in players {
            player.stop()
        }
    }

    // MARK: - Synthesis

    private func buildBuffers() {
        buffers["chompHigh"] = makeBuffer(duration: 0.075) { t in
            let progress = min(1, t / 0.075)
            let frequency = 510.0 - 190.0 * progress
            return self.square(time: t, frequency: frequency) * Float(0.24 * (1 - progress))
        }

        buffers["chompLow"] = makeBuffer(duration: 0.075) { t in
            let progress = min(1, t / 0.075)
            let frequency = 420.0 - 150.0 * progress
            return self.square(time: t, frequency: frequency) * Float(0.22 * (1 - progress))
        }

        buffers["power"] = makeBuffer(duration: 0.38) { t in
            let progress = min(1, t / 0.38)
            let notes = [392.0, 523.25, 659.25, 783.99]
            let noteIndex = min(Int(progress * Double(notes.count)), notes.count - 1)
            let frequency = notes[noteIndex]
            let amplitude = 0.18 * (1 - progress * 0.55)
            return self.square(time: t, frequency: frequency) * Float(amplitude)
        }

        for (index, frequency) in [523.25, 659.25, 783.99, 1046.5].enumerated() {
            buffers["ghost\(index)"] = makeBuffer(duration: 0.24) { t in
                let progress = min(1, t / 0.24)
                let warble = sin(t * 2 * .pi * 18) * 24
                let amplitude = 0.2 * (1 - progress)
                return self.square(time: t, frequency: frequency + warble) * Float(amplitude)
            }
        }

        buffers["fruit"] = makeBuffer(duration: 0.32) { t in
            let progress = min(1, t / 0.32)
            let frequency: Double
            if progress < 0.33 {
                frequency = 659.25
            } else if progress < 0.66 {
                frequency = 783.99
            } else {
                frequency = 1046.5
            }
            return self.triangle(time: t, frequency: frequency) * Float(0.24 * (1 - progress * 0.7))
        }

        buffers["extraLife"] = makeBuffer(duration: 0.65) { t in
            let progress = min(1, t / 0.65)
            let noteLength = 0.108
            let noteIndex = min(Int(t / noteLength), 5)
            let notes = [783.99, 987.77, 1174.66, 1567.98, 1318.51, 1567.98]
            let noteProgress = (t - Double(noteIndex) * noteLength) / noteLength
            let envelope = max(0, 1 - noteProgress)
            return self.square(time: t, frequency: notes[noteIndex])
                * Float(0.18 * envelope * (1 - progress * 0.4))
        }

        buffers["death"] = makeBuffer(duration: 1.2) { t in
            let progress = min(1, t / 1.2)
            let frequency = 700.0 * pow(0.11, progress) + sin(t * 2 * .pi * 9) * 9
            let wobble = sin(t * 2 * .pi * 23) * 0.08
            return self.square(time: t, frequency: frequency + wobble)
                * Float(0.22 * (1 - progress))
        }

        buffers["start"] = makeBuffer(duration: 1.05) { t in
            let noteLength = 0.13
            let notes = [261.63, 329.63, 392.0, 523.25, 392.0, 523.25, 659.25, 783.99]
            let noteIndex = min(Int(t / noteLength), notes.count - 1)
            let progress = min(1, t / 1.05)
            let noteProgress = (t - Double(noteIndex) * noteLength) / noteLength
            let envelope = max(0, 1 - noteProgress * 0.85)
            return self.square(time: t, frequency: notes[noteIndex])
                * Float(0.16 * envelope * (1 - progress * 0.4))
        }

        buffers["levelComplete"] = makeBuffer(duration: 0.8) { t in
            let notes = [523.25, 659.25, 783.99, 1046.5, 1318.51]
            let noteLength = 0.15
            let noteIndex = min(Int(t / noteLength), notes.count - 1)
            let progress = min(1, t / 0.8)
            let noteProgress = (t - Double(noteIndex) * noteLength) / noteLength
            let envelope = max(0, 1 - noteProgress)
            return self.triangle(time: t, frequency: notes[noteIndex])
                * Float(0.22 * envelope * (1 - progress * 0.3))
        }

        buffers["gameOver"] = makeBuffer(duration: 0.9) { t in
            let progress = min(1, t / 0.9)
            let frequency = 400.0 * pow(0.25, progress)
            return self.square(time: t, frequency: frequency) * Float(0.18 * (1 - progress))
        }
    }

    private func makeBuffer(duration: Double, generator: (Double) -> Float) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
            let channelData = buffer.floatChannelData
        else {
            return nil
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            channelData[0][frame] = generator(Double(frame) / sampleRate)
        }
        return buffer
    }

    private func square(time: Double, frequency: Double) -> Float {
        let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
        return phase < 0.5 ? 1 : -1
    }

    private func triangle(time: Double, frequency: Double) -> Float {
        let phase = (time * frequency).truncatingRemainder(dividingBy: 1)
        return Float(4 * abs(phase - 0.5) - 1)
    }
}
