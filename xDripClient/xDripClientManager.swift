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
    
    private enum Config {
        static let filterNoise = 2.5
    }
    
    public var useFilter = true

    required convenience public init?(rawState: CGMManager.RawStateValue) {
        self.init()
    }

    public var rawState: CGMManager.RawStateValue {
        return [:]
    }

    public var client: xDripClient?
    
    public static let localizedTitle = LocalizedString("xDrip4iO5", comment: "Title for the CGMManager option")

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

    public let shouldSyncToRemoteService = true
    
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

                   
            
            // If our last glucose was less than 0.5 minutes ago, don't fetch.
            if let latestGlucose = self.latestBackfill, latestGlucose.startDate.timeIntervalSinceNow > -TimeInterval(minutes: 0.5) {
                self.delegateQueue.async {
                    completion(.noData)
                }
                return
            }
            
            
            self.isFetching = true
            self.requestReceiver = manager.fetchLast(60)
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

                
                // Ignore glucose readings that are more than 65 minutes old
                let last_65_min_glucose = glucose.filterDateRange( Date( timeInterval: -TimeInterval(minutes: 65), since: Date() ), nil )
                
                
                guard !last_65_min_glucose.isEmpty else {
                    self.delegateQueue.async {
                        completion(.noData)
                    }
                    return
                }
                
                
                var filteredGlucose = last_65_min_glucose
                if self.useFilter {
                    var filter = KalmanFilter(stateEstimatePrior: Double(last_65_min_glucose.last!.glucose), errorCovariancePrior: Config.filterNoise)
                    filteredGlucose.removeAll()
                    for var item in last_65_min_glucose.reversed() {
                        let prediction = filter.predict(stateTransitionModel: 1, controlInputModel: 0, controlVector: 0, covarianceOfProcessNoise: Config.filterNoise)
                        let update = prediction.update(measurement: Double(item.glucose), observationModel: 1, covarienceOfObservationNoise: Config.filterNoise)
                        filter = update
                        let signed_glucose = Int(filter.stateEstimatePrior.rounded())
                        
                        // I don't think that the Kalman filter should ever produce BG values outside of the valid range - just to be on the safe side
                        // this does also prevent negative glucose values from being cast to UInt16
                        guard ( ( ( signed_glucose >= 39 ) && ( signed_glucose <= 500 ) ) ) else {
                            self.delegateQueue.async {
                                completion(.noData)
                            }
                            return
                        }
                        
                        item.glucose = UInt16(signed_glucose)
                        filteredGlucose.append(item)
                    }
                    filteredGlucose = filteredGlucose.reversed()
                }

                
                var startDate: Date?
                
                if let latestGlucose = self.latestBackfill {
                    startDate = latestGlucose.startDate
                }
                else {
                    startDate = self.delegate.call { (delegate) -> Date? in
                        return delegate?.startDateToFilterNewData(for: self)
                    }
                }
                
                
                             
                
                                
                let newGlucose = filteredGlucose.filterDateRange(startDate, nil)
                
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
