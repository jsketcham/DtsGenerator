//
//  CAOutput.swift
//  DtsGenerator
//
//  Created by Jim on 4/27/26.
//

import Foundation
internal import Combine
import Synchronization
import SwiftUI
import AVFoundation

@Observable nonisolated class CAOutput{
    
    var busy = false
    var ringBuffer = RingBuffer()

    // AudioUnits and Graph
    var graph: AUGraph?
    var outputNode: AUNode = 0
    var outputUnit: AudioUnit?
    var asbdOut = AudioStreamBasicDescription()

    var outputProc: AURenderCallback = { (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames,
                                          ioData) -> OSStatus in
        
        let this = Unmanaged<CAOutput>.fromOpaque(inRefCon).takeUnretainedValue()
        
        if let pAbl = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: ioData)){
            
            this.ringBuffer.fetch(pAbl, nFrames: inNumberFrames) // empty ring buffer
        }
        
        Task {
            this.ringBuffer.dtsGenService() // fill ring buffer
        }
        
        return noErr
    }
    
    init(_ output : AudioDeviceID){
        
        if checkErr(setupAUHAL(output)) != nil{
           exit(1)
        }

    }
    
    func stop(){
        
        if isRunning(){
            
            if let _ = checkErr(AudioOutputUnitStop(outputUnit!)) {
              return
            }
        }
        
    }
    func start(){
        
        if !isRunning(){
            
            if let _ = checkErr(AudioOutputUnitStart(outputUnit!)){
                return
            }

        }
        
    }
    func reset(_ output : AudioDeviceID){
        
    }
    func isRunning() -> Bool {
        
        var auhalRunning: UInt32 = 0
        var size: UInt32 = UInt32(MemoryLayout<UInt32>.size)

        if outputUnit != nil {
          if checkErr(AudioUnitGetProperty(outputUnit!, kAudioOutputUnitProperty_IsRunning, kAudioUnitScope_Global, 0,
                                           &auhalRunning, &size)) != nil {
            return false
          }
        }

        return auhalRunning != 0
    }
    
//    @discardableResult func InitAndStartAUHAL() -> OSStatus{
//     
//        if let err = checkErr(AudioUnitInitialize(outputUnit!)){
//            return err
//        }
//     
//        if let err = checkErr(AudioOutputUnitStart(outputUnit!)){
//            return err
//        }
//        
//        return noErr
//    }

}
nonisolated extension CAOutput{
    
    // https://developer.apple.com/library/archive/technotes/tn2091/_index.html
    // example code is for input, changed for output
    
    func setupAUHAL(_ output: AudioDeviceID) -> OSStatus {
        
        var comp: AudioComponent?
        var desc = AudioComponentDescription()

        // There are several different types of Audio Units.
        // Some audio units serve as Outputs, Mixers, or DSP
        // units. See AUComponent.h for listing
        desc.componentType = kAudioUnitType_Output

        // Every Component has a subType, which will give a clearer picture
        // of what this components function will be.
        desc.componentSubType = kAudioUnitSubType_HALOutput

        // all Audio Units in AUComponent.h must use
        // "kAudioUnitManufacturer_Apple" as the Manufacturer
        desc.componentManufacturer = kAudioUnitManufacturer_Apple
        desc.componentFlags = 0
        desc.componentFlagsMask = 0

        // Finds a component that meets the desc spec's
        comp = AudioComponentFindNext(nil, &desc)
        if comp == nil {
          exit(-1)
        }
        // gains access to the services provided by the component
        if let err = checkErr(AudioComponentInstanceNew(comp!, &outputUnit)) {
          return err
        }

        // AUHAL needs to be initialized before anything is done to it
        if let err = checkErr(AudioUnitInitialize(outputUnit!)) {
          return err
        }
        

        ///////////////
        // ENABLE IO (output)   note the Apple code sample is for input
        // You must enable the Audio Unit (AUHAL) for either input or output
        // BEFORE setting the AUHAL's current device.
        /*
         func AudioUnitSetProperty(
             _ inUnit: AudioUnit,
             _ inID: AudioUnitPropertyID,
             _ inScope: AudioUnitScope,
             _ inElement: AudioUnitElement,
             _ inData: UnsafeRawPointer?,
             _ inDataSize: UInt32
         ) -> OSStatus
         */
        // Typically, Element 0 represents the output bus, and Element 1 represents the input bus for a standard 2-bus unit
        var enableIO: UInt32 = 0    // disable input (bus 1)
        if let err = checkErr(AudioUnitSetProperty(outputUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input,
                                             1, &enableIO, UInt32(MemoryLayout<UInt32>.size))) {
            return err
        }

        enableIO = 1    // enable output (bus 0)
        if let err = checkErr(AudioUnitSetProperty(outputUnit!, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output,
                                             0, &enableIO, UInt32(MemoryLayout<UInt32>.size))) {
            return err
        }

        // 4. set AUHAL current device
        if let err = checkErr(setOutputDeviceAsCurrent(output)) {
          return err
        }
        
        // 5. get the output format (bus 0)
        var propertySize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        if let err = checkErr(AudioUnitGetProperty(outputUnit!, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &asbdOut, &propertySize)) {
            
            return err
        }
        //print("deviceID \(output) asbd \(asbdOut)")
        // deviceID 62 asbd AudioStreamBasicDescription(mSampleRate: 48000.0, mFormatID: 1819304813, mFormatFlags: 9, mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        
        // register output procedure
        var output = AURenderCallbackStruct(
          inputProc: outputProc,
          inputProcRefCon: UnsafeMutableRawPointer(Unmanaged<CAOutput>.passUnretained(self).toOpaque())
        )

        if let err = checkErr(AudioUnitSetProperty(outputUnit!, kAudioUnitProperty_SetRenderCallback,
                                                   kAudioUnitScope_Input, 0, &output,
                                                   UInt32(MemoryLayout<AURenderCallbackStruct>.size))) {
          return err
        }
        
        // AUHAL needs to be initialized before anything is done to it
        if let err = checkErr(AudioUnitInitialize(outputUnit!)) {
          return err
        }

        return noErr
    }
    
    func setOutputDeviceAsCurrent(_ out: AudioDeviceID) -> OSStatus {
      var out = out
      var size = UInt32(MemoryLayout<AudioDeviceID>.size)
      var theAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
      )

      if out == kAudioDeviceUnknown {
        if let err = checkErr(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &theAddress, 0, nil,
                                                         &size, &out)) {
          return err
        }
      }

        // Set the Current Device to the Default Output Unit.
        // changed kAudioUnitScope_Global to kAudioUnitScope_Output, which is right?
        
        return AudioUnitSetProperty(outputUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Output, 0,
                                  &out, UInt32(MemoryLayout<AudioDeviceID>.size))
    }

}

@discardableResult
nonisolated func checkErr(_ err : @autoclosure () -> OSStatus, file: String = #file, line: Int = #line) -> OSStatus! {
    let error = err()
    if error != noErr {
        print("DtsGenerator Error: \(error) ->  \(file):\(line)\n")
        return error
    }
    return nil
}

