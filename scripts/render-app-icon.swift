#!/usr/bin/env swift
// Renders the Burn app icon (ember-squircle). Visual spec:
// docs/superpowers/specs/2026-05-24-naming-and-icon-design.md §3.

import AppKit
import CoreGraphics
import Foundation

// MARK: - CLI

guard CommandLine.arguments.count == 3,
      let size = Int(CommandLine.arguments[1]),
      size > 0, size <= 4096 else {
    FileHandle.standardError.write(Data("usage: render-app-icon.swift <pixel-size 1..4096> <output.png>\n".utf8))
    exit(2)
}
let outPath = CommandLine.arguments[2]

// MARK: - Helpers

func makeGradient(colors: [CGColor], locations: [CGFloat], colorSpace: CGColorSpace) -> CGGradient {
    guard let grad = CGGradient(colorsSpace: colorSpace, colors: colors as CFArray, locations: locations) else {
        FileHandle.standardError.write(Data("CGGradient alloc failed\n".utf8))
        exit(1)
    }
    return grad
}

// MARK: - Rendering

let dim = CGFloat(size)
let cornerRadius = dim * 0.225  // squircle ≈ 22.5 % of side

let colorSpace = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(
    data: nil,
    width: size, height: size,
    bitsPerComponent: 8, bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("CGContext alloc failed\n".utf8))
    exit(1)
}

// 1. Clip to squircle
let rect = CGRect(x: 0, y: 0, width: dim, height: dim)
let squirclePath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(squirclePath)
ctx.clip()

// 2. Dark glass base (linear gradient 160°: #1A0A26 → #0A0414)
let baseStart = CGPoint(x: dim * 0.13, y: dim * 0.95)   // 160° in CG-coords (y up)
let baseEnd   = CGPoint(x: dim * 0.87, y: dim * 0.05)
let baseGrad = makeGradient(colors: [
    CGColor(red: 0x1A/255.0, green: 0x0A/255.0, blue: 0x26/255.0, alpha: 1.0),
    CGColor(red: 0x0A/255.0, green: 0x04/255.0, blue: 0x14/255.0, alpha: 1.0)
], locations: [0, 1], colorSpace: colorSpace)
ctx.drawLinearGradient(baseGrad, start: baseStart, end: baseEnd, options: [])

// 3. Pink tint top-left — radial, center (0.18, 0.04), radius 0.58 of side, alpha .62 → 0
let pinkCenter = CGPoint(x: dim * 0.18, y: dim * (1 - 0.04))
let pinkGrad = makeGradient(colors: [
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.62),
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.0)
], locations: [0, 1], colorSpace: colorSpace)
ctx.drawRadialGradient(pinkGrad,
    startCenter: pinkCenter, startRadius: 0,
    endCenter:   pinkCenter, endRadius:   dim * 0.58,
    options: [])

// 4. Cyan tint bottom-right — radial, center (1.0, 1.0), radius 0.70, alpha .50 → 0
let cyanCenter = CGPoint(x: dim, y: 0)
let cyanGrad = makeGradient(colors: [
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.50),
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.0)
], locations: [0, 1], colorSpace: colorSpace)
ctx.drawRadialGradient(cyanGrad,
    startCenter: cyanCenter, startRadius: 0,
    endCenter:   cyanCenter, endRadius:   dim * 0.70,
    options: [])

// 5. Ambient bloom on the glass (outside ember core): pink + cyan
let bloomCenter = CGPoint(x: dim * 0.5, y: dim * 0.5)
let pinkBloom = makeGradient(colors: [
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.55),
    CGColor(red: 1.0, green: 45/255.0, blue: 109/255.0, alpha: 0.0)
], locations: [0, 1], colorSpace: colorSpace)
ctx.drawRadialGradient(pinkBloom,
    startCenter: bloomCenter, startRadius: dim * 0.26,
    endCenter:   bloomCenter, endRadius:   dim * 0.50,
    options: [])
let cyanBloom = makeGradient(colors: [
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.35),
    CGColor(red: 0.0, green: 184/255.0, blue: 230/255.0, alpha: 0.0)
], locations: [0, 1], colorSpace: colorSpace)
ctx.drawRadialGradient(cyanBloom,
    startCenter: bloomCenter, startRadius: dim * 0.28,
    endCenter:   bloomCenter, endRadius:   dim * 0.58,
    options: [])

// 6. Ember core — sphere with highlight at (0.36, 0.30 relative to ember bounds)
let emberR = dim * 0.26  // radius — diameter ≈ 52% of side
let emberCenter = CGPoint(x: dim * 0.5, y: dim * 0.5)
let highlight = CGPoint(
    x: emberCenter.x + (0.36 - 0.5) * emberR * 2,
    y: emberCenter.y + (0.5 - 0.30) * emberR * 2  // CG y-up: 0.30 from top → above center
)

let emberColors: [CGColor] = [
    CGColor(red: 1.0,        green: 1.0,        blue: 1.0,        alpha: 1.0),  // 0%
    CGColor(red: 1.0,        green: 0xE1/255.0, blue: 0xEC/255.0, alpha: 1.0),  // 6%
    CGColor(red: 1.0,        green: 0x9B/255.0, blue: 0xC1/255.0, alpha: 1.0),  // 16%
    CGColor(red: 1.0,        green: 0x5F/255.0, blue: 0xA0/255.0, alpha: 1.0),  // 32%
    CGColor(red: 1.0,        green: 0x2D/255.0, blue: 0x6D/255.0, alpha: 1.0),  // 52%
    CGColor(red: 0xC0/255.0, green: 0x15/255.0, blue: 0x58/255.0, alpha: 1.0),  // 78%
    CGColor(red: 0x5D/255.0, green: 0x08/255.0, blue: 0x24/255.0, alpha: 1.0),  // 100%
]
let emberLocs: [CGFloat] = [0.00, 0.06, 0.16, 0.32, 0.52, 0.78, 1.00]
let emberGrad = makeGradient(colors: emberColors, locations: emberLocs, colorSpace: colorSpace)
ctx.drawRadialGradient(emberGrad,
    startCenter: highlight, startRadius: 0,
    endCenter:   emberCenter, endRadius: emberR,
    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

// 7. Hairline inner stroke on ember (subtle 1px white @10%)
ctx.setStrokeColor(CGColor(gray: 1.0, alpha: 0.10))
ctx.setLineWidth(max(0.5, dim / 1024.0))
ctx.strokeEllipse(in: CGRect(
    x: emberCenter.x - emberR, y: emberCenter.y - emberR,
    width: emberR * 2, height: emberR * 2))

// MARK: - Write PNG

guard let cgImage = ctx.makeImage() else {
    FileHandle.standardError.write(Data("ctx.makeImage() failed\n".utf8))
    exit(1)
}
let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: dim, height: dim))
guard let tiff = nsImage.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("PNG encode failed\n".utf8))
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
} catch {
    FileHandle.standardError.write(Data("write failed: \(error.localizedDescription)\n".utf8))
    exit(1)
}
print("wrote \(outPath) (\(size)×\(size))")
