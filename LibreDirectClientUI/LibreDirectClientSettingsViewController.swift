//
//  LibreDirectClientSettingsViewController.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import HealthKit
import LibreDirectClient
import LoopKit
import LoopKitUI
import UIKit

// MARK: - LibreDirectClientSettingsViewController

public class LibreDirectClientSettingsViewController: UITableViewController {
    // MARK: Lifecycle

    public init(cgmManager: LibreDirectClientManager, glucoseUnit: HKUnit, allowsDeletion: Bool) {
        self.cgmManager = cgmManager
        self.glucoseUnit = glucoseUnit
        self.allowsDeletion = allowsDeletion
        
        super.init(style: .grouped)
    }
    
    @available(*, unavailable)
    public required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: Public

    public let cgmManager: LibreDirectClientManager
    
    public let glucoseUnit: HKUnit
    
    public let allowsDeletion: Bool

    override public func viewDidLoad() {
        super.viewDidLoad()
        
        title = cgmManager.localizedTitle
        
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 44
        
        tableView.sectionHeaderHeight = UITableViewAutomaticDimension
        tableView.estimatedSectionHeaderHeight = 55
        
        tableView.register(SettingsTableViewCell.self, forCellReuseIdentifier: SettingsTableViewCell.className)
        tableView.register(TextButtonTableViewCell.self, forCellReuseIdentifier: TextButtonTableViewCell.className)
        
        let button = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(doneTapped(_:)))
        navigationItem.setRightBarButton(button, animated: false)
    }
    
    override public func numberOfSections(in tableView: UITableView) -> Int {
        return allowsDeletion ? Section.allCases.count : Section.allCases.count - 1
    }
    
    override public func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch Section(rawValue: section)! {
        case .latestReading:
            return LatestReadingRow.allCases.count
        case .delete:
            return 1
        }
    }
    
    override public func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch Section(rawValue: indexPath.section)! {
        case .latestReading:
            let cell = tableView.dequeueReusableCell(withIdentifier: SettingsTableViewCell.className, for: indexPath) as! SettingsTableViewCell
            let glucose = cgmManager.latestBackfill
            
            switch LatestReadingRow(rawValue: indexPath.row)! {
            case .glucose:
                cell.textLabel?.text = LocalizedString("Glucose", comment: "Title describing glucose value")
                
                if let quantity = glucose?.quantity, let formatted = glucoseFormatter.string(from: quantity, for: glucoseUnit) {
                    cell.detailTextLabel?.text = formatted
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            case .date:
                cell.textLabel?.text = LocalizedString("Date", comment: "Title describing glucose date")
                
                if let date = glucose?.timestamp {
                    cell.detailTextLabel?.text = dateFormatter.string(from: date)
                } else {
                    cell.detailTextLabel?.text = SettingsTableViewCell.NoValueString
                }
            case .trend:
                cell.textLabel?.text = LocalizedString("Trend", comment: "Title describing glucose trend")
                
                cell.detailTextLabel?.text = glucose?.trendType?.localizedDescription ?? SettingsTableViewCell.NoValueString
            }
            
            return cell
        case .delete:
            let cell = tableView.dequeueReusableCell(withIdentifier: TextButtonTableViewCell.className, for: indexPath) as! TextButtonTableViewCell
            
            cell.textLabel?.text = LocalizedString("Delete CGM", comment: "Title text for the button to remove a CGM from Loop")
            cell.textLabel?.textAlignment = .center
            cell.tintColor = .delete
            cell.isEnabled = true
            return cell
        }
    }
    
    override public func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        switch Section(rawValue: section)! {
        case .latestReading:
            return LocalizedString("Latest Reading", comment: "Section title for latest glucose reading")
        case .delete:
            return nil
        }
    }
    
    override public func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        switch Section(rawValue: indexPath.section)! {
        case .latestReading:
            tableView.deselectRow(at: indexPath, animated: true)
        case .delete:
            let confirmVC = UIAlertController(cgmDeletionHandler: {
                self.cgmManager.notifyDelegateOfDeletion {
                    DispatchQueue.main.async {
                        self.complete()
                    }
                }
            })
            
            present(confirmVC, animated: true) {
                tableView.deselectRow(at: indexPath, animated: true)
            }
        }
    }

    // MARK: Internal

    @objc func doneTapped(_ sender: Any) {
        complete()
    }

    // MARK: Private

    // MARK: - UITableViewDataSource
    
    private enum Section: Int, CaseIterable {
        case latestReading
        case delete
    }
    
    private enum LatestReadingRow: Int, CaseIterable {
        case glucose
        case date
        case trend
    }

    private lazy var glucoseFormatter: QuantityFormatter = {
        let formatter = QuantityFormatter()
        formatter.setPreferredNumberFormatter(for: glucoseUnit)
        return formatter
    }()
    
    private lazy var dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .long
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()

    private func complete() {
        if let nav = navigationController as? SettingsNavigationViewController {
            nav.notifyComplete()
        }
    }
}

private extension UIAlertController {
    convenience init(cgmDeletionHandler handler: @escaping () -> Void) {
        self.init(
            title: nil,
            message: LocalizedString("Are you sure you want to delete this CGM?", comment: "Confirmation message for deleting a CGM"),
            preferredStyle: .actionSheet
        )
        
        addAction(UIAlertAction(
            title: LocalizedString("Delete CGM", comment: "Button title to delete CGM"),
            style: .destructive,
            handler: { _ in
                handler()
            }
        ))
        
        let cancel = LocalizedString("Cancel", comment: "The title of the cancel action in an action sheet")
        addAction(UIAlertAction(title: cancel, style: .cancel, handler: nil))
    }
}
