//
//  UI.swift
//  Procyon
//
//  Created by Italo Mandara on 24/02/2026.
//

import UniformTypeIdentifiers
import AppKit

func openFolderSelectorPanel(type: UTType = .folder, initialDirectory: URL? = nil, title: String? = nil) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title ?? (type == .folder ? "Select a folder" : "Select a file");
    panel.allowsMultipleSelection = false;
    panel.canChooseDirectories = true;
    panel.allowedContentTypes = [type]
    if let initialDirectory {
        panel.directoryURL = initialDirectory
    }
    return panel.runModal() == .OK ? panel.url?.absoluteURL : nil
}
