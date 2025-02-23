import Foundation

// Registriere die Klasse für Objective-C Runtime
@objc(StringArrayTransformer)
final class StringArrayTransformer: ValueTransformer {
    
    static let name = NSValueTransformerName(rawValue: "StringArrayTransformer")

    override class func transformedValueClass() -> AnyClass {
        return NSArray.self
    }
    
    override class func allowsReverseTransformation() -> Bool {
        return true
    }
    
    /// Registriere den Transformer
    public static func register() {
        ValueTransformer.setValueTransformer(
            StringArrayTransformer(),
            forName: name
        )
    }
    
    override func transformedValue(_ value: Any?) -> Any? {
        guard let stringArray = value as? [String] else { return nil }
        return stringArray as NSArray
    }
    
    override func reverseTransformedValue(_ value: Any?) -> Any? {
        guard let array = value as? NSArray else { return nil }
        return array as? [String]
    }
} 