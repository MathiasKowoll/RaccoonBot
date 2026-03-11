//
//  ACFTools.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//


import Foundation

func parseACFToDict(from file: String) -> [String: Any] {
    return parseVDFToDict(from: file)
}

func parseVDFToDict(from file: String) -> [String: Any] {
    /**
     * New Refactored parser
     */
    
    func getTokens() -> [String] { // lexer
        let pattern = #/"[^"]*"|\{|\}/#
        return file.matches(of: pattern)
            .compactMap { $0.0.description }
    }
    
    let tks = getTokens()
    
    func getStringToken(from token: String) -> String? {
        let stringToken: Regex = /"(.*?)"$/
        return token.wholeMatch(of: stringToken)?.1.description
    }

    func parse(_ tokens: [String], _ index: Int = 0) -> ([String: Any], Int) {
        var pointer = index

        var dict: [String: Any] = [:]

        if(pointer >= tokens.count - 1) {
          print("EOF")
          return (dict, tokens.count - 1)
        }
        
        func getStringTokenForIndex(_ index: Int) -> String? {
            return getStringToken(from: tokens[index])
        }
        func isStringToken(_ index: Int) -> Bool {
            getStringTokenForIndex(index) != nil
        }
        func isLBrace(_ index: Int) -> Bool {
            return tokens[index] == "{"
        }
        func isRBrace(_ index: Int) -> Bool {
            return tokens[index] == "}"
        }

        while pointer < tokens.count {
          if(pointer + 1 < tokens.count) {
            let next = pointer+1
            let key = getStringTokenForIndex(pointer)
            if(isStringToken(pointer) && isStringToken(next) && key != nil) {
              let value = getStringTokenForIndex(next)!
              dict[key!] = value
              pointer = next + 1
            } else if(isStringToken(pointer) && isLBrace(next)) {
              pointer = next + 1
              let (d, p) = parse(tokens, pointer)
              dict[key!] = d
              if(p + 1 < tokens.count) {
                pointer = p + 1
              } else {
                return (dict, tokens.count - 1)
              }
            }
            if(isRBrace(pointer)) {
              return (dict, pointer)
            }
          }
        }
        return (dict, pointer)
    }
    return parse(tks).0
}
