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
    
    func getTokens() -> [String] { // lexer
        let regex: Regex = /".*?"|\{|\}/
        return file.matches(of: regex)
            .compactMap { $0.0.description }
            .map { $0.replacingOccurrences(of: "\\", with: "/") }
    }
    
    let tks = getTokens()
    
    func parse(_ tokens: [String]) -> [String: Any] {
        var dict: [String: Any] = [:]
        var openBrackets: Int = 0
        var sliceStart = 0
        var sliceEnd = 0
        var key: String? = nil
        func getStringToken(_ index: Int) -> String? {
          let stringToken: Regex = /"(.*?)"$/
          return tokens[index].wholeMatch(of: stringToken)?.1.description
        }

        func isLBrace(_ index: Int) -> Bool {
          return tokens[index] == "{"
        }

        func isRBrace(_ index: Int) -> Bool {
          return tokens[index] == "}"
        }
        
        for i in tokens.indices {
            if(i % 2 == 0) {
              if(i > 1 && getStringToken(i) != nil && isLBrace(i + 1)){ // skip parent object
                key = getStringToken(i)!
                openBrackets += 1
                sliceStart = i
              }
              if (
                (
                  i + 1 < tokens.indices.count - 1) && // boundary
                  getStringToken(i) != nil && // first is key
                  getStringToken(i + 1) != nil && // second is value
                  openBrackets == 0 // it's inside the parent object
                ) {
                let key = getStringToken(i)!
                let value = getStringToken(i + 1)!
                dict[key] = value // then put this property in the parent object
              }
            }
            if(i < tokens.indices.count - 1  && isRBrace(i)) { // skip parent object
              openBrackets -= 1 // track closure
            }
            if(openBrackets == 0 && key != nil) { // calculate the range for the child Object
              sliceEnd = i + 1
              let partial = Array(tokens[sliceStart..<sliceEnd]) // recursively parse the child object
              dict[key!] = parse(partial)
              key = nil
            }
        }
        return dict
    }
    return [tks[0]: parse(tks)] // because we skipped the partent object property key we do it now
}
