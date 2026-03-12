//
//  ACFTools.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import Foundation

enum VDFValue {
    case string(String)
    case object([String: VDFValue])
}

func parseVDFToDict(from file: String) -> [String: Any] {
    enum Token: Equatable { // need to be Equatable otherwise the check for the token type would be complicated
        case string(String)
        case openBrace
        case closeBrace
    }
    
    func getTokens() -> [Token] { // lexer
        let pattern = #/"([^"\n]*?)"|\{|\}/# // the string token is a capture group so it's in match.1
        let strippedComments = file.replacingOccurrences(of: "//.*?\n", with: "", options: .regularExpression, range: nil)
        return strippedComments.matches(of: pattern)
            .map { match in
                if let inner = match.1 { return .string(String(inner)) } // if quoted string return early with the string token
                switch match.0 {
                case "{": return .openBrace
                case "}": return .closeBrace
                default: fatalError("unexpected token: \(match.0)") // if it's not a string, { or } then we're in trouble
                }
            }
    }
    func getStringToken(from token: Token) -> String? {
        if case let .string(string) = token {
            return string
        }
        return nil
    }
    
    let tokens = getTokens()
    func getStringTokenForIndex(_ index: Int) -> String? {
        return getStringToken(from: tokens[index])
    }
    func isStringToken(_ index: Int) -> Bool {
        getStringTokenForIndex(index) != nil
    }
    func parse(at pointer: inout Int) -> [String: Any] {
        var dict: [String: Any] = [:]

        if(pointer > tokens.count - 1) { // if starts parsing after the last token, bail out
          return dict
        }

        while pointer < tokens.count {
            if(tokens[pointer] == .closeBrace) { // exit the recursion and continue from where you were before
                return dict
            }
            if(pointer + 1 < tokens.count) {
                let next = pointer + 1
                guard let key = getStringTokenForIndex(pointer) else {
                    return dict // first token should always be a string if not, bail out
                }
                if(isStringToken(next)) { // if next is another string then we have a key value case
                    let value = getStringTokenForIndex(next)
                    dict[key] = value
                    pointer = next + 1
                } else if(tokens[next] == .openBrace) { // if it's an open bracket we have a child node
                    pointer = next + 1
                    let childDict = parse(at: &pointer)
                    dict[key] = childDict
                    if(pointer + 1 < tokens.count) { // we're done with the child node, now proceed
                        pointer += 1
                    } else { // if the child node was sitting at the eof bail out
                        return dict
                    }
                }
            } else {
                return dict
            }
        }
        return dict
    }
    var startIndex = 0
    return parse(at: &startIndex)
}
