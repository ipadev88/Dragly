<div align="center">

<img src="Design/dragly-logo.png" width="128" alt="Dragly">

# Dragly

**GPS performance meter for cars — accurate acceleration timing on a single iPhone**

[![iOS](https://img.shields.io/badge/iOS-26%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/ios/)
[![iPadOS](https://img.shields.io/badge/iPadOS-26%2B-000000?style=for-the-badge&logo=apple&logoColor=white)](https://www.apple.com/ipados/)
[![Swift](https://img.shields.io/badge/Swift-6-F05138?style=for-the-badge&logo=swift&logoColor=white)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-0B84FF?style=for-the-badge&logo=swift&logoColor=white)](https://developer.apple.com/xcode/swiftui/)
[![Xcode](https://img.shields.io/badge/Xcode-26-1575F9?style=for-the-badge&logo=xcode&logoColor=white)](https://developer.apple.com/xcode/)

<img src="Design/screenshots/01-measure.png" width="200" alt="Measure">&nbsp;
<img src="Design/screenshots/02-result.png" width="200" alt="Result">&nbsp;
<img src="Design/screenshots/03-scrub.png" width="200" alt="Chart scrubbing">&nbsp;
<img src="Design/screenshots/04-history.png" width="200" alt="History">

</div>

---

## What it is

A Draggy-style performance meter that runs on one iPhone — no external GNSS receiver. Put the phone in the car, hit **START**, and forget about it: the app detects the launch on its own and times everything at once.

**Cruising at 55 mph and you floor it?** The clock starts by itself as you cross 60, and from there it keeps timing 60–90, 60–125, 90–125, 125–130, 125–155 and so on. A run doesn't stop at a round number — as long as the car keeps pulling, the measurement continues.

## Features

| | |
|---|---|
| **Standing start** | 0–60, 0–100, 0–150, 0–200, 0–250 km/h (and mph equivalents) |
| **Rolling start** | Any pair of marks: 100–200, 150–200, 200–210 … 200–250 |
| **Distances** | 60 ft, 100 m, 1/8 mile, 1/4 mile, 1/2 mile, 1 km — with trap speed |
| **Drag strip** | Optional 1-foot rollout, trap speed over the last 66 ft |
| **Classic** | 60–130 mph in one line |
| **Custom intervals** | Any range, e.g. 130–170 — timed on every run |
| **Chart** | Speed curve; press and drag to read time, speed, distance and g at any point |
| **Run conditions** | Temperature, altitude, density altitude, track slope |
| **History** | Every run stored on device with its chart and full table |
| **Units** | km/h and mph, meters and feet, °C and °F |

## How the accuracy works

GPS on an iPhone updates roughly once per second — nowhere near enough for hundredths of a second. So Dragly doesn't rely on GPS alone.

```
GPS (1 Hz, Doppler) ─┐
                     ├─► Kalman filter ─► 100 Hz speed ─► interpolation ─► time
IMU (100 Hz, accel) ─┘      [v, bias]
```

* **Kalman sensor fusion.** The state is speed plus accelerometer bias. Prediction runs on every IMU tick (10 ms); correction runs on every GPS fix using Doppler speed weighted by its reported variance.
* **Fix latency compensation.** A fix arrives stamped in the past, so the innovation is computed against the estimate *at fix time*, not "now". Without this there was a systematic error of ≈0.16 s.
* **Orientation doesn't matter.** The phone can lie in any position: the direction of travel is learned automatically and protected against flipping under braking.
* **Exact crossing times.** Each mark crossing is linearly interpolated between filter ticks — 0.01 s resolution.
* **Standing launches** are caught on the acceleration edge (the IMU reacts an order of magnitude sooner than GPS), replaying the confirmation window so the first 0.2 s aren't lost.
* **Slope and DA.** Track slope comes from the barometer (≈0.1 m vertically versus meters from GPS); density altitude is derived from pressure and temperature.
* **Works without the IMU too.** If the accelerometer is unavailable the engine falls back to GPS-only — accuracy drops, but the run is still timed.

### Verified accuracy

The engine is run against synthetic physics (noisy GPS with delivery latency + biased accelerometer) and compared to an analytical reference:

| Scenario | Error |
|---|---|
| Standing start, 0–100 km/h | ±0.04 s |
| Rolling start, 100–200 km/h | ±0.02 s |
| 1/4 mile (ET) | ±0.01 s |
| GPS-only, no accelerometer | ±0.13 s |
| Worst case across 12 runs with different noise | ±0.16 s |

> Real-world accuracy depends on GPS reception. The phone must be stationary relative to the car — in a mount, on a seat or in a pocket; held in your hand the IMU gets noisy and accuracy degrades toward the GPS-only level.

## Install

### Prebuilt IPA

Download `Dragly.ipa` from the [latest release](https://github.com/ipadev88/Dragly/releases/latest). The build is **unsigned** — sign it with your own Apple ID using [Sideloadly](https://sideloadly.io), [AltStore](https://altstore.io) or Xcode.

### From source

```bash
git clone https://github.com/ipadev88/Dragly.git
cd Dragly
open Dragly.xcodeproj
```

Build the **Dragly** scheme on your device (⌘R). Requires Xcode 26+ and iOS 26+.

## Stack

Apple system frameworks only — **no third-party dependencies**, no SPM, no CocoaPods.

| Framework | Used for |
|---|---|
| `SwiftUI` | The entire interface |
| `Observation` | `@Observable` models instead of ObservableObject |
| `SwiftData` | Run history |
| `Charts` | Speed chart with scrubbing |
| `CoreLocation` | Doppler speed and coordinates |
| `CoreMotion` | `CMDeviceMotion` at 100 Hz + `CMAltimeter` |
| `Foundation` | The algorithm core — no UI or sensor dependencies |

## Structure

```
Dragly/
├── Engine/                     core, pure Foundation — testable off-device
│   ├── KalmanSpeedEstimator    GPS + IMU fusion, fix latency compensation
│   ├── RunEngine               run state machine, mark detection
│   └── RunTypes                result models, interval resolution
├── Services/                   sensor wrappers
│   ├── LocationService         CLLocationManager → SpeedFix
│   ├── MotionService           CMDeviceMotion → AccelTick
│   ├── BarometerService        CMAltimeter → pressure and slope
│   └── SimulatedDriveService   synthetic run (DEBUG only)
├── Models/RunRecord            SwiftData model of a run
├── App/AppModel                wiring: services → engine → store
└── Views/                      screens: measure, result, history, settings
```

The core (`Engine/`) imports neither CoreLocation nor CoreMotion nor SwiftUI — only `Foundation`. That's why the algorithm compiles and can be verified with plain `swiftc` on a Mac, without a simulator and without a car.

## Permissions

| Permission | Why |
|---|---|
| Location (when in use) | Doppler speed is the basis of every measurement |
| Motion & fitness | Accelerometer and barometer for accuracy between GPS fixes |

Nothing is uploaded; your data stays on the device. The only network request is air temperature for the run's coordinates via [Open-Meteo](https://open-meteo.com) (no keys, no account). Offline the app works fully — it just won't show temperature.

## Languages

The interface ships in **English** and **Russian**, following the system language.

## License

[MIT](LICENSE)
