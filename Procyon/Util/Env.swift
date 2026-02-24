//
//  Env.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//


internal import Foundation
func toCrossoverENVString(_ key: String, _ value: String) -> String {
    return "\"\(key)\"=\"\(value)\""
}

func parseCXEnvVarString(_ string: String) -> (String, String){
    // "KEY"="VALUE"
    // e.g.: "CX_BOTTLE_PATH"="/Users/${USER}/CXPBottles"
    let regex = /\"(\w+?)\"\=\"(.+?)\"/
    var key = ""
    var value = ""
    do {
        let match = try regex.firstMatch(in: string)
        key = match?.1.description ?? ""
        value = match?.2.description ?? ""
    } catch {
        console.error("parseCXEnvVarString: \(error.localizedDescription)")
    }
    return (key, value)
}
