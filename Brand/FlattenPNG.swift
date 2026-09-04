#!/usr/bin/env swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: FlattenPNG.swift input.png output.png\n", stderr)
    exit(64)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard
    let source = CGImageSourceCreateWithURL(inputURL as CFURL, nil),
    let input = CGImageSourceCreateImageAtIndex(source, 0, nil),
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
    let context = CGContext(
        data: nil,
        width: input.width,
        height: input.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    )
else {
    fputs("Could not create an RGB image context.\n", stderr)
    exit(1)
}

context.setFillColor(CGColor(red: 14.0 / 255.0, green: 22.0 / 255.0, blue: 32.0 / 255.0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: input.width, height: input.height))
context.draw(input, in: CGRect(x: 0, y: 0, width: input.width, height: input.height))

guard
    let flattened = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    )
else {
    fputs("Could not create the PNG destination.\n", stderr)
    exit(1)
}

CGImageDestinationAddImage(destination, flattened, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Could not finalize the PNG.\n", stderr)
    exit(1)
}
