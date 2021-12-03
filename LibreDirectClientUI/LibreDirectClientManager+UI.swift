//
//  LibreDirectClientManager+UI.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit
import LibreDirectClient
import LoopKitUI

extension LibreDirectClientManager: CGMManagerUI {
    public static func setupViewController() -> (UIViewController & CGMManagerSetupViewController & CompletionNotifying)? {
        return nil
    }

    public func settingsViewController(for glucoseUnit: HKUnit) -> (UIViewController & CompletionNotifying) {
        let settings = LibreDirectClientSettingsViewController(cgmManager: self, glucoseUnit: glucoseUnit, allowsDeletion: true)
        let nav = SettingsNavigationViewController(rootViewController: settings)
        return nav
    }

    public var smallImage: UIImage? {
        return nil
    }
}
