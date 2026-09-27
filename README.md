# Errands Overpowered (`errands-op`)

> **Offline-first, algorithmic errand routing engine with Home Assistant bi-directional sync, Hybrid VRPTW multi-stop sequence solver, dual-ring hysteresis geofencing, and learned in-store aisle walking order DAGs.**

[![Flutter](https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.13.4-0175C2?logo=dart)](https://dart.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Tests Passing](https://img.shields.io/badge/tests-10%2F10%20passing-brightgreen.svg)]()

---

## 🎯 Philosophy: Human-in-the-Loop Optimization

Traditional route optimizers forcefully override user lists, causing frustration when personal errands require specific sequences. `errands-op` treats mathematical algorithms as **non-destructive visual suggestions**:

1. **Non-Destructive Overlays**: The primary list retains your manual ordering (`human_order_index`) at all times. Algorithmic solver suggestions appear as visual overlay badges (`Stop #1`, `Stop #2`).
2. **Hard Sequence Locks**: Any item or stop can be pinned (📌). Pinned stops enforce hard temporal constraints ($t_A + s_A + C_{AB} \le t_B$) that the solver cannot modify.
3. **Thermal Decay Perishable Deferral**: Cold items (ice cream, frozen goods, dairy) are dynamically penalized ($\gamma = 250$), deferring their stops to the final leg of the journey so they don't melt during earlier errands.
4. **Constraint Relaxation Cascade**: If a hard manual lock would cause an arrival after store closing hours, the engine surfaces an alert warning rather than failing or silently dropping stops.

---

## ⚡ Core Engine Features

### 1. Hybrid VRPTW Errand Solver
* **Disjunctive Candidate Matching**: Items automatically match candidate stores supporting their category, weighted by historical store preference confidence.
* **Geohash Distance Matrix with Haversine Fallback**: 6-character spatial Geohash caching with 7-day TTL and road tortuosity ($\tau = 1.28$). Recalculation is skipped unless user displacement exceeds $500\text{m}$.

### 2. Dual-Ring Hysteresis Geofencing State Machine
Eliminates GPS drift and false triggers when driving past stores:
* **Inner Arrival Boundary** ($R_{\text{in}} = 40\text{m}$): Requires continuous $120\text{s}$ dwell before transitioning from `OUTSIDE_STORE` $\to$ `INSIDE_STORE`.
* **Outer Exit Boundary** ($R_{\text{out}} = 80\text{m}$): Triggers an exit grace countdown of $180\text{s}$ before closing a store visit.
* **2D Kalman GPS Filter**: Discards GPS readings with horizontal accuracy $> 30\text{m}$.

### 3. In-Store Aisle Walk-Order Precedence Learning (DAG)
* Captures timestamped item check-offs inside stores ($\tau_1 < \tau_2 < \dots < \tau_m$).
* Computes exponential decay precedence weights: $w(\Delta \tau) = \exp(-(\tau_B - \tau_A)/\sigma)$.
* **Feedback Arc Set (FAS)**: Detects and eliminates directed cycles by severing the weakest links.
* **Kahn's Topological Sort**: Produces an empirical walk order through store aisles.

### 4. Home Assistant Bi-Directional WebSocket Sync
* Connects to `/api/websocket` subscribing to `todo/` entities.
* **Hybrid Logical Clock (HLC)**: Offline-first mutation queue with monotonic causality and Last-Write-Wins (LWW) conflict resolution.
* Exponential backoff reconnects with random jitter.

---

## 🏗️ Architecture

```
lib/
├── core/
│   ├── constants.dart         # Geofence radii, tortuosity tau, thermal penalty gamma
│   ├── geohash.dart           # Base-32 6-character spatial geohash encoder/decoder
│   ├── haversine.dart         # Great-circle, road distance, travel duration
│   ├── hlc.dart               # Monotonic Hybrid Logical Clock
│   └── kalman_filter.dart     # 2D Kalman GPS filter
├── data/
│   ├── database/
│   │   └── app_database.dart  # SQLite persistence (10 relational tables + FFI)
│   ├── models/                # To-do items, stores, routes, preferences, layout edges
│   └── sync/
│       ├── ha_websocket_client.dart # HA WebSocket client + mock test server
│       └── mutation_engine.dart     # LWW-HLC offline delta queue
├── services/
│   ├── distance_matrix_service.dart # Spatial caching & displacement checks
│   ├── geofence_engine.dart         # 40m/80m dual-ring hysteresis state machine
│   ├── layout_learning_engine.dart  # Cycle elimination (FAS) & Kahn's DAG sort
│   └── vrp_solver.dart              # Multi-stop Hybrid VRPTW engine
├── state/
│   └── app_state.dart         # Central reactive ChangeNotifier
└── ui/
    ├── screens/
    │   ├── main_errand_screen.dart  # Reorderable errand list with visual overlays
    │   ├── route_plan_screen.dart   # Step-by-step itinerary & warning banners
    │   ├── map_view_screen.dart     # Spatial radar canvas with dual geofence rings
    │   ├── in_store_screen.dart     # Learned walk-order aisle checklist
    │   ├── stores_screen.dart       # Store management & interactive DAG viewer
    │   └── settings_screen.dart     # Home Assistant configuration & simulation sandbox
    ├── theme.dart             # Material 3 slate/dark aesthetic
    └── widgets/               # Radar canvas, geofence badges, reorderable tiles
```

---

## 🚀 Getting Started

### Prerequisites
* [Flutter SDK](https://flutter.dev) (v3.13.0+)
* Dart SDK (v3.13.0+)

### Setup & Run
```bash
# Clone the repository
git clone https://github.com/seeramsujay/errands-op.git
cd errands-op

# Install dependencies
flutter pub get

# Run test suite
flutter test

# Run application
flutter run
```

---

## 🧪 Verification & Tests
The test suite covers algorithmic verification across:
* **VRP Solver**: Verified perishable deferral, user hard locks, and closing hour relaxation cascades.
* **Layout Learning**: Verified Kahn's topological sort and Feedback Arc Set cycle elimination.
* **Geofencing**: Verified 2D Kalman noise rejection and 40m arrival hysteresis.
* **Sync Engine**: Verified HLC monotonic ordering and mutation queue draining.
* **Widgets**: Verified interaction badges and UI rendering.

```bash
flutter test
# 00:11 +10: All tests passed!
```

---

## 📄 License
MIT License. Crafted with precision for overpowered errand operations.
