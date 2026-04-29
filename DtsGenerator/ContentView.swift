//
//  ContentView.swift
//  DtsGenerator
//
//  Created by Jim on 4/27/26.
//

import SwiftUI

struct ContentView: View {
    
    @State private var dtsManager = DtsManager()
    
    var body: some View {
        
        VStack {
            TableView(reels: $dtsManager.caHost.caOutput.ringBuffer.reels)   // $ -> binding
                .frame(width: 200, height: 100)
                .padding(10)
            
            Picker("output", selection: $dtsManager.selectedDevice) {
                ForEach(dtsManager.deviceDictionary.keys.sorted(), id: \.self) { device in
                    Text(device)
                }
            }
            .frame(maxWidth: 250)
            .disabled(dtsManager.running)
            .padding(10)
            
            HStack {
                Text("serial \(dtsManager.caHost.caOutput.ringBuffer.serialNumber)")
                    .frame(width:75, alignment: .leading)
                Text("reel \(dtsManager.caHost.caOutput.ringBuffer.reelNumber)")
                    .padding(.leading, 20)
                    .frame(width:75, alignment: .leading)
                Text("frame \(dtsManager.caHost.caOutput.ringBuffer.frameNumber)")
                    .frame(width:75, alignment: .leading)
            }

            Button("\(dtsManager.running ? "Stop" : "Run")") {
                dtsManager.startStop()
            }

        }
        .padding()
        .frame(minWidth: 400, minHeight: 250)
    }
}

#Preview {
    ContentView()
}
