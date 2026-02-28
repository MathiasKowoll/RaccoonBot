//
//  Console.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import os
internal import Foundation

let logger = Logger(subsystem: "CXPatcher", category: "util")

class Console {
    var logMessages: [String] = []
    var items: [String] = []
    var enableLogFile: Bool = debugEnabled == true
    let f = FileManager.default
    
    func cache(_ item: String) {
        self.items.append(item)
    }
    
    func cacheRelease(_ msg: String, function: StaticString = #function) {
        let message: String = "[\(function)] \(msg) \(self.items.joined(separator: ","))"
        
        #if DEBUG
        print(message)
        #endif
        if enableLogFile == true {
            logMessages.append(message)
        }
        self.items.removeAll()
    }
    
    func log(_ msg: String, function: StaticString = #function) {
        let message: String = "[\(function)] \(msg)"
        
        #if DEBUG
        print(message)
        #endif
        if enableLogFile == true {
            logMessages.append(message)
        }
    }
    func warn(_ msg: String, function: StaticString = #function) {
        let message: String = "[\(function)] \(msg)"
        
        #if DEBUG
        print(message)
        #endif
        if (useLogger) {
            logger.notice("\(message)")
        }
        if enableLogFile == true {
            logMessages.append(message)
        }
    }
    func error(_ msg: String, function: StaticString = #function) {
        let message: String = "[\(function)] \(msg)"
        
        let errorMsg: String = "ERROR: \(message)"
        if (useLogger) {
            logger.error("\(errorMsg)")
        }
        if enableLogFile == true {
            logMessages.append(message)
        }
    }
    func clear() {
        self.logMessages.removeAll()
    }
    func saveLogs(to: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("Procyon.log.txt")) {
        if f.fileExists(atPath: to.path(percentEncoded: false)) {
            do {
                try f.removeItem(at: to)
            } catch {
                console.error(error.localizedDescription)
            }
        }
        let content = logMessages.joined(separator: "\n")
        console.warn("Saving logs to \(to)")
        do {
            try content.write(to: to, atomically: true, encoding: .utf8)
        } catch {
            console.error(error.localizedDescription)
        }
    }
}

let console = Console()

