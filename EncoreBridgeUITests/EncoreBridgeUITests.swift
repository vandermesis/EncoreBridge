//
//  EncoreBridgeUITests.swift
//  EncoreBridgeUITests
//
//  Created by Marek Skrzelowski on 15/11/2026.
//

import XCTest
import AVFoundation
import AppKit

final class EncoreBridgeUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testOptionsMenuAndPanelLifecycle() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        XCTAssertFalse(app.windows["EncoreBridge — Logs"].exists)
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "playbackPanel").firstMatch.exists)
        for _ in 0..<2 {
            openActions(app)
            let item = app.statusItems["EncoreBridgeStatusItem"]
            let menu = app.menus.containing(.menuItem, identifier: "Show Logs").firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 5))
            print("ACTIONS_MENU_GEOMETRY", menu.frame, "STATUS_ITEM_GEOMETRY", item.frame)
            XCTAssertFalse(item.frame.isEmpty)
            XCTAssertFalse(menu.frame.isEmpty)
            XCTAssertTrue(menu.isHittable)
            XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "playbackPanel").firstMatch.exists)
            XCTAssertFalse(app.windows["EncoreBridge — Logs"].exists)
            XCTAssertGreaterThanOrEqual(menu.frame.minY, item.frame.maxY,
                                       "Actions menu must open below the menu bar: \(menu.frame), status item: \(item.frame)")
            for (index, screen) in XCUIScreen.screens.enumerated() {
                let attachment = XCTAttachment(screenshot: screen.screenshot())
                attachment.name = "Actions Below Menu Bar — Screen \(index)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            app.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(menu.waitForNonExistence(timeout: 3))
            let panel = app.descendants(matching: .any).matching(identifier: "playbackPanel").firstMatch
            if panel.exists {
                item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
            XCTAssertTrue(panel.waitForNonExistence(timeout: 3))
        }
    }

    @MainActor
    func testMonitoringControls() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }

        openPanel(app)
        keepScreenshot(app, name: "Now Playing")
        XCTAssertFalse(app.buttons["Copy Logs"].exists)
        XCTAssertFalse(app.staticTexts["Nasłuchiwanie Apple Music"].exists)
        XCTAssertEqual(NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == "EncoreBridge" })?.activationPolicy, .accessory)

        openActions(app)
        XCTAssertTrue(app.menuItems["Show Logs"].exists)
        XCTAssertTrue(app.menuItems["Copy Logs"].exists)
        XCTAssertTrue(app.menuItems["Close"].exists)
        keepScreenshot(app, name: "Context Menu")
        app.menuItems["Stop Monitoring"].click()
        openActions(app)
        XCTAssertTrue(app.menuItems["Start Monitoring"].waitForExistence(timeout: 5))
        app.menuItems["Start Monitoring"].click()
        openActions(app)
        XCTAssertTrue(app.menuItems["Stop Monitoring"].waitForExistence(timeout: 5))
        app.menuItems["Show Logs"].click()
        XCTAssertTrue(app.staticTexts["Ostatnie 10 wpisów"].waitForExistence(timeout: 5))
        keepScreenshot(app, name: "Recent Logs")
        app.buttons["Copy Logs"].click()
        let logs = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        XCTAssertTrue(logs.contains("APPLE_MUSIC_PLAYBACK ") && logs.contains("ROON_PLAYBACK "))
        XCTAssertTrue(logs.contains("APPLE_MUSIC_AUDIO_FORMAT ") && logs.contains("ROON_AUDIO_FORMAT "))
        XCTAssertTrue(logs.contains("Monitoring zatrzymany"))
        openActions(app)
        XCTAssertTrue(app.menuItems["Close"].exists)
    }

    @MainActor
    func testRoonPanelMatchesLiveSourceFileWhenAvailable() throws {
        let app = XCUIApplication()
        app.launch()
        defer { app.terminate() }
        openActions(app)
        app.menuItems["Copy Logs"].click()
        let logs = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
        print("ROON_UI_SNAPSHOT", logs.components(separatedBy: "\n\n").first ?? logs)
        try XCTSkipUnless(logs.contains("\nROON_PLAYING true\n"), "SHD ROON is not currently playing.")
        let firstLine = try XCTUnwrap(logs.components(separatedBy: .newlines).first { $0.hasPrefix("ROON_PLAYBACK ") })
        let data = Data(firstLine.dropFirst("ROON_PLAYBACK ".count).utf8)
        let playback = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let title = try XCTUnwrap(playback["title"] as? String)
        let artist = try XCTUnwrap(playback["artist"] as? String)
        let id = try XCTUnwrap(playback["id"] as? String)
        let prefix = "roon:SHD ROON:"
        let path = String(id.dropFirst(prefix.count))
        try XCTSkipUnless(id.hasPrefix(prefix) && path.hasPrefix("/"), "The current Roon source has no local reference file.")
        let referenceFile = try AVAudioFile(forReading: URL(filePath: path))
        let reference = referenceFile.fileFormat.streamDescription.pointee
        try XCTSkipUnless(reference.mFormatID == kAudioFormatAppleLossless, "This source comparison uses an ALAC reference.")
        let depth = try XCTUnwrap([1: 16, 2: 20, 3: 24, 4: 32][Int(reference.mFormatFlags)])
        openPanel(app)
        let track = app.staticTexts["currentTrack.roon"]
        XCTAssertTrue(track.label == title || track.value as? String == title, app.debugDescription)
        let artistField = app.staticTexts["currentArtist.roon"]
        XCTAssertTrue(artistField.label == artist || artistField.value as? String == artist, app.debugDescription)
        let section = app.descendants(matching: .any).matching(identifier: "playbackSource.roon").firstMatch
        XCTAssertTrue(section.staticTexts["ALAC"].exists)
        XCTAssertTrue(section.staticTexts["\(depth)-bit"].exists)
        XCTAssertTrue(section.staticTexts[String(format: "%g kHz", reference.mSampleRate / 1000)].exists)
        let evidence = XCTAttachment(string: logs)
        evidence.name = "Roon live source comparison"
        evidence.lifetime = .keepAlways
        add(evidence)
    }

    @MainActor
    func testLiveMusicFormats() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["ENCOREBRIDGE_LIVE_MUSIC"] == "1",
            "Set TEST_RUNNER_ENCOREBRIDGE_LIVE_MUSIC=1 to test the local Music session."
        )

        let app = XCUIApplication()
        let music = XCUIApplication(bundleIdentifier: "com.apple.Music")
        app.launch()
        defer { app.terminate() }

        let allCases = [
            ("Hi-Res Lossless Audio", "Dancing in the Dark"),
            ("Hi-Res Lossless Audio", "Skyfall"),
            ("Hi-Res Lossless Audio", "Kaleidoscope Heart"),
            ("Hi-Res Lossless Audio", "Salute to the Sun"),
            ("Hi-Res Lossless Audio", "Always on My Mind"),
            ("Hi-Res Lossless Audio", "The Girl from Ipanema"),
            ("Hi-Res Lossless Audio", "So What"),
            ("Fahrenheit Project Full Discography", "Devotion (intro)"),
            ("Odsłuch", "Maria Awaria"),
            ("Fahrenheit Project Full Discography", "L'Ivresse des profondeurs"),
            ("Radiohead", "Creep"),
            ("Radiohead", "Everything in Its Right Place"),
            ("SOHN Singles", "Oblivion"),
            ("Hi-Res Lossless Audio", "Dancing in the Dark"),
            ("Songs", "The Lost Jungle of Booshi")
        ]
        let cases: [(String, String)]
        if ProcessInfo.processInfo.environment["ENCOREBRIDGE_E2E_DRM"] == "1" { cases = [allCases.last!] }
        else if ProcessInfo.processInfo.environment["ENCOREBRIDGE_E2E_QUICK"] == "1" { cases = Array(allCases.prefix(2)) }
        else if ProcessInfo.processInfo.environment["ENCOREBRIDGE_E2E_RESUME"] == "1" { cases = Array(allCases.suffix(5)) }
        else if ProcessInfo.processInfo.environment["ENCOREBRIDGE_E2E_FINISH"] == "1" { cases = Array(allCases.suffix(3)) }
        else { cases = allCases }
        for (playlistName, title) in cases {
            music.activate()
            let playlist = music.outlines.staticTexts.matching(
                NSPredicate(format: "value == %@", playlistName)
            ).firstMatch
            XCTAssertTrue(playlist.waitForExistence(timeout: 5), playlistName)
            playlist.click()
            let track: XCUIElement
            if playlistName == "Songs" {
                let filter = music.searchFields["filterField"]
                XCTAssertTrue(filter.waitForExistence(timeout: 5))
                filter.click()
                filter.typeKey("a", modifierFlags: .command)
                filter.typeText(title)
                track = music.outlines.matching(NSPredicate(format: "label == 'Music'")).outlineRows.firstMatch
            } else {
                track = music.tables["trackTable"].staticTexts.matching(
                    NSPredicate(format: "value == %@ OR value BEGINSWITH %@", title, title + " ")
                ).firstMatch
            }
            // Music remembers navigation into albums/artists separately for each playlist.
            // Return to the playlist's root instead of treating that remembered view as a failure.
            for _ in 0..<5 {
                if track.waitForExistence(timeout: 1) { break }
                music.typeKey("[", modifierFlags: .command)
            }
            XCTAssertTrue(track.waitForExistence(timeout: 5), title)
            track.doubleClick()

            let playingTitle = music.descendants(matching: .any)
                .matching(identifier: "Music.miniPlayer.metadataRegion[state=populated]")
                .descendants(matching: .any).matching(NSPredicate(format: "label == %@ OR label BEGINSWITH %@", title, title + " ")).firstMatch
            XCTAssertTrue(playingTitle.waitForExistence(timeout: 15), title)
            openPanel(app)
            let titleField = app.staticTexts["currentTrack.appleMusic"]
            let correctTrack = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                titleField.label.contains(title) || (titleField.value as? String)?.contains(title) == true
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [correctTrack], timeout: 10), .completed, "Wrong current track: " + title)
            openActions(app)
            app.menuItems["Copy Logs"].click()
            openPanel(app)
            let diagnostic = try XCTUnwrap(NSPasteboard.general.string(forType: .string))
            XCTAssertTrue(diagnostic.contains("QUALITY_ACCESS true"), "EncoreBridge still lacks Accessibility access: " + diagnostic.prefix(500))
            let firstLine = try XCTUnwrap(diagnostic.components(separatedBy: .newlines).first { $0.hasPrefix("APPLE_MUSIC_PLAYBACK ") })
            let json = Data(firstLine.dropFirst("APPLE_MUSIC_PLAYBACK ".count).utf8)
            let playback = try XCTUnwrap(JSONSerialization.jsonObject(with: json) as? [String: Any])
            XCTAssertEqual(playback["title"] as? String, title)

            let sourceLabel: String
            if let filePath = playback["fileURL"] as? String, let url = URL(string: filePath) {
                if url.pathExtension == "movpkg" {
                    // The reference is the downloaded HLS rendition, not a listed alternative.
                    let document = try XMLDocument(contentsOf: url.appending(path: "boot.xml"))
                    let streams = try document.nodes(forXPath: "//*[local-name()='Stream'][*[local-name()='Complete']='YES']")
                    XCTAssertEqual(streams.count, 1)
                    let stream = try XCTUnwrap(streams.first as? XMLElement)
                    let variant = try XCTUnwrap(stream.attribute(forName: "UniqueTag")?.stringValue)
                    let playlists = try FileManager.default.contentsOfDirectory(at: url.appending(path: "Data"), includingPropertiesForKeys: nil).filter { $0.pathExtension == "m3u8" }
                    let lines = try playlists.flatMap { try String(contentsOf: $0, encoding: .utf8).components(separatedBy: .newlines) }
                    let rendition = try XCTUnwrap(lines.first { $0.hasPrefix("#EXT-X-STREAM-INF:") && $0.contains("STABLE-VARIANT-ID=\"" + variant + "\"") })
                    let regex = try NSRegularExpression(pattern: #"AUDIO="audio-alac-stereo-([0-9]+)-([0-9]+)""#)
                    let match = try XCTUnwrap(regex.firstMatch(in: rendition, range: NSRange(rendition.startIndex..., in: rendition)))
                    let rate = try XCTUnwrap(Range(match.range(at: 1), in: rendition))
                    let bits = try XCTUnwrap(Range(match.range(at: 2), in: rendition))
                    let hertz = try XCTUnwrap(Double(rendition[rate]))
                    sourceLabel = String(rendition[bits]) + "-bit " + String(format: "%g", hertz / 1000) + " kHz ALAC (downloaded DRM manifest)"
                } else {
                let file = try AVAudioFile(forReading: url)
                let description = file.fileFormat.streamDescription.pointee
                let codec: String
                switch description.mFormatID {
                case kAudioFormatAppleLossless: codec = "ALAC"
                case kAudioFormatMPEG4AAC: codec = "AAC"
                case kAudioFormatMPEGLayer3: codec = "MP3"
                case kAudioFormatFLAC: codec = "FLAC"
                default: codec = url.pathExtension.uppercased()
                }
                let bits = description.mFormatID == kAudioFormatAppleLossless
                    ? [1: 16, 2: 20, 3: 24, 4: 32][Int(description.mFormatFlags)]
                    : (description.mBitsPerChannel > 0 ? Int(description.mBitsPerChannel) : nil)
                sourceLabel = (bits.map { "\($0)-bit " } ?? "") + String(format: "%g", description.mSampleRate / 1000) + " kHz " + codec + " (file)"
                }
            } else {
                music.activate()
                let badge = music.buttons["Music.miniPlayer.audioBadge"]
                XCTAssertTrue(badge.waitForExistence(timeout: 8), title + ": no local file or quality badge")
                badge.click()
                let sourceFormat = music.popovers.staticTexts.matching(
                    NSPredicate(format: "label CONTAINS[c] 'kHz' OR value CONTAINS[c] 'kHz'")
                ).firstMatch
                XCTAssertTrue(sourceFormat.waitForExistence(timeout: 10))
                sourceLabel = sourceFormat.value as? String ?? sourceFormat.label
                music.typeKey(.escape, modifierFlags: [])
            }
            let expression = try NSRegularExpression(pattern: #"([0-9]+(?:[.,][0-9]+)?)\s*kHz"#)
            let match = try XCTUnwrap(expression.firstMatch(in: sourceLabel, range: NSRange(sourceLabel.startIndex..., in: sourceLabel)))
            let rateRange = try XCTUnwrap(Range(match.range(at: 1), in: sourceLabel))
            let expectedRate = sourceLabel[rateRange].replacingOccurrences(of: ",", with: ".") + " kHz"
            let codec = try XCTUnwrap(["ALAC", "AAC", "MP3", "FLAC", "WAV", "AIFF"].first { sourceLabel.contains($0) })
            openPanel(app)
            continueAfterFailure = true
            let section = app.descendants(matching: .any).matching(identifier: "playbackSource.appleMusic").firstMatch
            XCTAssertTrue(section.staticTexts[expectedRate].waitForExistence(timeout: 10), title + ": " + sourceLabel)
            XCTAssertTrue(section.staticTexts[codec].waitForExistence(timeout: 10), title + ": missing/wrong codec, " + sourceLabel)
            let depthRegex = try NSRegularExpression(pattern: #"(16|20|24|32)-bit"#)
            if let depth = depthRegex.firstMatch(in: sourceLabel, range: NSRange(sourceLabel.startIndex..., in: sourceLabel)),
               let range = Range(depth.range, in: sourceLabel) {
                XCTAssertTrue(section.staticTexts[String(sourceLabel[range])].waitForExistence(timeout: 10), title + ": wrong bit depth, " + sourceLabel)
            }
            let evidence = XCTAttachment(string: "\(playlistName) / \(title): source = \(sourceLabel)\n\(diagnostic)\n\(app.debugDescription)")
            evidence.name = playlistName + " - " + title
            evidence.lifetime = .keepAlways
            add(evidence)
            print("E2E_OBSERVED", playlistName, title, sourceLabel)
            continueAfterFailure = false
        }
    }

    @MainActor
    private func keepScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func openActions(_ app: XCUIApplication) {
        openPanel(app)
        let options = app.descendants(matching: .any).matching(identifier: "optionsMenu").firstMatch
        XCTAssertTrue(options.waitForExistence(timeout: 5), app.debugDescription)
        options.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(app.menuItems["Show Logs"].waitForExistence(timeout: 5), app.debugDescription)
    }

    @MainActor
    private func openPanel(_ app: XCUIApplication) {
        let item = app.statusItems["EncoreBridgeStatusItem"]
        for _ in 0..<2 {
            if app.descendants(matching: .any).matching(identifier: "playbackPanel").firstMatch.waitForExistence(timeout: 1) { return }
            XCTAssertTrue(item.waitForExistence(timeout: 3))
            item.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            if app.descendants(matching: .any).matching(identifier: "playbackPanel").firstMatch.waitForExistence(timeout: 4) { return }
        }
        XCTFail("EncoreBridge panel did not open: " + app.debugDescription)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
