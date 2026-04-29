//
//  DtsManager.swift
//  DtsGenerator
//
//  Created by Jim on 4/27/26.

//  AVAudioEngine works with aggregate devices
//  this uses AudioUnits and Graph style, so that we can select a single output device
// because DtsPlayer uses AVAudioEngine, and it seems that aggregate device keeps us from
// having another AVAudioEngine, in a generator program, from using 'Plugable USB' out

import Foundation
internal import Combine
import CoreAudio
import AudioToolbox
import Synchronization
import Cocoa

@Observable nonisolated class DtsManager: ObservableObject {
    
    var caHost = CAHost(output: 0)    // using Core Audio, we want a single output, can't use AVAudioEngine
    var running = false
    
    var deviceDictionary: [String: AudioDeviceID] = [:] // output devices only
    var selectedDevice = ""{
        didSet{
            print("selectedDevice: \(selectedDevice), oldValue \(oldValue)")
            if oldValue != selectedDevice{
                
                UserDefaults.standard.set(selectedDevice, forKey: "selectedDevice")
                
                if let deviceID = deviceDictionary[selectedDevice]{
                    
                    caHost.deviceID = deviceID
                }
                
            }
        }
    }
    init(){
        
        deviceDictionary = CAHost.getAllDevices(.output) // printing info in debug window, populates deviceDictionary
        
        if let selectedDevice = UserDefaults.standard.string(forKey: "selectedDevice"){
            self.selectedDevice = selectedDevice    
        }
    }
    func startStop(){
        
        caHost.caOutput.stop()
        
        running.toggle()
        
        if running{
            caHost.caOutput.ringBuffer.reset()
            caHost.caOutput.start()
        }
        
    }

}
