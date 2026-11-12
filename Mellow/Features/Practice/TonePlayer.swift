import AVFoundation

/// Мягкий тон на смену фазы дыхания: синус, который плавно поднимается на вдохе и опускается на выдохе.
/// Категория .ambient — звук не перебивает музыку и молчит в беззвучном режиме.
final class TonePlayer {
    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private var up: AVAudioPCMBuffer?
    private var down: AVAudioPCMBuffer?
    private var ready = false
    private var failed = false

    private func prepare() {
        guard !ready, !failed else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
            failed = true
            return
        }
        up = TonePlayer.makeTone(format: format, from: 196, to: 262)
        down = TonePlayer.makeTone(format: format, from: 147, to: 110)
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        do {
            try AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
            try AVAudioSession.sharedInstance().setActive(true)
            try engine.start()
            ready = true
        } catch {
            failed = true
        }
    }

    func play(up isUp: Bool) {
        prepare()
        guard ready, let buffer = isUp ? up : down else { return }
        if !engine.isRunning {
            do { try engine.start() } catch { return }
        }
        node.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        if !node.isPlaying { node.play() }
    }

    func stop() {
        guard ready else { return }
        node.stop()
        engine.stop()
        ready = false
        engine.detach(node)
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private static func makeTone(format: AVAudioFormat, from f0: Double, to f1: Double) -> AVAudioPCMBuffer? {
        let rate = format.sampleRate
        let total = Int(rate * 2.1)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(total)),
              let channel = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = AVAudioFrameCount(total)
        var phase = 0.0
        for i in 0..<total {
            let t = Double(i) / rate
            let glide = min(1, t / 1.6)
            let freq = f0 + (f1 - f0) * glide
            let gain: Double
            if t < 0.5 {
                gain = 0.12 * t / 0.5
            } else {
                gain = max(0, 0.12 * (1 - (t - 0.5) / 1.5))
            }
            phase += 2 * Double.pi * freq / rate
            channel[i] = Float(sin(phase) * gain)
        }
        return buffer
    }
}
