// EngineSound.swift
// ModestoGridPrix
//
// Real-time synthesized engine note — no audio assets needed. An AVAudioEngine
// source node generates a buzzy waveform (stacked sawtooth-ish harmonics) whose
// pitch and loudness track the car's "RPM". The 3D race feeds it the player's
// speed/throttle each frame and the note revs up and down with the car.
//
// The audio render block runs on a realtime thread, so we only exchange plain
// atomics-ish values (Float) with it — set target rpm/throttle from the game
// thread, smooth toward them inside the render block.

import AVFoundation

final class EngineSound {

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    /// Hardware sample rate, read from the active session (often 48000 on iPhone,
    /// not 44100). Using the real rate avoids a silent format mismatch.
    private var sampleRate: Double = 48_000

    // Shared control values (written from game thread, read in render block).
    // Simple Float stores; races are benign (slightly stale value for one block).
    private var targetRPM: Float = 0.08   // 0 = idle-ish, 1 = redline
    private var targetLoad: Float = 0.0   // throttle 0..1 (adds grit/volume)

    // Render-thread state.
    private var phase: Float = 0
    private var pulsePhase: Float = 0
    private var smoothedRPM: Float = 0.08
    private var smoothedLoad: Float = 0

    private var started = false

    init() { }

    private func build() {
        // Match the engine's actual output format (hardware sample rate) so the
        // source node isn't silently rejected by a rate/format mismatch.
        let outFormat = engine.outputNode.outputFormat(forBus: 0)
        if outFormat.sampleRate > 0 { sampleRate = outFormat.sampleRate }
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        source = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self = self else { return noErr }
            let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let sr = Float(self.sampleRate)

            let twoPi = Float.pi * 2
            for frame in 0..<Int(frameCount) {
                // Smooth toward targets so revs glide, not jump.
                self.smoothedRPM += (self.targetRPM - self.smoothedRPM) * 0.0008
                self.smoothedLoad += (self.targetLoad - self.smoothedLoad) * 0.0008

                // Base engine frequency scales with rpm. Keep it low and warm so
                // it rumbles rather than whines: idle ~42 Hz up to ~210 Hz.
                let baseFreq = 42.0 + self.smoothedRPM * 168.0

                self.phase += baseFreq / sr
                if self.phase >= 1 { self.phase -= 1 }
                let p = self.phase

                // Rounded tone: strong fundamental + a couple of low harmonics
                // only. No raw sawtooth / high rasp (that was the electronic buzz).
                var tone: Float = 0
                tone += sinf(twoPi * p) * 0.60
                tone += sinf(twoPi * 2 * p) * 0.30
                tone += sinf(twoPi * 3 * p) * 0.12
                // A soft, load-dependent 1.5x harmonic adds throaty "growl" under
                // throttle without the harsh high end.
                tone += sinf(twoPi * 1.5 * p) * (0.06 + self.smoothedLoad * 0.14)

                // Cylinder-firing amplitude pulse: a slow tremolo (a few Hz,
                // rising with rpm) that makes it read as a mechanical rumble.
                self.pulsePhase += (6.0 + self.smoothedRPM * 26.0) / sr
                if self.pulsePhase >= 1 { self.pulsePhase -= 1 }
                let pulse = 0.82 + 0.18 * sinf(twoPi * self.pulsePhase)

                // Overall gain: clearly audible at idle, fuller under power.
                let gain = 0.18 + self.smoothedLoad * 0.16 + self.smoothedRPM * 0.08
                var sample = tone * pulse * gain
                // Gentle soft clip for warmth, not distortion.
                sample = tanhf(sample * 1.1)

                for buffer in abl {
                    let buf = UnsafeMutableBufferPointer<Float>(
                        start: buffer.mData?.assumingMemoryBound(to: Float.self),
                        count: Int(frameCount))
                    buf[frame] = sample
                }
            }
            return noErr
        }

        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
    }

    /// Begin playback. Safe to call once the race view appears.
    private var built = false

    func start() {
        guard !started else { return }
        // Session FIRST, so the engine sees the real hardware output format when
        // we build the graph.
        configureSession()
        if !built { build(); built = true }
        engine.prepare()
        do {
            try engine.start()
            started = true
            NSLog("EngineSound started: running=\(engine.isRunning) sr=\(sampleRate)")
        } catch {
            // Audio is non-critical; the game still plays silently if this fails.
            print("EngineSound failed to start: \(error)")
        }
    }

    func stop() {
        guard started else { return }
        engine.stop()
        started = false
    }

    /// Feed the current car state. `speedFraction` 0..1 of top speed; `throttle` 0..1.
    func update(speedFraction: Float, throttle: Float) {
        // Idle floor so the engine never goes fully silent while racing.
        targetRPM = max(0.08, min(1, speedFraction * 0.85 + throttle * 0.25))
        targetLoad = max(0, min(1, throttle))
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        do {
            // Playback (not .mixWithOthers): take the main output route so the
            // engine note reliably plays out of the phone speaker even while the
            // screen is being mirrored/captured by QuickTime on the Mac.
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setActive(true, options: [])
            try? session.overrideOutputAudioPort(.speaker)
        } catch {
            print("Audio session error: \(error)")
        }

        // Restart the engine if iOS interrupts us (e.g. when QuickTime grabs or
        // releases the device for screen capture), which otherwise leaves us mute.
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification, object: session)
        nc.addObserver(self, selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification, object: session)
        #endif
    }

    #if os(iOS)
    @objc private func handleInterruption(_ note: Notification) {
        guard let info = note.userInfo,
              let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .ended {
            try? AVAudioSession.sharedInstance().setActive(true)
            if started, !engine.isRunning { try? engine.start() }
        }
    }

    @objc private func handleRouteChange(_ note: Notification) {
        // After a route change (speaker/headphones/capture), make sure we're
        // still running and still aimed at the speaker.
        try? AVAudioSession.sharedInstance().overrideOutputAudioPort(.speaker)
        if started, !engine.isRunning { try? engine.start() }
    }
    #endif
}
