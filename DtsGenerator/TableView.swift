//
//  TableView.swift
//  DtsReader
//
//  Created by Jim on 4/21/26.
//

import Foundation
import SwiftUI
internal import Combine
// Usage in SwiftUI:
// TableView()
struct ReelObject{
    @Binding var reels: [Int]
}
class ReelTableView : NSTableView,NSTextFieldDelegate {
    
    var reelObject : ReelObject?    // a way to add @Binding to NSTableView, which is not @Observable
    
    func controlTextDidEndEditing(_ obj: Notification) {
        
        let tf = obj.object as! NSTextField
        print("\(tf.stringValue) \(self.selectedRow)")
        //reels[self.selectedRow] = Int(tf.stringValue)!
        reelObject?.reels[self.selectedRow] = Int(tf.stringValue)!
            
    }
}
struct TableView: NSViewRepresentable {
    
    @Binding var reels: [Int]
    
    class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        
        func numberOfRows(in tableView: NSTableView) -> Int {
            
            guard let rtv = tableView as? ReelTableView,
                  let reels = rtv.reelObject?.reels else{
                
                return  0
                
            }
            return reels.count
        }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            
            guard let rtv = tableView as? ReelTableView,
                  let reels = rtv.reelObject?.reels else{
                
                return  NSTextField(labelWithString: "-")
                
            }
            
            switch(tableColumn?.title){
                case "Reel":
                return NSTextField(labelWithString: "\(row + 1)")
            case "Frames":
                let textField = NSTextField(labelWithString: "\(reels[row])")
                textField.isEditable = true
                textField.delegate = rtv
                return textField
            default:
                return nil
            }
        }
        func tableView(_ tableView: NSTableView, shouldEdit tableColumn: NSTableColumn?, row: Int) -> Bool {
            return tableColumn?.title == "Frames"
        }

        func tableView(_ tableView: NSTableView, setObjectValue object: Any?, for tableColumn: NSTableColumn?, row: Int) {
            guard let object = object as? Int,
                  let rtv = tableView as? ReelTableView,
                  let reels = rtv.reelObject?.reels else {
                print("setObjectValue guard failed")
                return
            }
            rtv.reelObject?.reels[row] = object
            print(String(format:"setObjectValue \(reels)"))
        }
    }
    
    func makeCoordinator() -> Coordinator {print("makeCoordinator \(reels)"); return Coordinator()}
    
    func makeNSView(context: Context) -> NSScrollView {
        
        print("makeNSView")
        
        let scrollView = NSScrollView()
        let tableView = ReelTableView()
        tableView.reelObject = ReelObject(reels: $reels)    // @Observable, workaound for NSTableView not conforming
        
        // Setting up tableview with delegate/datasource
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator
        
        // Add columns and embed in scrollview
        var column = NSTableColumn()
        column.title = "Reel"
        tableView.addTableColumn(column)
        column = NSTableColumn()
        column.title = "Frames"
        tableView.addTableColumn(column)
        
        // add grid lines, alternating background color
        tableView.gridStyleMask = [.solidHorizontalGridLineMask, .solidVerticalGridLineMask]
        tableView.gridColor = NSColor.gridColor
        tableView.usesAlternatingRowBackgroundColors = true
        
        scrollView.documentView = tableView
        
        return scrollView
    }
    
    func updateNSView(_ nsView: NSScrollView, context: Context) {
        
        // this syncs swiftUI -> tableView
        
        let rtv = nsView.documentView as? ReelTableView
        rtv?.reloadData()
        //rtv!.reels[0] = 321
        //reels = rtv!.reels
        print("updateNSView set reels to: \(reels)")
    }
}

