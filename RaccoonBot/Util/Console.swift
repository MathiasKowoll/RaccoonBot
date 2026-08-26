//
//  Console.swift
//  RaccoonBot
//
//  Created by Italo Mandara on 24/02/2026.
//

import os
import Foundation

let logger = Logger(subsystem: "CXPatcher", category: "util")

class Console {
    var logMessages: [String] = []
    var items: [String: [String]] = [:]
    var enableLogFile: Bool = DEBUG_ENABLED == true
    let f = FileManager.default
    
    func cache(_ item: String, key: String) {
        if self.items[key] == nil {
            self.items[key] = []
        }
        self.items[key]?.append(item)
    }
    
    func cacheRelease(_ msg: String, key: String, function: StaticString = #function) {
        let message: String = "[\(function)] deferred: \(msg) \(self.items[key]?.joined(separator: ",") ?? "no msg")"
        
        #if DEBUG
        print(message)
        #endif
        if enableLogFile == true {
            logMessages.append(message)
        }
        self.items.removeAll()
    }
    
    func log(_ msg: String, function: StaticString = #function) {
        let message: String = "[\(function)] info: \(msg)"
        
        #if DEBUG
        print(message)
        #endif
        if enableLogFile == true {
            logMessages.append(message)
        }
    }
    func warn(_ msg: String, function: StaticString = #function) {
        let message: String = "[\(function)] warning: \(msg)"
        
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
        let message: String = "[\(function)] error: \(msg)"
        
        let errorMsg: String = "ERROR: \(message)"
        
        #if DEBUG
        print(errorMsg)
        #endif
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
    func saveLogs(to: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("RaccoonBot.log.txt")) {
        if f.fileExists(atPath: to.path(percentEncoded: false)) {
            do {
                try f.removeItem(at: to)
            } catch {
                console.error(String(reflecting: error))
            }
        }
        let content = logMessages.joined(separator: "\n")
        console.warn("Saving logs to \(to)")
        do {
            try content.write(to: to, atomically: true, encoding: .utf8)
        } catch {
            console.error(String(reflecting: error))
        }
    }
}

let console = Console()

