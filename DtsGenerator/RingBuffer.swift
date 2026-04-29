//
//  RingBuffer.swift
//  DtsGenerator
//
//  Created by Jim on 4/27/26.
//

import Foundation
internal import Combine
import Synchronization
import SwiftUI
import AVFoundation

nonisolated let bufferSize = 8192  // delay line
nonisolated let bitBufferSize = 256

@Observable nonisolated class RingBuffer {
    
    var busy = false
    var ti : TimeInterval = 0
    private var buffers : [[Float]] = Array(repeating: Array(repeating: 0, count: bufferSize), count: 2)
    
    private var inIndex : Int = 0
    private var outIndex : Int = 0
    private var full = false
    
    var reels : [Int] = [1001,1002,1003,1004,1005]
    
    private var frequencyAccum = 0.0
    private var ltcPhase : Int32 = 0
    private var ltcAmplitude : Float = 0.1
    var serialNumber : UInt32 = 1234
    var frameNumber : UInt32 = 0   // reel 1, frame 0 is the pop
    var reelNumber : UInt32 = 1
    private var ltcShifter : UInt32 = 0
    private var toggle = false
    private let freqIncr = 1440.0 / 48000.0
    private let bitsPerDtsHalfCell = 33.33        // half cells, 1440 hz
    
    // -6dB for now
    private var posBit : [Float] = Array(repeating: -0.5, count: bitBufferSize)   // need 133 for a sync mark
    private var negBit : [Float] = Array(repeating: 0.5, count: bitBufferSize)
    var numSamplesOverflow = 0{
        didSet{
            if numSamplesOverflow != 0 {
                //print("numSamplesOverflow \(numSamplesOverflow)")
            }
        }
    }

    func reset(){
        inIndex = 0
        outIndex = 0
        full = false
        
        reelNumber = 1
        frameNumber = 0     // reel 1 starts at the pop, all others at FFOA (60)
        
        ti = 0              // measuring how much time we spend in this routine
     }
    
    var syncSampleArray : [Int] = []
    var totalSamples = 0    // measure samples between sync marks
    var lastSyncSample = 0    // sync mark in right channel

    @discardableResult func dtsGenService() -> OSStatus {
        
        // a fast DTS generator that writes all the samples of the period using memcpy
        
        guard busy == false else {return noErr}
        guard reelNumber <= reels.count else {return -1}

        self.busy = true
        let now = Date()

        //
        var framesAvailable = Int(framesAvailable())
        var index = Int(inIndex)
        
        var pNegBit: UnsafeMutablePointer<Float>?
        negBit.withUnsafeMutableBufferPointer{ ptr in
            
            pNegBit = ptr.baseAddress!.advanced(by: Int(0))
        }
        var pPosBit: UnsafeMutablePointer<Float>?
        posBit.withUnsafeMutableBufferPointer{ ptr in
            
            pPosBit = ptr.baseAddress!.advanced(by: Int(0))
        }

        var pData: UnsafeMutablePointer<Float>?
        var pBit: UnsafeMutablePointer<Float>?
        var size: Int = 0
        
        // handle overflow from previous frame
        while numSamplesOverflow > 0 && framesAvailable > 0{

            var numSamplesToWrite   = min(numSamplesOverflow, framesAvailable)      // paranoia
            numSamplesToWrite       = min(numSamplesOverflow, bufferSize - index)   // wrap
            numSamplesToWrite       = min(numSamplesToWrite, bitBufferSize)         // paranoia, src size limit
            
            for i in 0..<buffers.count{
                buffers[i].withUnsafeMutableBufferPointer { ptr in
                    
                    pData = ptr.baseAddress!.advanced(by: Int(index))
                    pBit = toggle ? pNegBit : pPosBit
                    size = numSamplesToWrite * MemoryLayout<Float>.size
                    memcpy(pData, pBit!, size)  // write half cell samples
                }
            }
            
            numSamplesOverflow -= numSamplesToWrite
            framesAvailable -= numSamplesToWrite
            index += numSamplesToWrite; index %= bufferSize

        }
        
        while framesAvailable > 0{
            
            ltcPhase %= 48
            toggle.toggle()
            switch ltcPhase{
            case 0:
                //syncMark = true // temp sync mark in right
                syncSampleArray.append(totalSamples - lastSyncSample)
                lastSyncSample = totalSamples
                
                frequencyAccum += 4 * bitsPerDtsHalfCell
                ltcPhase += 4
                frameNumber += 1
                
                let maxFrameNumber = reels[Int(reelNumber) - 1] // guard statement keeps this in bounds
                
                if frameNumber > maxFrameNumber{
                    reelNumber += 1; print("reel \(reelNumber)")
                    frameNumber = 60    // FFOA
                    
                }

                switch(reelNumber){
                case 14,15:
                    ltcShifter = frameNumber & 0x1 == 0 ? serialNumber : frameNumber + reelNumber << 16
                    break
                default:
                    ltcShifter = frameNumber & 0xf == 0 ? serialNumber : frameNumber + reelNumber << 16
                    break
                }
                
                break
            case 1,2,3,5,6,7:
                print("ltcPhase error, phases 1,2,3,5,6,7 are not used")
                break
            case 4:
                ltcPhase += 4
                frequencyAccum += 4 * bitsPerDtsHalfCell
                break
            default:
                if ltcShifter & 1 == 1{
                   ltcPhase += 1; frequencyAccum += bitsPerDtsHalfCell
                   if ltcPhase & 1 == 0{ltcShifter >>= 1}
                }else{
                   ltcPhase += 2; frequencyAccum += 2 * bitsPerDtsHalfCell; ltcShifter >>= 1
                    
                    if ltcPhase & 1 == 1{
                        print("ltcPhase error, 0 out of phase at \(ltcPhase)")
                        ltcPhase = 0
                    }
                }
                break
                
                /*
                 */
                
            }
            
            // output frequencyAccum samples
            let numSamples = Int(frequencyAccum)
            // subtract the integer part
            frequencyAccum -= Double(numSamples)
            totalSamples += numSamples
            
            // handle wrap, running out of framesAvailable
            var numSamplesToWrite   = min(numSamples, bufferSize - index)           // wrap
            numSamplesToWrite       = min(numSamplesToWrite, framesAvailable)       // out of space
            numSamplesToWrite       = min(numSamplesToWrite, bitBufferSize)         // paranoia, src size limit
            
            numSamplesOverflow = numSamples - numSamplesToWrite // continue writing in the next frame
            
            for i in 0..<buffers.count{
                buffers[i].withUnsafeMutableBufferPointer { ptr in
                    
                    pData = ptr.baseAddress!.advanced(by: Int(index))
                    pBit = toggle ? pNegBit : pPosBit
                    size = numSamplesToWrite * MemoryLayout<Float>.size
                    memcpy(pData, pBit!, size)  // write half cell samples
                }
            }

            // maintain ptrs
            index += numSamplesToWrite; index %= bufferSize
            framesAvailable -= numSamplesToWrite
            
            //print("numSamplesToWrite \(numSamplesToWrite) ltcPhase \(ltcPhase) toggle \(toggle)")
        }
        
        inIndex = index
        full = inIndex == outIndex
        
        ti += Date().timeIntervalSince(now)

        self.busy = false
        return noErr
    }

    func framesAvailable() -> UInt32{
        
        //if inIndex != outIndex{full = false}
        if full{return 0}
        
        return  UInt32(outIndex == inIndex ? bufferSize : (outIndex - inIndex + bufferSize) % bufferSize)
    }
    func readFramesAvailable() -> UInt32{
        
        //print("readFramesAvailable inIndex, outIndex \(inIndex) \(outIndex)")
        
        //if inIndex != outIndex{full = false}
        if full{return UInt32(bufferSize)}

        return UInt32((inIndex - outIndex + bufferSize) % bufferSize)
    }

    @discardableResult func fetch(_ abl: UnsafeMutableAudioBufferListPointer, nFrames: UInt32)->OSStatus{
        
        var outIndexCopy = self.outIndex    // copy ptr
        var ablOfs : Int = 0                // on wrap, happens once

        var framesToWrite = Int(min(nFrames,readFramesAvailable()))
        if framesToWrite == 0{return -1}    // out of frames
        
        let numBuffers = min(abl.count,buffers.count)   // will always be stereo, but allow mono

        while framesToWrite > 0{
            
            let frs = min(Int(framesToWrite),bufferSize - outIndexCopy)  // wrap
            let numBytes = frs * MemoryLayout<Float32>.size
            
            for i in 0..<numBuffers{
                
                buffers[i].withUnsafeMutableBufferPointer { ptr in
                    
                    let dest = abl[i].mData!.advanced(by: ablOfs).assumingMemoryBound(to: Float32.self)
                    let src = ptr.baseAddress!.advanced(by: outIndexCopy)
                    memcpy(dest,src,numBytes)
                }
            }
            
            framesToWrite -= frs
            ablOfs = frs
            outIndexCopy += Int(frs)
            outIndexCopy %= bufferSize

        }
        
        outIndex = outIndexCopy // maintain ptr

        return noErr
    }
}
