//
//  TagsTransformer.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import Foundation
import CoreData

@objc(TagsTransformer)
final class TagsTransformer: NSSecureUnarchiveFromDataTransformer {
    static let name = NSValueTransformerName(rawValue: "TagsTransformer")

    override static var allowedTopLevelClasses: [AnyClass] {
        return [NSArray.self, NSString.self]
    }

    public static func register() {
        let transformer = TagsTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}
