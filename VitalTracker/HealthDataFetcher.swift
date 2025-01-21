import Foundation
import HealthKit

class HealthDataFetcher {
    let healthStore = HKHealthStore()
    
    func fetchHealthData(completion: @escaping (Double, Double) -> Void) {
        fetchSleepAnalysis { sleepMinutes in
            self.fetchHRVData { hrvValue in
                print("Fetched Sleep Minutes: \(sleepMinutes), Fetched HRV Value: \(hrvValue)")
                completion(sleepMinutes, hrvValue)
            }
        }
    }

    func fetchSleepAnalysis(completion: @escaping (Double) -> Void) {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(sampleType: sleepType, predicate: predicate, limit: 0, sortDescriptors: [sortDescriptor]) { query, results, error in
            if let error = error {
                print("Error fetching sleep data: \(error.localizedDescription)")
                return
            }

            guard let sleepSamples = results as? [HKCategorySample] else {
                print("No sleep data available")
                return
            }

            var totalSleepMinutes = 0.0
            for sample in sleepSamples where sample.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                totalSleepMinutes += sample.endDate.timeIntervalSince(sample.startDate) / 60
            }

            print("Total Sleep Minutes: \(totalSleepMinutes)")
            completion(totalSleepMinutes)
        }

        healthStore.execute(query)
    }

    func fetchHRVData(completion: @escaping (Double) -> Void) {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            return
        }

        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: endOfDay, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)

        let query = HKSampleQuery(sampleType: hrvType, predicate: predicate, limit: 0, sortDescriptors: [sortDescriptor]) { query, results, error in
            if let error = error {
                print("Error fetching HRV data: \(error.localizedDescription)")
                return
            }

            guard let hrvSamples = results as? [HKQuantitySample] else {
                print("No HRV data available")
                return
            }

            var totalHRV = 0.0
            var count = 0
            for sample in hrvSamples {
                totalHRV += sample.quantity.doubleValue(for: HKUnit.secondUnit(with: .milli))
                count += 1
            }

            let averageHRV = count > 0 ? totalHRV / Double(count) : 0.0
            print("Average HRV: \(averageHRV)")
            completion(averageHRV)
        }

        healthStore.execute(query)
    }

    func calculateHealthScore(sleepMinutes: Double, hrvValue: Double, completion: @escaping (Int) -> Void) {
        let apiKey = "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"
        guard let url = URL(string: "https://api.openai.com/v1/chat/completions") else {
            print("Invalid URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let hours = Int(sleepMinutes) / 60
        let minutes = Int(sleepMinutes) % 60

        let payload: [String: Any] = [
            "model": "gpt-4o-mini",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant for calculating health scores."],
                ["role": "user", "content": "Based on the following health data, provide a health score out of 100, where 100 is the healthiest:\n- Sleep time: \(hours) hours and \(minutes) minutes\n- HRV: \(hrvValue) ms\nNote: A perfect score of 100 is achieved with 8 hours of sleep and 120 ms HRV. The score should be generous, so  7.5 hours with 100 ms would be a 95"]
            ],
            "max_tokens": 100,
            "temperature": 0.7
        ]

        guard let jsonData = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            print("Failed to serialize JSON")
            return
        }

        request.httpBody = jsonData

        let task = URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                print("Error: \(error.localizedDescription)")
                return
            }

            guard let data = data else {
                print("No data received")
                return
            }

            do {
                let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                let responseString = String(data: data, encoding: .utf8)
                print("Response String: \(String(describing: responseString))")

                if let json = json,
                   let choices = json["choices"] as? [[String: Any]],
                   let message = choices.first?["message"] as? [String: Any],
                   let content = message["content"] as? String,
                   let score = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    print("Parsed Score: \(score)")
                    completion(score)
                } else {
                    print("Invalid response format: \(String(describing: json))")
                }
            } catch {
                print("Failed to decode response: \(error.localizedDescription)")
            }
        }

        task.resume()
    }
}
