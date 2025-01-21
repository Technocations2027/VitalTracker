import Foundation
import Combine
import HealthKit

class HealthDataViewModel: ObservableObject {
    @Published var healthScore: Int = 0

    private let healthDataFetcher = HealthDataFetcher()
    
    func fetchAndCalculateHealthScore() {
        healthDataFetcher.fetchHealthData { sleepMinutes, hrvValue in
            print("Fetched Sleep Minutes in ViewModel: \(sleepMinutes), HRV Value: \(hrvValue)")
            self.healthDataFetcher.calculateHealthScore(sleepMinutes: sleepMinutes, hrvValue: hrvValue) { score in
                DispatchQueue.main.async {
                    print("Updating healthScore in ViewModel: \(score)")
                    self.healthScore = score
                }
            }
        }
    }
}
