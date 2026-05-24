import XCTest
import AppKit

final class MiniEmberRenderTests: XCTestCase {
    func test_renderScript_produces128pxPNG_withEmberAtCenterAndDarkCorner() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("burn-icon-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // Find repo root from test bundle — climb until we find scripts/render-app-icon.swift.
        var dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        while !FileManager.default.fileExists(atPath: dir.appendingPathComponent("scripts/render-app-icon.swift").path) {
            let parent = dir.deletingLastPathComponent()
            if parent == dir {
                XCTFail("repo root not found (started from \(URL(fileURLWithPath: #filePath).deletingLastPathComponent().path))")
                return
            }
            dir = parent
        }
        let scriptURL = dir.appendingPathComponent("scripts/render-app-icon.swift")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["swift", scriptURL.path, "128", tmp.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "render-app-icon.swift exited non-zero")

        // Verify PNG is valid 128×128
        guard let image = NSImage(contentsOf: tmp),
              let rep = image.representations.first as? NSBitmapImageRep else {
            XCTFail("output is not a valid image")
            return
        }
        XCTAssertEqual(rep.pixelsWide, 128)
        XCTAssertEqual(rep.pixelsHigh, 128)

        // Ember highlight pixel (white-pink core).
        // CG renders y-up; the highlight offset is (-14%, +20%) from ember center.
        // At 128px: CG-x ≈ 55, CG-y ≈ 77 → NSBitmapImageRep y-down: (55, 128-77)=(55,51).
        // Empirically the brightest sample is at (54, 50) — verified against actual output.
        guard let center = rep.colorAt(x: 54, y: 50) else {
            XCTFail("colorAt(54, 50) returned nil")
            return
        }
        XCTAssertGreaterThan(center.redComponent,   0.85, "ember highlight should be bright")
        XCTAssertGreaterThan(center.greenComponent, 0.50, "ember highlight has white component")

        // Interior glass pixel (dark base gradient, away from ember core).
        // (16, 16) in NSBitmapImageRep y-down is well inside the squircle and far from the ember.
        // Verified sum ≈ 0.71 against actual output.
        guard let corner = rep.colorAt(x: 16, y: 16) else {
            XCTFail("colorAt(16, 16) returned nil")
            return
        }
        XCTAssertLessThan(corner.redComponent + corner.greenComponent + corner.blueComponent, 1.6,
            "glass background should be dark")
    }
}
