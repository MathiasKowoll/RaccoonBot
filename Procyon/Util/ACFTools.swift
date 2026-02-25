//
//  ACFTools.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//


internal import Foundation

func parseACFToDict(from: String) -> [String:String] {
    /**
     Incomplete shallow parser that the skips main property
     parses an ACF file content String into a dictionary
     */
    var dictionary: [String:String] = [:]
    let search1: Regex = /(("\w+?")\n\{\n(.*?\n)+\})+/
    let search2: Regex = /(\t"(\w+?)"\t+"(.*?)")\n(?=\t"\w+")/
    
    let matches = from.matches(of: search1)
    for match in matches {
        let values = match.0.matches(of: search2)
        for value in values {
            dictionary[value.2.description] = value.3.description
        }
    }
    return dictionary
}

func parseVDFToDict(from file: String) -> [String:Any] {
    /**
     more comprehensive parser (to replace the one above)
     parses an VDF file content String into a dictionary
     */
    var parentDictionary: [String:Any] = [:]
    var dictionary: [String:Any] = [:]
    
    func getTokens() -> [String] { // lexer
        let regex: Regex = /".*?"|\{|\}/
        return file.matches(of: regex)
            .compactMap { $0.0.description }
            .map { $0.replacingOccurrences(of: "\\", with: "/") }
        + ["EOF"]
    }
    
    let tokens = getTokens()
    
    func parse(_ tokens: [String]) -> [String:Any] {
        var dict: [String:Any] = [:]
        let stringToken: Regex = /^STRING\((.*?)\)$/
        for index in tokens.indices {
            
        }
        return dict
    }
    
    print(tokens)
    
    return dictionary
}

