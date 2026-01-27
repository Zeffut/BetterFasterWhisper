//
//  MediaControlManager.swift
//  BetterFasterWhisper
//
//  Created by BetterFasterWhisper Contributors
//  Licensed under MIT License
//

import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.betterfasterwhisper", category: "MediaControlManager")

/// Manages media playback control during recording.
/// Simply sends a pause command when recording starts.
final class MediaControlManager: ObservableObject {
    
    // MARK: - Singleton
    
    static let shared = MediaControlManager()
    
    // MARK: - Published Properties
    
    /// Whether to pause media when recording starts
    @Published var pauseMediaOnRecord: Bool {
        didSet {
            UserDefaults.standard.set(pauseMediaOnRecord, forKey: "pauseMediaOnRecord")
        }
    }
    
    // MARK: - Properties
    
    /// MRMediaRemoteSendCommand function pointer
    private var mrMediaRemoteSendCommand: (@convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool)?
    
    // Media Remote Commands
    private let kMRPause: UInt32 = 1
    
    // MARK: - Initialization
    
    private init() {
        // Load setting from UserDefaults (default: enabled)
        self.pauseMediaOnRecord = UserDefaults.standard.object(forKey: "pauseMediaOnRecord") as? Bool ?? true
        loadMediaRemoteFramework()
    }
    
    // MARK: - Private Setup
    
    private func loadMediaRemoteFramework() {
        let frameworkPath = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        
        guard let handle = dlopen(frameworkPath, RTLD_NOW) else {
            logger.warning("Failed to load MediaRemote.framework")
            return
        }
        
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            mrMediaRemoteSendCommand = unsafeBitCast(
                sym,
                to: (@convention(c) (UInt32, UnsafeMutableRawPointer?) -> Bool).self
            )
            logger.info("MRMediaRemoteSendCommand loaded")
        } else {
            logger.warning("Failed to find MRMediaRemoteSendCommand")
        }
        
        logger.info("MediaRemote.framework loaded successfully")
    }
    
    // MARK: - Public Methods
    
    /// Sends a pause command to any playing media (if enabled).
    func pauseMedia() {
        guard pauseMediaOnRecord else {
            logger.info("pauseMedia skipped - feature disabled")
            return
        }
        
        logger.info("pauseMedia called - sending pause command")
        
        if let sendCommand = mrMediaRemoteSendCommand {
            let result = sendCommand(kMRPause, nil)
            logger.info("MRMediaRemoteSendCommand(pause) returned: \(result)")
        } else {
            logger.warning("MRMediaRemoteSendCommand not available")
        }
    }
    
    /// Does nothing - we don't resume media.
    func resumeMedia() {
        // No-op
    }
    
    /// Resets the state.
    func reset() {
        // No-op
    }
}
