import Foundation
import WhippetCore

extension ModuleManifest {
    static let calculator = ModuleManifest(
        id: "calculator",
        title: String(localized: "Calculator"),
        summary: String(localized: "Calculations, conversions and time zones, with a history of answers."),
        icon: "plus.forwardslash.minus",
        tint: .orange,
        commands: [
            ModuleCommand(
                id: "calculator", title: String(localized: "Calculator"), icon: "plus.forwardslash.minus",
                permissions: [.accessibility(.paste)], legacyHotkey: "command.calculator"),
            ModuleCommand(
                id: "floating-calculator", title: String(localized: "Floating Calculator"),
                icon: "macwindow.on.rectangle", legacyHotkey: "command.floatingCalculator"),
        ],
        features: [
            ModuleFeature(
                id: "inline", title: String(localized: "Answers in the Search Bar"),
                summary: String(localized: "Answers calculations and conversions as you type them in the search."),
                permissions: [.accessibility(.paste)]),
            ModuleFeature(
                id: "currency", title: String(localized: "Currency Conversion"),
                summary: String(localized: "Fetches the European Central Bank's daily exchange rates every 6 hours."),
                permissions: [.network(["www.ecb.europa.eu"])]),
        ]
    )
}

extension ModuleRef {
    static let calculatorModule = ModuleManifest.calculator.ref
    static let calculator = ModuleManifest.calculator.ref("calculator")
    static let floatingCalculator = ModuleManifest.calculator.ref("floating-calculator")
    static let inlineCalculation = ModuleManifest.calculator.ref("inline")
    static let currencyConversion = ModuleManifest.calculator.ref("currency")
}
