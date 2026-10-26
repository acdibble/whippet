import CoreGraphics
import Testing

struct WindowLayoutTests {
    /// A 1440 × 875 visible area above a 25-point Dock, and a window somewhere on it.
    private let screen = CGRect(x: 0, y: 25, width: 1440, height: 875)
    private let window = CGRect(x: 100, y: 200, width: 800, height: 500)

    private func frame(_ command: WindowCommand, window: CGRect? = nil, screen: CGRect? = nil, next: CGRect? = nil) -> CGRect? {
        WindowLayout.frame(for: command, window: window ?? self.window, screen: screen ?? self.screen, nextScreen: next)
    }

    @Test func halvesSplitTheVisibleArea() {
        #expect(frame(.leftHalf) == CGRect(x: 0, y: 25, width: 720, height: 875))
        #expect(frame(.rightHalf) == CGRect(x: 720, y: 25, width: 720, height: 875))
        // AppKit's y grows upwards, so the top half sits higher.
        #expect(frame(.topHalf) == CGRect(x: 0, y: 463, width: 1440, height: 437))
        #expect(frame(.bottomHalf) == CGRect(x: 0, y: 25, width: 1440, height: 438))
    }

    @Test func thirdsRunAcrossALandscapeScreen() {
        #expect(frame(.firstThird) == CGRect(x: 0, y: 25, width: 480, height: 875))
        #expect(frame(.centerThird) == CGRect(x: 480, y: 25, width: 480, height: 875))
        #expect(frame(.lastThird) == CGRect(x: 960, y: 25, width: 480, height: 875))
        #expect(frame(.firstTwoThirds) == CGRect(x: 0, y: 25, width: 960, height: 875))
        #expect(frame(.lastTwoThirds) == CGRect(x: 480, y: 25, width: 960, height: 875))
    }

    @Test func thirdsRunDownAPortraitScreen() {
        let portrait = CGRect(x: 0, y: 0, width: 900, height: 1500)
        #expect(frame(.firstThird, screen: portrait) == CGRect(x: 0, y: 1000, width: 900, height: 500))
        #expect(frame(.lastThird, screen: portrait) == CGRect(x: 0, y: 0, width: 900, height: 500))
    }

    @Test func maximizeFillsTheVisibleAreaAndCenterKeepsTheSize() {
        #expect(frame(.maximize) == screen)
        #expect(frame(.center) == CGRect(x: 320, y: 213, width: 800, height: 500))
        let huge = CGRect(x: 0, y: 0, width: 3000, height: 2000)
        #expect(frame(.center, window: huge) == screen)
    }

    @Test func nextDisplayKeepsTheWindowsPlaceAndScale() {
        let next = CGRect(x: 1440, y: 0, width: 2880, height: 1750)
        #expect(frame(.nextDisplay, next: next) == CGRect(x: 1640, y: 350, width: 1600, height: 1000))
        #expect(frame(.nextDisplay) == nil)
        #expect(frame(.restore) == nil)
    }

    @Test func picksTheScreenHoldingMostOfTheWindow() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        #expect(WindowLayout.screenIndex(for: CGRect(x: 1300, y: 100, width: 400, height: 300), in: screens) == 1)
        #expect(WindowLayout.screenIndex(for: CGRect(x: 1000, y: 100, width: 600, height: 300), in: screens) == 0)
        // Off every screen, the nearest one.
        #expect(WindowLayout.screenIndex(for: CGRect(x: 4000, y: 100, width: 100, height: 100), in: screens) == 1)
    }

    @Test func nextScreenGoesLeftToRightAndWrapsAround() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900), CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        #expect(WindowLayout.nextScreenIndex(after: 1, in: screens) == 0)
        #expect(WindowLayout.nextScreenIndex(after: 0, in: screens) == 1)
        #expect(WindowLayout.nextScreenIndex(after: 0, in: [screens[0]]) == nil)
    }

    @Test func flippingConvertsBetweenAppKitAndAccessibilityCoordinates() {
        // 100 points above the bottom of a 900-point main display is 300 below its top.
        let appKit = CGRect(x: 100, y: 100, width: 800, height: 500)
        let accessibility = WindowLayout.flipped(appKit, mainScreenHeight: 900)
        #expect(accessibility == CGRect(x: 100, y: 300, width: 800, height: 500))
        #expect(WindowLayout.flipped(accessibility, mainScreenHeight: 900) == appKit)
    }
}
