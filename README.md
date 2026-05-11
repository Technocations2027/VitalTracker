# VitalTracker

VitalTracker is an iOS health monitoring app that reads real-time biometric data from Apple HealthKit and presents it in a clean, at-a-glance dashboard. It surfaces the metrics that actually matter for recovery and daily readiness — sleep duration, resting heart rate, heart rate variability, and sleep quality — and wraps them into a single health score.

## Features

- Reads live HRV, heart rate, sleep duration, and sleep quality from Apple HealthKit
- Displays a dynamic health score calculated from your biometric data
- Three-tab dashboard: HRV status, sleep breakdown, and fitness overview
- Animated score circle showing your current readiness at a glance
- Per-metric cards with baseline ranges for context
- Requests only the HealthKit permissions it actually uses

## Requirements

- iOS 15 or newer
- Xcode 14 or newer
- A physical iPhone or Apple Watch (HealthKit data is not available in the simulator)
- HealthKit-enabled device with sleep and heart rate data recorded

## Install

Clone the repo:

```
git clone https://github.com/TECHNOCATIONS2027/VitalTracker.git
cd VitalTracker
```

Open the project in Xcode:

```
open VitalTracker.xcodeproj
```

Select your physical device as the build target, then build and run. On first launch, the app will prompt for HealthKit authorization — approve heart rate, HRV, and sleep analysis to populate all metrics.

## Notes

- HRV data (`heartRateVariabilitySDNN`) requires an Apple Watch to generate readings. Without a Watch, the HRV field will show N/A.
- Sleep analysis pulls the most recent sleep session recorded by the Health app or a connected sleep tracker.
- Baseline ranges shown in the metric cards are illustrative defaults and will be made user-configurable in a future update.
