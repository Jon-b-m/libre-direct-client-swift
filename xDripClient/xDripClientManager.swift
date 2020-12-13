//
//  xDripClientManager.swift
//  Loop
//
//  Copyright © 2018 LoopKit Authors. All rights reserved.
//

import LoopKit
import HealthKit
import Combine



public class xDripClientManager: CGMManager {
    
    public static var managerIdentifier = "xDripClient"

    public init() {
        client = xDripClient()
        updateTimer = DispatchTimer(timeInterval: 10, queue: processQueue)
        scheduleUpdateTimer()
    }

    required convenience public init?(rawState: CGMManager.RawStateValue) {
        self.init()
    }

    public var rawState: CGMManager.RawStateValue {
        return [:]
    }

    public var client: xDripClient?
    
    public static let localizedTitle = LocalizedString("xDrip", comment: "Title for the CGMManager option")

    public let appURL: URL? = URL(string: "xdrip://")

    public var cgmManagerDelegate: CGMManagerDelegate? {
        get {
            return delegate.delegate
        }
        set {
            delegate.delegate = newValue
        }
    }
    
    public var delegateQueue: DispatchQueue! {
        get {
            return delegate.queue
        }
        set {
            delegate.queue = newValue
        }
    }
    
    public let delegate = WeakSynchronizedDelegate<CGMManagerDelegate>()
    
    public let providesBLEHeartbeat = false

    public let shouldSyncToRemoteService = false
    
    private var isFetching = false
    
    private var requestReceiver: Cancellable?

    public var sensorState: SensorDisplayable? {
        return latestBackfill
    }

    public let managedDataInterval: TimeInterval? = nil
    
    private let processQueue = DispatchQueue(label: "xDripClientManager.processQueue")

    public private(set) var latestBackfill: Glucose?
    
    public var latestCollector: String? {
        if let glucose = latestBackfill, let collector = glucose.collector, collector != "unknown" {
            return collector
        }
        return nil
    }

    
    
       
    
    public func fetchNewDataIfNeeded(_ completion: @escaping (CGMResult) -> Void) {
        
        
        
        processQueue.async {
            
            
            guard let manager = self.client, !self.isFetching else {
                self.delegateQueue.async {
                    completion(.noData)
                }
                return
            }

                   
            
            // If our last glucose was less than 4.5 minutes ago, don't fetch.
            if let latestGlucose = self.latestBackfill, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 4.5) {
                self.delegateQueue.async {
                    completion(.noData)
                }
                return
            }
            
            
            self.isFetching = true
            self.requestReceiver = manager.fetchLast(1)
            .sink(receiveCompletion: { finish in
                switch finish {
                case .finished: break
                case let .failure(error):
                    self.delegateQueue.async {
                        completion(.error(error))
                    }
                }
                self.isFetching = false
            }, receiveValue: { [weak self] glucose in
                guard let self = self else { return }
                guard !glucose.isEmpty else {
                    self.delegateQueue.async {
                        completion(.noData)
                    }
                    return
                }

                

                
                
                // Ignore glucose values that are up to a minute newer than our previous value, to account for possible time shifting in Share data
                let startDate = self.delegate.call { (delegate) -> Date? in
                    return delegate?.startDateToFilterNewData(for: self)?.addingTimeInterval(TimeInterval(minutes: 1))
                }
                
                
                let newGlucose = glucose.filterDateRange(startDate, nil)
                
                let newSamples = newGlucose.filter({ $0.isStateValid }).map {
                    return NewGlucoseSample(date: $0.startDate, quantity: $0.quantity, isDisplayOnly: false, syncIdentifier: "\(Int($0.startDate.timeIntervalSince1970))", device: self.device)
                }
                
                
              
                
                self.latestBackfill = newGlucose.first
                
                
                
                                           
                self.delegateQueue.async {
                    guard !newSamples.isEmpty else {
                        completion(.noData)
                        return
                    }
                    completion(.newData(newSamples))
                }
            })
        }


    }
    
    
    
    

    public var device: HKDevice? {
        
        return HKDevice(
            name: "xDripClient",
            manufacturer: "xDrip",
            model: latestCollector,
            hardwareVersion: nil,
            firmwareVersion: nil,
            softwareVersion: nil,
            localIdentifier: nil,
            udiDeviceIdentifier: nil
        )
    }

    public var debugDescription: String {
        return [
            "## xDripClientManager",
            "latestBackfill: \(String(describing: latestBackfill))",
            "latestCollector: \(String(describing: latestCollector))",
            ""
        ].joined(separator: "\n")
    }
    
    private let updateTimer: DispatchTimer

    private func scheduleUpdateTimer() {
        updateTimer.suspend()
        updateTimer.eventHandler = { [weak self] in
            guard let self = self else { return }
            self.fetchNewDataIfNeeded { result in
                guard case .newData = result else { return }
                self.delegate.notify { delegate in
                    delegate?.cgmManager(self, didUpdateWith: result)
                }
            }
        }
        updateTimer.resume()
    }
}
