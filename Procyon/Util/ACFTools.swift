//
//  ACFTools.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//


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
