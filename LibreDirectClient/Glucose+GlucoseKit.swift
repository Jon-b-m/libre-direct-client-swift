//
//  ShareGlucose+GlucoseKit.swift
//  Naterade
//
//  Created by Nathan Racklyeft on 5/8/16.
//  Copyright © 2016 Nathan Racklyeft. All rights reserved.
//

import Foundation
import HealthKit
import LoopKit

// MARK: - Glucose

public struct Glucose {
    public var glucose: UInt16
    public let trend: UInt8
    public let timestamp: Date
    public let collector: String?
}

// MARK: GlucoseValue

extension Glucose: GlucoseValue {
    public var startDate: Date {
        return timestamp
    }

    public var quantity: HKQuantity {
        return HKQuantity(unit: .milligramsPerDeciliter, doubleValue: Double(glucose))
    }
}

// MARK: SensorDisplayable

extension Glucose: SensorDisplayable {
    public var isStateValid: Bool {
        return ((glucose >= 39) && (glucose <= 500))
    }

    public var trendType: GlucoseTrend? {
        return GlucoseTrend(rawValue: Int(trend))
    }

    public var isLocal: Bool {
        return true
    }
}

public extension SensorDisplayable {
    var stateDescription: String {
        if isStateValid {
            return LocalizedString("OK", comment: "Sensor state description for the valid state")
        } else {
            return LocalizedString("Needs Attention", comment: "Sensor state description for the non-valid state")
        }
    }
}
