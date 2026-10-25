// Makes numbered contact sheets of the downloaded photos, so each class can be checked by eye
// before training. Photos that don't show the landmark are listed in excluded.csv.
//
// Usage: swift contact_sheet.swift "Nine Arch Bridge"     (writes Sheets/<label>-1.png, -2.png...)

import AppKit
import Foundation

let here = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let label = CommandLine.arguments.dropFirst().first ?? "Other"
let folder = here.appending(path: "Raw/\(label)")
let output = here.appending(path: "Sheets")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

// Photos already on an earlier sheet keep their numbers; only new ones (e.g. after a top-up download) are shown
let indexURL = output.appending(path: "\(label)-index.csv")
let reviewed = ((try? String(contentsOf: indexURL, encoding: .utf8)) ?? "")
    .split(separator: "\n")
    .compactMap { $0.split(separator: ",").last.map(String.init) }
let firstNumber = reviewed.count
let files = try FileManager.default.contentsOfDirectory(atPath: folder.path)
    .filter { $0.hasSuffix(".jpg") && !reviewed.contains($0) }
    .sorted()
if files.isEmpty {
    print("Nothing new to review for \(label)")
    exit(0)
}

let columns = 8, rows = 6, cell = 200
let perSheet = columns * rows
let suffix = firstNumber == 0 ? "" : "-from\(firstNumber)"

for (sheetIndex, start) in stride(from: 0, to: files.count, by: perSheet).enumerated() {
    let page = Array(files[start..<min(start + perSheet, files.count)])
    let size = NSSize(width: columns * cell, height: rows * cell)
    let image = NSImage(size: size)
    image.lockFocus()
    NSColor.black.setFill()
    NSRect(origin: .zero, size: size).fill()

    for (offset, file) in page.enumerated() {
        let column = offset % columns
        let row = offset / columns
        let frame = NSRect(x: column * cell + 2, y: (rows - 1 - row) * cell + 2, width: cell - 4, height: cell - 4)
        if let photo = NSImage(contentsOf: folder.appending(path: file)) {
            // Fit the photo inside its square
            let scale = min(frame.width / photo.size.width, frame.height / photo.size.height)
            let fitted = NSSize(width: photo.size.width * scale, height: photo.size.height * scale)
            photo.draw(in: NSRect(x: frame.midX - fitted.width / 2, y: frame.midY - fitted.height / 2,
                                  width: fitted.width, height: fitted.height))
        }
        let number = "\(firstNumber + start + offset)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.boldSystemFont(ofSize: 22),
            .foregroundColor: NSColor.yellow,
            .backgroundColor: NSColor.black.withAlphaComponent(0.7),
        ]
        number.draw(at: NSPoint(x: frame.minX + 4, y: frame.maxY - 28), withAttributes: attributes)
    }
    image.unlockFocus()

    let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
    let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7])!
    let url = output.appending(path: "\(label)\(suffix)-\(sheetIndex + 1).jpg")
    try jpeg.write(to: url)
    print(url.path)
}

// Number -> file name, so numbers on the sheets can be turned into file names
let index = (reviewed + files).enumerated().map { "\($0.offset),\($0.element)" }.joined(separator: "\n")
try index.write(to: indexURL, atomically: true, encoding: .utf8)
