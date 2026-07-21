# Previsioni Pesca

Previsioni Pesca is an iOS application that estimates daily fish activity for coastal Mediterranean spots by combining lunar astronomy, offline harmonic tide modeling, solunar periods, coastal weather conditions, and water temperature.

The app does not rely on a single indicator. Instead, it computes a composite score for the day and then identifies the best activity windows within the 24-hour period.

## Features

- Daily fish activity score
- Best activity windows during the day
- Offline harmonic tide simulation
- Solunar period generation
- Weather-based score adjustment
- Water temperature correction
- Tide chart with visual activity windows and solunar markers

## How It Works

The forecast engine is built around two outputs:

1. A daily score that describes the overall quality of the day
2. A set of best windows that highlight the most favorable moments within that day

The final result is produced by combining multiple groups of factors:

- lunar phase
- lunar distance
- tide coefficient
- solunar overlap
- tide dynamics
- coastal weather conditions
- water temperature

## Forecast Pipeline

### 1. Astronomical data

For each selected date and location, the engine calculates or receives the following astronomical events:

- sunrise and sunset
- moonrise and moonset
- lunar transit
- lunar anti-transit
- moon age
- moon illumination
- moon distance

These values define the astronomical context of the day and are used both for the daily score and for intraday window detection.

### 2. Tide coefficient

The tide coefficient is a daily indicator of tidal energy. It is derived from:

- moon phase
- Earth-Moon distance
- a local lag factor called `tideLagDays`

The lag is important because local tidal response does not always match the astronomical forcing instantaneously.

The coefficient is calculated with the following logic:

```text
coeff = 70 + 30 * cos(4 * pi * moonAge / 29.53059) + distAdj
```

Where:

- `moonAge` is the lunar age in days
- `distAdj` is a correction derived from the normalized Earth-Moon distance
- the final value is clamped to the 20-120 range

This value is cached per station and per day.

### 3. Harmonic tide simulation

The app uses an offline harmonic tide model instead of depending entirely on external live tide APIs.

Each reference station includes harmonic constituents such as:

- `M2`
- `S2`
- `N2`
- `K1`
- `O1`

Tide height is reconstructed as the sum of constituent waves:

```text
h(t) = sum of [Ai * cos(wi * t - phii)]
```

Where:

- `Ai` is the amplitude of the constituent
- `wi` is the angular speed
- `phii` is the phase

The resulting raw tide height is then scaled using the daily tide coefficient.

### 4. Daily tide events

To find daily highs and lows, the engine samples the tide curve every 5 minutes across the full day and detects local extrema.

Each event is stored as:

- time
- height
- type (`Alta` or `Bassa`)

These events are later used both for visualization and for tide-dynamics scoring.

### 5. Solunar periods

The app generates solunar periods from lunar events using fixed windows:

- Major period: +/- 1 hour around lunar transit
- Major period: +/- 1 hour around lunar anti-transit
- Minor period: +/- 30 minutes around moonrise
- Minor period: +/- 30 minutes around moonset

If a solunar period overlaps with sunrise or sunset within about 30 minutes, it is flagged as enhanced.

Solunar periods are not treated as the final answer. They are only one part of the scoring model.

## Scoring Model

The scoring model is multiplicative. Each factor increases or decreases the final result instead of adding an isolated number of points.

### Daily score

The daily score is computed as:

```text
score_day = f_phase * f_dist * f_coeff * f_overlap * f_weather * f_temp
```

Where:

- `f_phase` = lunar phase factor
- `f_dist` = lunar distance factor
- `f_coeff` = tide coefficient factor
- `f_overlap` = solunar overlap factor
- `f_weather` = weather multiplier
- `f_temp` = water temperature factor

The final score is clamped to a maximum value of `1.8`.

### Daily activity levels

The numeric score is mapped to a qualitative label:

| Score range | Activity level |
|---|---|
| `< 0.45` | Bassa |
| `0.45 - < 0.90` | Moderata |
| `0.90 - < 1.26` | Buona |
| `1.26 - < 1.62` | Alta |
| `>= 1.62` | Molto Alta |

## Weather Multiplier

The weather multiplier combines discrete bonuses and a continuous wind curve.

### Discrete weather bonuses

| Condition | Effect |
|---|---:|
| `cloudCoverPercent > 60` | `+0.15` |
| `windDirectionChange > 30` | `+0.10` |
| `swellHeight > 0.5` | `+0.10` |
| `surfaceTempDelta24h < -1.5` | `+0.10` |

### Wind optimization curve

Wind is modeled with a Gaussian-like curve centered around 7.2 m/s:

```text
windMult = 0.7 + 0.5 * exp(-((windSpeedMps - 7.2)^2) / (2 * 4.0^2))
```

This means:

- very weak wind is penalized
- very strong wind is penalized
- moderate wind near 7.2 m/s is favored

### Final weather formula

```text
f_weather = (1 + bonus_cloud + bonus_windShift + bonus_swell + bonus_tempBreak) * windMult
```

## Tide Dynamics Factor

For intraday activity, the engine uses a dedicated tide-dynamics factor to estimate how active the water movement is at a specific moment.

This factor uses three components:

1. Current velocity proxy, based on tide height change over the previous hour
2. Transition bonus, if the time is within 90 minutes before a tide extreme
3. Slack-water penalty, if the time is within 30 minutes of low tide

### Explicit tide-dynamics weights

| Component | Logic | Effect |
|---|---|---|
| Current velocity | `1.0 + min(normalizedRate * 0.8, 0.4)` | up to `+0.4` |
| Pre-transition bonus | within 90 minutes before the extreme | `+0.2` |
| Slack near low tide | within 30 minutes of low tide | multiplier `0.7` |

The final formula is:

```text
f_tide = (velocityFactor + transitionBonus) * slackMultiplier
```

This makes the model favor moving water and pre-turning tide phases, while penalizing slack conditions near low tide.

## Best Windows Detection

Best windows are not copied directly from solunar periods. They are generated through a separate intraday scoring pass.

### Step 1: 15-minute slots

The day is divided into 96 slots of 15 minutes each.

### Step 2: Solunar overlap per slot

Each slot receives a solunar bonus based on how much it overlaps with major or minor periods:

- base `1.5` for major periods
- base `1.0` for minor periods
- extra `+0.5` for enhanced periods

This bonus is converted into a slot multiplier:

```text
f_solunar = 1 + (solunarBonus / 0.25) * 0.5
```

### Step 3: Slot score

The current slot formula is:

```text
score_slot = 0.5 * f_solunar * f_tide * f_weather * f_temp * f_phase * f_dist * f_coeff
```

The result is clamped to `1.8`.

### Step 4: Smoothing

To avoid noisy spikes, slot scores are smoothed with a 3-point moving average.

### Step 5: Peak detection

The engine finds local maxima by comparing each point to the previous and next points.

### Step 6: Window expansion

Each peak becomes a real window by expanding left and right while the score remains above 85 percent of the peak value.

Windows shorter than 45 minutes are discarded.

### Step 7: Merge and ranking

Close or overlapping windows are merged. The engine keeps up to 3 final windows and sorts them chronologically for display.

## Activity Reasons Shown in the UI

Each best window stores a score breakdown with these factor groups:

- tide
- solunar
- weather
- water temperature
- lunar phase

The UI extracts the most relevant textual reasons from that breakdown.

### Reason thresholds

| Condition | UI label |
|---|---|
| `tide > 1.25` | `corrente marea favorevole` |
| `tide > 1.05` | `flusso marea attivo` |
| `solunar > 1.20` | `periodo solunare attivo` |
| `weather > 1.10` | `meteo costiero favorevole` |
| `waterTemp < 0.90` | `temperatura acqua penalizzante` |
| `waterTemp > 1.05` | `temperatura acqua favorevole` |
| `lunarPhase > 0.80` | `fase lunare ottimale` |
| `lunarPhase < 0.30` | `fase lunare debole` |

The engine removes duplicates, ranks the reasons by importance, and keeps the top three.

## Relative Weight of the Factors

In practical terms, the factors currently behave like this:

| Factor | Relative weight | Notes |
|---|---|---|
| Solunar contribution in slots | High | Major and enhanced periods strongly influence timing |
| Tide dynamics | High | Moving water and pre-transition phases are very important |
| Weather | Medium-high | Can significantly improve or penalize the day |
| Water temperature | Medium | Often decisive between otherwise similar days |
| Lunar phase and distance | Medium | Provide the astronomical background of the day |
| Tide coefficient | Medium-high | Affects both tide shape and daily quality |

## Project Structure

```text
.
├── MeteoPescaApp.swift
├── ContentView.swift
├── Models.swift
├── AstronomyEngine.swift
├── TideEngine.swift
├── RulesEngine.swift
└── WeatherService.swift
```

### Main files

- `Models.swift` contains the data structures used across the app
- `AstronomyEngine.swift` computes astronomical events and lunar information
- `TideEngine.swift` contains the harmonic tide model and tide coefficient logic
- `RulesEngine.swift` contains the forecast pipeline and scoring logic
- `WeatherService.swift` retrieves atmospheric and marine weather data
- `ContentView.swift` renders the UI and chart components

## Requirements

- Xcode with SwiftUI support
- iOS deployment target compatible with the project settings
- Network access for weather and marine forecast retrieval

## Setup

1. Clone the repository
2. Open the project in Xcode
3. Build and run on simulator or device

## Usage

1. Select a location
2. Select a date
3. Let the app compute astronomical, tide, and weather data
4. Read the daily activity score
5. Inspect the best windows and tide chart for timing details

## Notes

- Tide modeling is offline and based on representative harmonic stations
- Weather data is fetched externally and used as a multiplier, not as the sole source of truth
- Solunar periods influence the score, but they are not the final recommendation by themselves
- The daily score and slot score formulas are conceptually aligned, but the slot score still includes a fixed `0.5` base factor

## License

This project is released under the MIT License.
