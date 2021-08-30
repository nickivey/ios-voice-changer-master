//
//  PlaySoundsViewController+Audio.swift
//
//  Copyright © 2016 Udacity. All rights reserved.
//

import UIKit
import AVFoundation

// MARK: - PlaySoundsViewController: AVAudioPlayerDelegate

extension PlaySoundsViewController: AVAudioPlayerDelegate {
    
    // MARK: Alerts
    
    struct Alerts {
        static let DismissAlert = "Dismiss"
        static let RecordingDisabledTitle = "Recording Disabled"
        static let RecordingDisabledMessage = "You've disabled this app from recording your microphone. Check Settings."
        static let RecordingFailedTitle = "Recording Failed"
        static let RecordingFailedMessage = "Something went wrong with your recording."
        static let AudioRecorderError = "Audio Recorder Error"
        static let AudioSessionError = "Audio Session Error"
        static let AudioRecordingError = "Audio Recording Error"
        static let AudioFileError = "Audio File Error"
        static let AudioEngineError = "Audio Engine Error"
    }


    // MARK: PlayingState (raw values correspond to sender tags)
    
    enum PlayingState { case playing, notPlaying }
    
    
    // MARK: Audio Functions
    
    func setupAudio() {
        // initialize (recording) audio file
        do {
            audioFile = try AVAudioFile(forReading: recordedAudioURL as URL)
        } catch {
            showAlert(Alerts.AudioFileError, message: String(describing: error))
        }        
    }
    
 
    func playSound(rate: Float? = nil, pitch: Float? = nil, echo: Bool = false, reverb: Bool = false) {

        // initialize audio engine components
        audioEngine = AVAudioEngine()
        
        // node for playing audio
        audioPlayerNode = AVAudioPlayerNode()
        audioEngine.attach(audioPlayerNode)
        
       audioMixer = AVAudioMixerNode()
       audioEngine.attach(audioMixer)
        
   //   self.audioEngine.connect(audioEngine.outputNode, to: audioMixer, format: nil)
    //    self.audioEngine.connect(audioMixer, to: audioEngine.outputNode, format: nil)

        
        // node for adjusting rate/pitch
        let changeRatePitchNode = AVAudioUnitTimePitch()
        if let pitch = pitch {
            changeRatePitchNode.pitch = pitch
        }
        if let rate = rate {
            changeRatePitchNode.rate = rate
        }
        audioEngine.attach(changeRatePitchNode)
        
        // node for echo
        let echoNode = AVAudioUnitDistortion()
        echoNode.loadFactoryPreset(.multiEcho1)
        audioEngine.attach(echoNode)
        
        // node for reverb
        let reverbNode = AVAudioUnitReverb()
        reverbNode.loadFactoryPreset(.cathedral)
        reverbNode.wetDryMix = 50
        audioEngine.attach(reverbNode)
        
        // connect nodes
        if echo == true && reverb == true {
            connectAudioNodes(audioPlayerNode, changeRatePitchNode, echoNode, reverbNode, audioMixer, audioEngine.outputNode)
        } else if echo == true {
            connectAudioNodes(audioPlayerNode, changeRatePitchNode, echoNode, audioMixer, audioEngine.outputNode)
        } else if reverb == true {
            connectAudioNodes(audioPlayerNode, changeRatePitchNode, reverbNode, audioMixer, audioEngine.outputNode)
        } else {
            connectAudioNodes(audioPlayerNode, changeRatePitchNode, audioMixer, audioEngine.outputNode)
        }
        
        
        // schedule to play and start the engine!
        audioPlayerNode.stop()
        audioPlayerNode.scheduleFile(audioFile, at: nil) {
            
            var delayInSeconds: Double = 0
            
            if let lastRenderTime = self.audioPlayerNode.lastRenderTime, let playerTime = self.audioPlayerNode.playerTime(forNodeTime: lastRenderTime) {
                
                if let rate = rate {
                    delayInSeconds = Double(self.audioFile.length - playerTime.sampleTime) / Double(self.audioFile.processingFormat.sampleRate) / Double(rate)
                } else {
                    delayInSeconds = Double(self.audioFile.length - playerTime.sampleTime) / Double(self.audioFile.processingFormat.sampleRate)
                }
            }
            
            // schedule a stop timer for when audio finishes playing
            self.stopTimer = Timer(timeInterval: delayInSeconds, target: self, selector: #selector(PlaySoundsViewController.stopAudio), userInfo: nil, repeats: false)
            RunLoop.main.add(self.stopTimer!, forMode: RunLoopMode.defaultRunLoopMode)
        }
        
        do {
            try audioEngine.start()

        } catch {
            showAlert(Alerts.AudioEngineError, message: String(describing: error))
            return
        }
        
        let audioAsset = AVURLAsset.init(url: recordedAudioURL, options: nil)
        let durationInSeconds = CMTimeGetSeconds(audioAsset.duration)
        
        let length = 4000
        let buffer = AVAudioPCMBuffer(pcmFormat: audioPlayerNode.outputFormat(forBus: 0),frameCapacity:AVAudioFrameCount(length))
        buffer!.frameLength = AVAudioFrameCount(durationInSeconds)


        let dirPaths: AnyObject = NSSearchPathForDirectoriesInDomains( FileManager.SearchPathDirectory.documentDirectory,  FileManager.SearchPathDomainMask.userDomainMask, true)[0] as AnyObject
        let tmpFileUrl: NSURL = NSURL.fileURL(withPath: dirPaths.appendingPathComponent("effectedSound.caf")) as NSURL

        filteredOutputURL = tmpFileUrl

        do{
            print(dirPaths)
            let settings = [AVFormatIDKey: NSNumber(value: kAudioFormatLinearPCM), AVSampleRateKey: NSNumber(value: 44100), AVNumberOfChannelsKey: NSNumber(value: 1)]
            self.newAudio = try AVAudioFile(forWriting: tmpFileUrl as URL, settings: settings)
            

            audioMixer.installTap(onBus: 0, bufferSize: (AVAudioFrameCount(durationInSeconds)), format: self.audioPlayerNode.outputFormat(forBus: 0)){ [self]
                (buffer: AVAudioPCMBuffer!, time: AVAudioTime!)  in

                print(self.newAudio!.length)
                print("=====================")
                print(self.audioFile.length)
                print("**************************")
                if (self.newAudio!.length) < (self.audioFile.length){

                    do{
                        //print(buffer)
                        try self.newAudio!.write(from: buffer)
                    }catch _{
                        print("Problem Writing Buffer")
                    }
                }else{
                    audioPlayerNode.removeTap(onBus: 0)
                }

            }
        }catch _{
            print("Problem")
        }
        
        // play the recording!
        audioPlayerNode.play()
        
    }
    
    
    @objc func stopAudio() {
        
        if let audioPlayerNode = audioPlayerNode {
            audioPlayerNode.stop()
        }
        
        if let stopTimer = stopTimer {
            stopTimer.invalidate()
        }
        
        configureUI(.notPlaying)
                        
        if let audioEngine = audioEngine {
            audioEngine.stop()
            audioEngine.reset()
        }
    }
    
    // MARK: Connect List of Audio Nodes
    
    func connectAudioNodes(_ nodes: AVAudioNode...) {
        for x in 0..<nodes.count-1 {
            audioEngine.connect(nodes[x], to: nodes[x+1], format: audioFile.processingFormat)
        }
    }
    
    // MARK: UI Functions

    func configureUI(_ playState: PlayingState) {
        switch(playState) {
        case .playing:
            setPlayButtonsEnabled(false)
            stopButton.isEnabled = true
        case .notPlaying:
            setPlayButtonsEnabled(true)
            stopButton.isEnabled = false
        }
    }
    
    func setPlayButtonsEnabled(_ enabled: Bool) {
        snailButton.isEnabled = enabled
        chipmunkButton.isEnabled = enabled
        rabbitButton.isEnabled = enabled
        vaderButton.isEnabled = enabled
        echoButton.isEnabled = enabled
        reverbButton.isEnabled = enabled
    }

    func showAlert(_ title: String, message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Alerts.DismissAlert, style: .default, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    
    func sendAudio() {
        var shareView = UIActivityViewController!(nil)
        shareView = UIActivityViewController(activityItems: [self.filteredOutputURL!], applicationActivities:nil )
        self.present(shareView!,animated:true,completion: nil )
    }
    
 
}
