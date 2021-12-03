//
//  LibreDirectClient.swift
//  LibreDirectClient
//
//  Created by Mark Wilson on 5/7/16.
//  Copyright © 2016 Mark Wilson. All rights reserved.
//

import Combine
import Foundation

// MARK: - ClientError

public enum ClientError: Error {
    case fetchError
    case dataError(reason: String)
    case dateError
}

// MARK: - LibreDirectClient

public class LibreDirectClient {
    // MARK: Lifecycle

    public init(_ group: String? = Bundle.main.appGroupSuiteName) {
        shared = UserDefaults(suiteName: group)
    }

    // MARK: Internal

    func fetchLast(_ n: Int) -> AnyPublisher<[Glucose], Swift.Error> {
        shared.publisher
            .retry(2)
            .tryMap { try self.fetchLastBGs(n, $0) }
            .map { $0.filter { $0.isStateValid } }
            .eraseToAnyPublisher()
    }

    // MARK: Private

    private let shared: UserDefaults?

    private func fetchLastBGs(_ n: Int, _ sharedParm: UserDefaults?) throws -> [Glucose] {
        do {
            guard let sharedData = sharedParm?.data(forKey: "latestReadings") else {
                throw ClientError.fetchError
            }
        
            let decoded = try? JSONSerialization.jsonObject(with: sharedData, options: [])
            guard let sgvs = decoded as? [AnyObject] else {
                throw ClientError.dataError(reason: "Failed to decode SGVs as array from recieved data.")
            }
        
            var transformed: [Glucose] = []
            for sgv in sgvs.prefix(n) {
                // Collector might not be available
                var collector: String?
                if let _col = sgv["Collector"] as? String {
                    collector = _col
                }
                
                if let glucose = sgv["Value"] as? Int, let trend = sgv["Trend"] as? Int, let dt = sgv["DT"] as? String {
                    // only add glucose readings in a valid range - skip unrealistically low or high readings
                    // this does also prevent negative glucose values from being cast to UInt16
                    if glucose >= 39, glucose <= 500 {
                        transformed.append(Glucose(
                            glucose: UInt16(glucose),
                            trend: UInt8(trend),
                            timestamp: try parseDate(dt),
                            collector: collector
                        ))
                    }
                } else {
                    throw ClientError.dataError(reason: "Failed to decode an SGV record.")
                }
            }
            
            return transformed
            
        } catch let error as ClientError {
            throw error
        } catch {
            throw ClientError.fetchError
        }
    }

    private func parseDate(_ wt: String) throws -> Date {
        // wt looks like "/Date(1462404576000)/"
        let re = try NSRegularExpression(pattern: "\\((.*)\\)")
        if let match = re.firstMatch(in: wt, range: NSMakeRange(0, wt.count)) {
            #if swift(>=4)
                let matchRange = match.range(at: 1)
            #else
                let matchRange = match.rangeAt(1)
            #endif
            let epoch = Double((wt as NSString).substring(with: matchRange))! / 1000
            return Date(timeIntervalSince1970: epoch)
        } else {
            throw ClientError.dateError
        }
    }
}

public extension Bundle {
    var appGroupSuiteName: String {
        return object(forInfoDictionaryKey: "AppGroupIdentifier") as! String
    }
}
