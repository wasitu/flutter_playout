//
//  AudioPlayer.swift
//  Runner
//
//  Created by Khuram Khalid on 27/09/2019.
//

import Foundation
import AVFoundation
import Flutter
import MediaPlayer

class AudioPlayer: NSObject, FlutterPlugin, FlutterStreamHandler {
    static func register(with registrar: FlutterPluginRegistrar) {
        
        let player = AudioPlayer()
        
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            try audioSession.setCategory(AVAudioSession.Category.playback)
        } catch _ { }
        
        let channel = FlutterMethodChannel(name: "tv.mta/NativeAudioChannel", binaryMessenger: registrar.messenger())
        
        registrar.addMethodCallDelegate(player, channel: channel)
        
        setupEventChannel(messenger: registrar.messenger(), instance: player)
    }
    
    private static func setupEventChannel(messenger:FlutterBinaryMessenger, instance:AudioPlayer) {
        
        /* register for Flutter event channel */
        instance.eventChannel = FlutterEventChannel(name: "tv.mta/NativeAudioEventChannel", binaryMessenger: messenger, codec: FlutterJSONMethodCodec.sharedInstance())
        
        instance.eventChannel!.setStreamHandler(instance)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        
      /* start audio playback */
      if ("play" == call.method) {
          
          if let arguments = call.arguments as? NSDictionary {
              
              if let audioURL = arguments["url"] as? String {
                  
                  if let title = arguments["title"] as? String {
                      
                      if let subtitle = arguments["subtitle"] as? String {
                          
                          if let position = arguments["position"] as? Double {
                            
                            if let isLiveStream = arguments["isLiveStream"] as? Bool {
                                setup(title: title, subtitle: subtitle, position: position, url: audioURL, isLiveStream: isLiveStream)
                            }
                          }
                      }
                  }
              }
          }
          
          result(true)
      }
      else if ("resume" == call.method) {
        play()
        result(true)
      }
      
      /* pause audio playback */
      else if ("pause" == call.method) {
          
          pause()
          
          result(true)
      }
        
        /* reset audio playback */
        else if ("reset" == call.method) {
            
            reset()
            
            result(true)
        }
          
      /* seek audio playback */
      else if ("seekTo" == call.method) {
          
          if let arguments = call.arguments as? NSDictionary {
              
              if let seekToSecond = arguments["second"] as? Double {
                  
                  seekTo(seconds: seekToSecond)
              }
          }
          
          result(true)
      }
      else if ("setSpeed" == call.method) {
          if let arguments = call.arguments as? NSDictionary {
              if let speed = arguments["speed"] as? Double {
                setSpeed(speed: speed)
              }
          }
          
          result(true)
      }
        
        /* stop audio playback */
        else if ("dispose" == call.method) {
            
            teardown()
            
            result(true)
        }
          
      /* not implemented yet */
      else { result(FlutterMethodNotImplemented) }
    }
    
    private override init() { }
    
    private var audioPlayer = AVPlayer()
    
    private var timeObserverToken:Any?
    
    /* Flutter event streamer properties */
    private var eventChannel:FlutterEventChannel?
    private var flutterEventSink:FlutterEventSink?
    
    private var nowPlayingInfo = [String : Any]()
    
    private var mediaURL = ""
    
    private var speed: Float = 1.0
    
    private func setup(title:String, subtitle:String, position:Double, url: String?, isLiveStream:Bool) {

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(AVAudioSession.Category.playback, options: AVAudioSession.CategoryOptions.allowBluetooth)
            try audioSession.setActive(true)
        } catch _ { }
        
        audioPlayer.pause()
        
        var validPlaybackUrl = false
        
        if let audioURL = url {
            
            if let url = URL(string: audioURL) {
            
                /* Create the asset to play */
                let asset = AVAsset(url: url)
                
                if (asset.isPlayable) {
                    
                    validPlaybackUrl = true
                
                        
                        mediaURL = audioURL
                        
                        audioPlayer = AVPlayer(url: url)
                    speed = 1.0
                        
                        let center = NotificationCenter.default
                        
                        center.addObserver(self, selector: #selector(onComplete(_:)), name: NSNotification.Name.AVPlayerItemDidPlayToEndTime, object: self.audioPlayer.currentItem)
                        center.addObserver(self, selector:#selector(onAVPlayerNewErrorLogEntry(_:)), name: .AVPlayerItemNewErrorLogEntry, object: audioPlayer.currentItem)
                        center.addObserver(self, selector:#selector(onAVPlayerFailedToPlayToEndTime(_:)), name: .AVPlayerItemFailedToPlayToEndTime, object: audioPlayer.currentItem)
                        
                        /* Add observer for AVPlayer status and AVPlayerItem status */
                        self.audioPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.status), options: [.new, .initial], context: nil)
                        self.audioPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options:[.old, .new, .initial], context: nil)
                        self.audioPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.timeControlStatus), options:[.old, .new, .initial], context: nil)
                        self.audioPlayer.addObserver(self, forKeyPath: #keyPath(AVPlayer.currentItem.duration), options: [.new, .initial], context: nil)
                        
                        let interval = CMTime(seconds: 1.0,
                        preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                        
                        timeObserverToken = audioPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) {
                            time in self.onTimeInterval(time: time)
                        }
                        
                        setupRemoteTransportControls()
                        
                        setupNowPlayingInfoPanel(title: title, subtitle: subtitle, isLiveStream: isLiveStream)
                        
                        seekTo(seconds: position / 1000)
                    
                    onDurationChange()
                }
            }
        }
        
        if (!validPlaybackUrl) {
            pause()
        }
    }
    
    @objc func onComplete(_ notification: Notification) {
        
        pause()
        
        self.flutterEventSink?(["name":"onComplete"])
                
        updateInfoPanel()
    }
    
    /* Observe If AVPlayerItem.status Changed to Fail */
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        
        if keyPath == #keyPath(AVPlayerItem.status) {
            
            let newStatus: AVPlayerItem.Status
            
            if let newStatusAsNumber = change?[NSKeyValueChangeKey.newKey] as? NSNumber {
                newStatus = AVPlayerItem.Status(rawValue: newStatusAsNumber.intValue)!
            } else {
                newStatus = .unknown
            }
            
            if newStatus == .failed {
                self.flutterEventSink?(["name":"onError", "error":(String(describing: self.audioPlayer.currentItem?.error))])
            } else if newStatus == .readyToPlay {
                self.flutterEventSink?(["name":"onReady"])
            }
        }
        
        else if keyPath == #keyPath(AVPlayer.timeControlStatus) {
            
            guard let p = object as! AVPlayer? else {
                return
            }
            
            if #available(iOS 10.0, *) {
                
                switch (p.timeControlStatus) {
                
                case AVPlayerTimeControlStatus.paused:
                    self.flutterEventSink?(["name":"onPause"])
                    break
                
                case AVPlayerTimeControlStatus.playing:
                    self.flutterEventSink?(["name":"onPlay"])
                    break
                
                case .waitingToPlayAtSpecifiedRate: break
                @unknown default:
                    break
                }
            } else {
                // Fallback on earlier versions
            }
        }
        
        else if keyPath == #keyPath(AVPlayer.currentItem.duration) {
            onDurationChange()
            updateInfoPanel()
        }
    }
    
    @objc func onAVPlayerNewErrorLogEntry(_ notification: Notification) {
        guard let object = notification.object, let playerItem = object as? AVPlayerItem else {
            return
        }
        guard let error: AVPlayerItemErrorLog = playerItem.errorLog() else {
            return
        }
        guard var errorMessage = error.extendedLogData() else {
            return
        }
        
        errorMessage.removeLast()
        
        self.flutterEventSink?(["name":"onError", "error":String(data: errorMessage, encoding: .utf8)])
    }

    @objc func onAVPlayerFailedToPlayToEndTime(_ notification: Notification) {
        guard let error = notification.userInfo!["AVPlayerItemFailedToPlayToEndTimeErrorKey"] else {
            return
        }
        self.flutterEventSink?(["name":"onError", "error":error])
    }
    
    private func setupRemoteTransportControls() {
        
        let commandCenter = MPRemoteCommandCenter.shared()

        // Add handler for Play Command
        commandCenter.playCommand.addTarget { event in
            self.play()
            return .success
        }

        // Add handler for Pause Command
        commandCenter.pauseCommand.addTarget { event in
            self.pause()
            return .success
        }
        
        commandCenter.skipForwardCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
            var seconds = self.audioPlayer.currentTime().seconds + 10
            let duration = self.audioPlayer.currentItem?.duration.seconds ?? 0
            if (seconds > duration) { seconds = duration }
            self.seekTo(seconds: seconds)
            return .success
        }
        
        commandCenter.skipBackwardCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
            var seconds = self.audioPlayer.currentTime().seconds - 10
            if (seconds < 0) { seconds = 0 }
            self.seekTo(seconds: seconds)
            return .success
        }
        
        if #available(iOS 9.1, *) {
            commandCenter.changePlaybackPositionCommand.addTarget { (event) -> MPRemoteCommandHandlerStatus in
                let positionTime = (event as? MPChangePlaybackPositionCommandEvent)?.positionTime ?? 0
                self.seekTo(seconds: round(positionTime))
                return .success
            }
        }
    }
    
    private func setupNowPlayingInfoPanel(title:String, subtitle:String, isLiveStream:Bool) {
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = title
        
        nowPlayingInfo[MPMediaItemPropertyArtist] = subtitle
        
        if #available(iOS 10.0, *) {
            nowPlayingInfo[MPNowPlayingInfoPropertyIsLiveStream] = isLiveStream
        }

        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer.currentTime().seconds

        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = audioPlayer.currentItem?.asset.duration.seconds

        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = 0 // will be set to 1 by onTime callback

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
    }
    
    private func play() {
        
        audioPlayer.rate = speed
        
        self.flutterEventSink?(["name":"onPlay"])
        
        updateInfoPanel()
    }
        
    private func pause() {
        
        audioPlayer.pause()
        
        self.flutterEventSink?(["name":"onPause"])
        
        updateInfoPanel()
    }
    
    private func seekTo(seconds:Double) {
                
        let position = self.audioPlayer.currentTime().seconds
        
        audioPlayer.seek(to: CMTime(seconds: seconds, preferredTimescale: CMTimeScale(NSEC_PER_SEC))) { (isCompleted) in
            
            if (isCompleted) {
                
                self.flutterEventSink?(["name":"onSeek", "position":position, "offset":seconds])
            }
            
            self.updateInfoPanel()
        }
    }
    
    private func setSpeed(speed: Double) {
        self.speed = Float(speed)
        if audioPlayer.rate > 0 {
            audioPlayer.rate = self.speed
            updateInfoPanel()
        }
    }
    
    private func reset() {
        
        audioPlayer.pause()
        
        seekTo(seconds: 0.0)
        
        /* reset state */
        self.mediaURL = ""
                
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    }
    
    private func teardown() {
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        
        if let timeObserver = timeObserverToken {
            audioPlayer.removeTimeObserver(timeObserver)
            timeObserverToken = nil
        }
        
        /* stop playback */
        self.audioPlayer.pause()
        
        /* reset state */
        self.mediaURL = ""
        
        NotificationCenter.default.removeObserver(self)
        
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false)
        } catch _ { }
    }
    
    private func onTimeInterval(time:CMTime) {
        
        self.flutterEventSink?(["name":"onTime", "time":self.audioPlayer.currentTime().seconds])
        
        updateInfoPanel()
    }
    
    public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        flutterEventSink = events
        return nil
    }
    
    public func onCancel(withArguments arguments: Any?) -> FlutterError? {
        flutterEventSink = nil
        return nil
    }
    
    private func updateInfoPanel() {
        self.nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = audioPlayer.currentTime().seconds
        self.nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = audioPlayer.currentItem?.asset.duration.seconds
        self.nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = audioPlayer.rate
        
        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
    }
    
    private func onDurationChange() {
        guard let item = self.audioPlayer.currentItem else { return }
        let duration = item.duration.seconds * 1000
        if (!duration.isNaN) {
            self.flutterEventSink?(["name":"onDuration", "duration":duration])
        }
    }
}
