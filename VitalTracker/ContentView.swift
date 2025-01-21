import SwiftUI
import HealthKit

struct ContentView: View {
    @State private var sleepTime = "N/A"
    @State private var heartRate = "N/A"
    @State private var sleepHeartRate = "N/A"
    @State private var sleepQuality = "N/A"
    @State private var healthScore = 0
    @State private var selectedTab = 0
    @State private var heartRateVariability = "N/A"
    @State private var acuteTrainingLoad = "N/A"
    private var healthStore = HKHealthStore()

    func formattedTime() -> String {
        let date = Date()
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    func requestHealthKitAuthorization() {
        let typesToShare: Set = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!
        ]

        let typesToRead: Set = [
            HKObjectType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
            HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
            HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if success {
                print("HealthKit authorization successful")
                fetchHealthData()
            } else {
                print("HealthKit authorization failed: \(String(describing: error))")
            }
        }
    }

    func fetchHealthData() {
        fetchSleepAnalysis()
        fetchRecentHeartRateData()
        fetchHRVData()
        fetchAndCalculateATL()
    }

    // Fetching sleep periods and then fetching heart rate during those periods
    func fetchSleepAnalysis() {
        guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            return
        }

        // Get the start and end of the previous night (e.g., from 8 PM to 8 AM)
        let calendar = Calendar.current
        let now = Date()
        let startOfDay = calendar.startOfDay(for: now)
        let previousNight = calendar.date(byAdding: .day, value: -1, to: startOfDay)!
        let startOfSleepPeriod = calendar.date(byAdding: .hour, value: 20, to: previousNight)! // 8 PM
        let endOfSleepPeriod = calendar.date(byAdding: .hour, value: 10, to: startOfDay)! // 10 AM

        // Create a predicate to filter sleep data for the specified period
        let sleepPredicate = HKQuery.predicateForSamples(withStart: startOfSleepPeriod, end: endOfSleepPeriod, options: .strictStartDate)

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
        let sleepQuery = HKSampleQuery(sampleType: sleepType, predicate: sleepPredicate, limit: 0, sortDescriptors: [sortDescriptor]) { query, results, error in
            if let error = error {
                print("Error fetching sleep data: \(error.localizedDescription)")
                return
            }

            guard let sleepSamples = results as? [HKCategorySample] else {
                print("No sleep data available")
                return
            }

            var totalSleepMinutes = 0.0
            var sleepPeriods: [(start: Date, end: Date)] = []

            for sample in sleepSamples {
                // Only include REM, Core, and Deep sleep stages
                if sample.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue ||
                    sample.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue ||
                    sample.value == HKCategoryValueSleepAnalysis.asleepDeep.rawValue {
                    let sleepMinutes = sample.endDate.timeIntervalSince(sample.startDate) / 60
                    totalSleepMinutes += sleepMinutes
                    sleepPeriods.append((start: sample.startDate, end: sample.endDate))
                }
            }

            let hours = Int(totalSleepMinutes) / 60
            let minutes = Int(totalSleepMinutes) % 60

            DispatchQueue.main.async {
                self.sleepTime = String(format: "%dh %dm", hours, minutes) // Update sleepTime
                print("Formatted Sleep Time: \(self.sleepTime)")
                self.updateHealthScore() // Recalculate health score
            }

            // Fetch heart rate data during these sleep periods
            self.fetchHeartRateDuringSleepPeriods(sleepPeriods: sleepPeriods)
        }

        healthStore.execute(sleepQuery)
    }

    func fetchHeartRateDuringSleepPeriods(sleepPeriods: [(start: Date, end: Date)]) {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        var totalHeartRate = 0.0
        var sampleCount = 0

        let dispatchGroup = DispatchGroup()

        for period in sleepPeriods {
            dispatchGroup.enter()

            let predicate = HKQuery.predicateForSamples(withStart: period.start, end: period.end, options: .strictStartDate)
            let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: heartRateType, predicate: predicate, limit: 0, sortDescriptors: [sortDescriptor]) { query, results, error in
                if let error = error {
                    print("Error fetching heart rate data: \(error.localizedDescription)")
                    dispatchGroup.leave()
                    return
                }

                guard let heartRateSamples = results as? [HKQuantitySample] else {
                    print("No heart rate data available")
                    dispatchGroup.leave()
                    return
                }

                for sample in heartRateSamples {
                    let heartRateValue = sample.quantity.doubleValue(for: HKUnit(from: "count/min"))
                    totalHeartRate += heartRateValue
                    sampleCount += 1
                }

                dispatchGroup.leave()
            }

            healthStore.execute(query)
        }

        dispatchGroup.notify(queue: .main) {
            let averageHeartRate = sampleCount > 0 ? totalHeartRate / Double(sampleCount) : 0.0
            self.sleepHeartRate = String(format: "%.0f bpm", averageHeartRate) // Update sleepHeartRate
            self.updateHealthScore() // Recalculate health score
        }
    }
    
    func fetchRecentHeartRateData() {
        guard let heartRateType = HKObjectType.quantityType(forIdentifier: .heartRate) else {
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: heartRateType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { query, results, error in
            if let error = error {
                print("Error fetching heart rate data: \(error.localizedDescription)")
                return
            }

            guard let result = results?.first as? HKQuantitySample else {
                print("No heart rate data available")
                return
            }

            let heartRateUnit = HKUnit(from: "count/min")
            let heartRateValue = result.quantity.doubleValue(for: heartRateUnit)
            DispatchQueue.main.async {
                self.heartRate = String(format: "%.0f bpm", heartRateValue)
                self.updateHealthScore()
            }
        }

        healthStore.execute(query)
    }

    func fetchHRVData() {
        guard let hrvType = HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN) else {
            print("HRV type is not available.")
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let query = HKSampleQuery(sampleType: hrvType, predicate: nil, limit: 1, sortDescriptors: [sortDescriptor]) { query, results, error in
            if let error = error {
                print("Error fetching HRV data: \(error.localizedDescription)")
                return
            }

            guard let result = results?.first as? HKQuantitySample else {
                print("No HRV data available.")
                return
            }

            let hrvUnit = HKUnit.secondUnit(with: .milli)
            let hrvValue = result.quantity.doubleValue(for: hrvUnit)
            DispatchQueue.main.async {
                self.heartRateVariability = String(format: "%.0f ms", hrvValue)
                self.updateHealthScore()
            }
        }

        healthStore.execute(query)
    }

    func fetchActiveEnergyBurnedData(completion: @escaping ([Double], Error?) -> Void) {
        guard let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else {
            completion([], NSError(domain: "HealthKit", code: 1, userInfo: [NSLocalizedDescriptionKey: "Active Energy Burned Type not available"]))
            return
        }

        let calendar = Calendar.current
        let endDate = Date()
        guard let startDate = calendar.date(byAdding: .day, value: -7, to: endDate) else {
            completion([], NSError(domain: "HealthKit", code: 2, userInfo: [NSLocalizedDescriptionKey: "Unable to calculate start date"]))
            return
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        let query = HKStatisticsCollectionQuery(quantityType: energyType, quantitySamplePredicate: predicate, options: .cumulativeSum, anchorDate: startDate, intervalComponents: interval)

        query.initialResultsHandler = { query, results, error in
            var dailyEnergyBurned: [Double] = []

            if let statsCollection = results {
                statsCollection.enumerateStatistics(from: startDate, to: endDate) { statistics, stop in
                    if let sum = statistics.sumQuantity() {
                        let calories = sum.doubleValue(for: HKUnit.kilocalorie())
                        dailyEnergyBurned.append(calories)
                    } else {
                        dailyEnergyBurned.append(0)
                    }
                }
            }

            completion(dailyEnergyBurned, error)
        }

        healthStore.execute(query)
    }

    func calculateATL(from energyData: [Double]) -> Double {
        let alpha = 2.0 / (Double(energyData.count) + 1.0)

        var atl = 0.0
        for (index, energy) in energyData.enumerated() {
            let weight = pow(1.0 - alpha, Double(index))
            atl += energy * weight
        }

        return atl * alpha
    }

    func fetchAndCalculateATL() {
        fetchActiveEnergyBurnedData { energyData, error in
            if let error = error {
                print("Error fetching active energy burned data: \(error.localizedDescription)")
                return
            }

            let atl = self.calculateATL(from: energyData.reversed())
            DispatchQueue.main.async {
                self.acuteTrainingLoad = String(format: "%.0f ATL", atl)
            }
        }
    }

    func updateHealthScore() {
        let sleepMinutes = sleepTime.components(separatedBy: ["h", " "]).compactMap { Int($0) }.reduce(0) { $0 * 60 + $1 }
        let heartRateValue = Int(heartRate.components(separatedBy: " ").first ?? "") ?? 0
        let hrvValue = Int(heartRateVariability.components(separatedBy: " ").first ?? "") ?? 0

        let maxSleepMinutes = 480.0 // 8 hours
        let targetHeartRate = 64.0 // Target heart rate for perfect score
        let maxHRV = 150.0 // Maximum HRV for perfect score

        let sleepScore = min(50.0, (Double(sleepMinutes) / maxSleepMinutes) * 50.0)
        let heartRateScore = max(0.0, min(25.0, 25.0 - abs(Double(heartRateValue) - targetHeartRate) * 0.5))
        let hrvScore = min(25.0, (Double(hrvValue) / maxHRV) * 25.0)

        let score = 40 + sleepScore + heartRateScore + hrvScore

        DispatchQueue.main.async {
            self.healthScore = max(0, min(100, Int(score)))
        }
    }

    var body: some View {
        NavigationView {
            VStack {
                if selectedTab == 0 || selectedTab == 1 || selectedTab == 2 {
                    VStack {
                        CircleScoreView(score: healthScore)
                            .padding(.top, 50)
                    }
                }

                TabView(selection: $selectedTab) {
                    VStack(spacing: 0) {
                        Text("Current HRV")
                            .font(.title)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.top, 30)

                        Text("Time of Day: \(formattedTime())")
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))

                        VStack(spacing: 10) {
                            Text(heartRateVariability)
                                .font(.system(size: 64))
                                .fontWeight(.bold)
                                .foregroundColor(.green)

                            Text("HRV Status: Good")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .foregroundColor(.green)
                        }
                        .padding()
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(16)
                        .shadow(radius: 5)

                        Spacer()
                    }
                    .tag(0)
                    .onAppear {
                        fetchHRVData()
                    }

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            HealthCardView(
                                title: "Sleep",
                                value: sleepTime,
                                description: "",
                                headingColor: .blue,
                                baseline: "Baseline 5:30 - 8:00"
                            )
                            HealthCardView(
                                title: "Sleep HR",
                                value: sleepHeartRate,
                                description: "",
                                headingColor: .red,
                                baseline: "Baseline 49 - 65 bpm"
                            )
                        }
                        HStack(spacing: 16) {
                            HealthCardView(
                                title: "Sleep HRV",
                                value: heartRateVariability,
                                description: "",
                                headingColor: .purple,
                                baseline: "Baseline 50 - 110 ms"
                            )
                            HealthCardView(
                                title: "Sleep Quality",
                                value: sleepQuality,
                                description: "",
                                headingColor: .green,
                                baseline: "Quality of Sleep"
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 150)
                    .tag(1)

                    VStack(spacing: 16) {
                        HStack(spacing: 16) {
                            HealthCardView(
                                title: "Fatigue",
                                value: acuteTrainingLoad,
                                description: "",
                                headingColor: .orange,
                                baseline: "Baseline 20 - 45 ATL"
                            )
                            HealthCardView(
                                title: "Heart Rate",
                                value: heartRate,
                                description: "",
                                headingColor: .red,
                                baseline: "Baseline 60 - 110 bpm"
                            )
                        }
                        HStack(spacing: 16) {
                            HealthCardView(
                                title: "HRV",
                                value: heartRateVariability,
                                description: "",
                                headingColor: .purple,
                                baseline: "Baseline 60 - 150 ms"
                            )
                            HealthCardView(
                                title: "Fitness",
                                value: "N/A Steps",
                                description: "",
                                headingColor: .green,
                                baseline: "Tracked during Day"
                            )
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 150)
                    .tag(2)
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .always))
                .frame(height: 600)
                .animation(.easeInOut(duration: 0.5), value: selectedTab)
            }
            .padding(.top, 100)
            .onAppear {
                requestHealthKitAuthorization()
            }
        }
    }
}

struct HealthCardView: View {
    var title: String
    var value: String
    var description: String
    var headingColor: Color
    var baseline: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(headingColor)

            HStack {
                Text(value)
                    .font(.system(size: 18))
                    .fontWeight(.bold)
                    .foregroundColor(.white)

                Spacer()

                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.white)
            }

            Text(baseline)
                .font(.caption)
                .foregroundColor(.white.opacity(0.7))

            Spacer()
        }
        .padding()
        .frame(height: 140)
        .background(Color.gray.opacity(0.4))
        .cornerRadius(16)
        .shadow(radius: 5)
    }
}

struct CircleScoreView: View {
    var score: Int
    private let maxScore = 100

    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [Color.green.opacity(0.2), Color.green.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 40)
                )
                .frame(width: 200, height: 200)

            Circle()
                .trim(from: 0.0, to: CGFloat(score) / CGFloat(maxScore))
                .stroke(
                    LinearGradient(
                        colors: [.green, .red],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    style: StrokeStyle(lineWidth: 28, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .frame(width: 200, height: 200)

            Text("\(score)")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}



