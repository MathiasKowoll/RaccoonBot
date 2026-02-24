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
    var enableLogFile: Bool = false
    let f = FileManager.default
    
    func log(_ msg: String) {
        print(msg)
        if enableLogFile == true {
            logMessages.append(msg)
        }
    }
    func warn(_ msg: String) {
        print(msg)
        logger.notice("\(msg)")
        if enableLogFile == true {
            logMessages.append(msg)
        }
    }
    func error(_ msg: String) {
        let errorMsg: String = "ERROR: \(msg)"
        logger.error("\(errorMsg)")
        console.warn(errorMsg)
        if enableLogFile == true {
            logMessages.append(msg)
        }
    }
    func clear() {
        self.logMessages.removeAll()
    }
    func saveLogs(to: URL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Procyon.log.txt")) {
        if f.fileExists(atPath: to.path) {
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
