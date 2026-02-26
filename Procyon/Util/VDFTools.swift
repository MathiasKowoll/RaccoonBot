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
    // var dict: [String:Any] = [:]
    
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
        func isStringToken(_ index: Int) -> Bool {
          getStringToken(index) != nil
        }
        func isLBrace(_ index: Int) -> Bool {
          return tokens[index] == "{"
        }
        func isRBrace(_ index: Int) -> Bool {
          return tokens[index] == "}"
        }
        
        for i in tokens.indices {
            if(i % 2 == 0) { // process the tokens in pairs
              if(i > 1 && isStringToken(i) && isLBrace(i + 1) && openBrackets == 0){ //skip root key
                key = getStringToken(i)!
                openBrackets += 1
                sliceStart = i
              }
              if (
                (
                  i + 1 <  tokens.indices.count - 1) &&
                  isStringToken(i) &&
                  isStringToken(i + 1) &&
                  openBrackets == 0
                ) {
                let key = getStringToken(i)!
                let value = getStringToken(i + 1)!
                dict[key] = value
              }
            }
            if(openBrackets == 0 && key != nil) { // if the child object is closed
              sliceEnd = i + 1 // update the range
              dict[key!] = parse(Array(tokens[sliceStart..<sliceEnd])) // process the child obj (slice) recursively
              key = nil
            } else if(i < tokens.indices.count - 1 && isRBrace(i)) { //skip root closing bracket
              openBrackets -= 1
            }
            print("\(i % 2 == 0 ? "e": "o").\(i))\(tokens[i]) sl\(sliceStart)-\(sliceEnd) key=\(key ?? "") ob=\(openBrackets)")
        }
        return dict
    }
    return [tks[0]: parse(tks)]
}
