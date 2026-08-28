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
    /// Set from the switch and from the environment. Starts wherever the
    /// application starts, and follows the switch after that.
    var enableLogFile: Bool = debugLoggingEnabled
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
    /// Where the log is written.
    ///
    /// `RaccoonBotLogPath` decides it when set -- a directory, or a full file
    /// name if you want to choose that too. Otherwise it goes beside the
    /// application, which is where you look for it while developing.
    ///
    /// Except from /Applications, which is not a place to leave a text file
    /// and is not writable without an administrator. Installed copies write
    /// into Application Support instead. Anywhere else that turns out not to
    /// be writable falls back the same way rather than failing quietly.
    static let logPathVariable = "RaccoonBotLogPath"
    static let logFileName = "RaccoonBot.log.txt"

    static var defaultLogDirectory: URL {
        let f = FileManager.default
        let support = f.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RaccoonBot")
        let beside = Bundle.main.bundleURL.deletingLastPathComponent()
        let path = beside.path(percentEncoded: false)
        if path == "/Applications" || path.hasPrefix("/Applications/") { return support }
        return f.isWritableFile(atPath: path) ? beside : support
    }

    static var logURL: URL {
        let f = FileManager.default
        if let raw = ProcessInfo.processInfo.environment[logPathVariable],
           !raw.trimmingCharacters(in: .whitespaces).isEmpty {
            let expanded = (raw as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if f.fileExists(atPath: expanded, isDirectory: &isDirectory), isDirectory.boolValue {
                return URL(fileURLWithPath: expanded).appendingPathComponent(logFileName)
            }
            // Not there yet: a trailing slash is the only thing that says
            // whether a name was meant as a directory or as the file itself.
            if expanded.hasSuffix("/") {
                return URL(fileURLWithPath: expanded).appendingPathComponent(logFileName)
            }
            return URL(fileURLWithPath: expanded)
        }
        return defaultLogDirectory.appendingPathComponent(logFileName)
    }

    func saveLogs(to: URL? = nil) {
        let target = to ?? Console.logURL
        do {
            try f.createDirectory(at: target.deletingLastPathComponent(),
                                  withIntermediateDirectories: true)
        } catch {
            console.error("Could not make \(target.deletingLastPathComponent().path(percentEncoded: false)): \(error.localizedDescription)")
            return
        }
        if f.fileExists(atPath: target.path(percentEncoded: false)) {
            do { try f.removeItem(at: target) }
            catch { console.error(String(reflecting: error)) }
        }
        let content = logMessages.joined(separator: "\n")
        console.warn("Saving logs to \(target.path(percentEncoded: false))")
        do {
            try content.write(to: target, atomically: true, encoding: .utf8)
        } catch {
            console.error(String(reflecting: error))
        }
    }}

let console = Console()

