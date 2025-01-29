//
//  ImagesTransformer.swift
//  Eunoia-Journal
//
//  Created by Malchow, Alexander (TI-25) on 29.01.25.
//
import Foundation
import CoreData

@objc(ImagesTransformer)
final class ImagesTransformer: NSSecureUnarchiveFromDataTransformer {
    static let name = NSValueTransformerName(rawValue: "ImagesTransformer")

    override static var allowedTopLevelClasses: [AnyClass] {
        return [NSArray.self, NSString.self]
    }

    public static func register() {
        let transformer = ImagesTransformer()
        ValueTransformer.setValueTransformer(transformer, forName: name)
    }
}
