//
//  ACFTools.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//


import Foundation

func parseACFToDict(from file: String) -> [String:Any] {
    return parseVDFToDict(from: file)
}

func parseVDFToDict(from file: String) -> [String:Any] {
    /**
     more comprehensive parser (to replace the one above)
     parses an VDF file content String into a dictionary
     TO DO: Refactor and made the parser logic less brittle
     */
    
    func getTokens() -> [String] { // lexer
        let regex: Regex = /".*?"|\{|\}/
        return file.matches(of: regex)
            .compactMap { $0.0.description }
            .map { $0.replacingOccurrences(of: "\\", with: "/") }
    }
    
    let tks = getTokens()
    
    func getStringToken(from token: String) -> String? {
        let stringToken: Regex = /"(.*?)"$/
        return token.wholeMatch(of: stringToken)?.1.description
    }
    
    func parse(_ tokens: [String]) -> [String: Any] {
        var dict: [String: Any] = [:]
        var openBrackets: Int = 0
        var sliceStart = 0
        var sliceEnd = 0
        var childObjKey: String? = nil
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
        
        for i in tokens.indices {
            if(i % 2 == 0) { // process the tokens in pairs
                if(
                    i > 1 && //skip root key
                    isStringToken(i) &&
                    isLBrace(i + 1) && // if it's a string token followed by an open bracket then it's a child object
                    openBrackets == 0 // not nested in other child objects
                ){
                    childObjKey = getStringTokenForIndex(i)! // assign the key for later use
                    openBrackets += 1 // begin to track the child object
                    sliceStart = i // begin to track the child object
                }
                if (
                    (i < tokens.indices.count) && // array boundary constraint
                    isStringToken(i) && // key is a string token
                    isStringToken(i + 1) && // value is a string token
                    openBrackets == 0 // skip if inside a nested obj, will be processed recursively instead
                ) {
                    let key = getStringTokenForIndex(i)!
                    let value = getStringTokenForIndex(i + 1)!
                    dict[key] = value // update the parent objeect string values
                }
            }
            if(openBrackets == 0 && childObjKey != nil) { // if the child object is closed and a key is assigned
                sliceEnd = i + 1 // update the range
                dict[childObjKey!] = parse(Array(tokens[sliceStart..<sliceEnd])) // process the child obj (slice) recursively
                childObjKey = nil
            } else if(i < tokens.indices.count - 1 && isRBrace(i)) { //skip root closing bracket
                openBrackets -= 1 // will continue until all the brackets are balanced (optimistic)
            }
        }
        return dict
    }
    return [getStringToken(from: tks[0])!: parse(tks)]
}
