<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="errands-op - The Overpowered Errand Engine">
</p>

<p align="center">
  <a href="https://flutter.dev"><img src="https://img.shields.io/badge/Flutter-3.47.5-02569B?logo=flutter" alt="Flutter"></a>
  <a href="https://dart.dev"><img src="https://img.shields.io/badge/Dart-3.13.4-0175C2?logo=dart" alt="Dart"></a>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <a href="https://github.com/seeramsujay/errands-op"><img src="https://img.shields.io/badge/tests-64%20passing-brightgreen.svg" alt="Tests"></a>
  <a href="https://www.home-assistant.io"><img src="https://img.shields.io/badge/Home%20Assistant-WebSocket%20Sync-41BDF5?logo=home-assistant" alt="Home Assistant"></a>
</p>

<p align="center">
  <b>errands-op</b> is an offline-first, algorithmic errand routing engine. It bridges Home Assistant to-do lists, solves multi-stop Vehicle Routing Problems with Time Windows (VRPTW), prevents false GPS triggers with dual-ring hysteresis geofencing, and learns in-store aisle walk-orders through Feedback Arc Set cycle elimination and topological sorting.
</p>

---

## ⚡ Why errands-op?

Most errand organizers either force-sort your personal list into an unfamiliar sequence or ignore the practical realities of shopping—such as frozen groceries melting while you visit the hardware store, or GPS bouncing while driving by a plaza.

<p align="center">
  <img src="./assets/readme/comparison.svg" width="100%" alt="Traditional Errand Apps vs errands-op">
</p>

---

## 🏗️ System Architecture

`errands-op` executes a closed-loop four-stage mathematical pipeline:

<p align="center">
  <img src="./assets/readme/architecture.svg" width="100%" alt="errands-op Closed-Loop Mathematical Engine Pipeline">
</p>

### 1. Home Assistant Sync & Hybrid Logical Clocks
- Bi-directional sync with any Home Assistant to-do entity over `/api/websocket` (`todo/item/subscribe` snapshots + `todo.add_item` / `update_item` / `remove_item`), matched by HA's item `uid`. Remote adds, renames, completions and deletions flow in; items from voice assistants get a category and perishable flag guessed from their text.
- Offline-first mutation queue ordered by **Hybrid Logical Clocks (HLC)**, compacted per item/field, with **Last-Write-Wins (LWW)**: unsent local edits win over incoming snapshots. Order, pins, categories and perishable flags stay local.
- Exponential backoff with random jitter and a 30 s heartbeat; a rejected token stops retrying and is shown in Settings.

### 2. Hybrid VRPTW Multi-Stop Sequence Solver
- **Exact label-setting DP**: Store choice and visit order are solved *jointly* by a dynamic program over (tasks covered, last store) with Pareto pruning on (time, cost), run on a background isolate. Lists with more than 12 distinct tasks fall back to a greedy cost-per-task heuristic.
- **Disjunctive Candidate Matching**: Each item can be served by any store stocking its category; one stop can serve several categories. Strongly learned favourite stores filter out the rest, weaker preferences act as a soft cost.
- **Time Windows**: Arrives early → waits for opening ($\beta$ wait penalty); service must finish before closing. Overnight hours (e.g. 18:00–02:00) are supported.
- **Thermal Decay Penalty**: $\gamma = 0.5$ per perishable item per second carried until you're home, so cold items are bought late — even if it means buying them at a different store than the rest.
- **Human Hard Sequence Locks**: A pinned (📌) item is never served after anything listed below it ($t_A + s_A + C_{AB} \le t_B$).
- **Constraint Relaxation Cascade**: If no route meets every closing time (e.g. because of pins), windows become soft penalties, the pinned order is kept, and each late stop gets an explicit warning.
- **Distance Matrix**: Optional OSRM-compatible routing server with geohash-6 caching (7-day TTL); otherwise Haversine × road tortuosity ($\tau = 1.28$) at ~40 km/h. The route includes the trip home.

### 3. Dual-Ring Hysteresis Geofencing State Machine
- **2D Kalman GPS Filter**: Discards noisy fixes with horizontal accuracy $\sigma > 30\text{m}$.
- **Inner Arrival Ring** (each store's own radius, 40 m by default): requires a continuous $120\text{s}$ dwell before transitioning to `INSIDE_STORE` mode.
- **Outer Exit Ring** (2 × the arrival radius): an exit grace buffer of $180\text{s}$ prevents premature session termination when walking through store dead zones. Distances are always measured to the store you are in, so a neighbouring shop can't hold or end your visit.
- Live GPS via `geolocator` (Android/iOS/macOS); visits left open by an app restart are resumed or closed.

### 4. Learned In-Store Layout Walk-Order (DAG)
- Observes real timestamped item check-offs inside stores ($\tau_1 < \tau_2 < \dots < \tau_m$).
- Computes exponential decay precedence weights: $w(\Delta \tau) = \exp(-(\tau_B - \tau_A)/\sigma)$ and **accumulates** them as evidence per store (both directions are kept).
- **Net DAG + Feedback Arc Set (FAS)**: Opposite directions cancel out; remaining cycles are broken by cutting the edge with the least evidence.
- **Kahn's Topological Sort**: Produces the empirical walk order; categories the store hasn't learned yet keep your own list order.

---

## 📱 Application Screens

| Screen | Responsibility |
| :--- | :--- |
| **Main Errand List** | Reorderable list preserving manual sequence (also while filtered), tap-to-edit, non-destructive overlay badges (`Stop #1`, `Stop #2`), filter chips, and "I'm Going Out" solver CTA. |
| **Route Itinerary** | Step-by-step timeline with arrival estimates, closing hour conflict alerts, and travel distances. |
| **Radar Map** | Interactive radar canvas rendering GPS fix, store nodes, route polylines, and dual geofence rings ($40\text{m} / 80\text{m}$). |
| **In-Store Shopping Mode** | Auto-triggered upon geofence dwell. Groups items by store aisle and sorts them via the learned DAG toposort. |
| **Stores & DAG** | Add, edit and delete stores (location, hours, time spent, categories, arrival radius) and inspect each store's learned walk graph. |
| **Settings & Simulator** | Home Assistant connection, live GPS, home location, optional routing server, and a sandbox to simulate GPS fixes, store visits and remote HA items. |

---

## 🚀 Quick Start

### Prerequisites
- [Flutter SDK](https://flutter.dev) 3.47+ (Dart 3.13+)
- Android: Android SDK (API 36) — `flutter doctor` lists anything missing
- Linux desktop: `sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsqlite3-dev`
- The web target is not supported (local data lives in SQLite).

### Setup & Run
```bash
git clone https://github.com/seeramsujay/errands-op.git
cd errands-op
flutter pub get
flutter test               # 64 tests
flutter run                # connected phone or desktop
flutter build apk --release
```

### First-time setup in the app
1. **Stores & DAG → Add Store** for the shops and offices you use (the five Bangalore stores are sample data).
2. **Settings → Location**: set your home (route start/end) and turn on **Live GPS**.
3. **Settings → Home Assistant** (optional): paste your HA URL (e.g. `http://homeassistant.local:8123`), a long-lived access token (HA → Profile → Security) and the to-do entity (default `todo.shopping_list`). Items you added before connecting are pushed on first connect.
4. Optional: an OSRM server URL for real road travel times.

---

## 🧪 Test Suite

```bash
flutter test
# 00:06 +64: All tests passed!
# - vrp_solver_test        joint store choice, thermal deferral, waiting for opening, closing-time ordering,
#                          pins & relaxation cascade, overnight hours, heuristic fallback, <1.5 s for 12 tasks
# - layout_learning_test   Kahn's sort, FAS, evidence accumulation, end-to-end visit learning
# - geofence_engine_test   Kalman gating, dwell/grace timing, neighbouring stores, per-store radius, restart recovery
# - sync_engine_test       real WebSocket against a fake Home Assistant: auth, snapshots, uid adoption,
#                          remote deletes, offline queue compaction, bad token, reconnect
# - app_state_test         filtered reorder, editing, overlays, persisted routes, store CRUD, reset
# - database_test          v1 → v2 migration, seeding, retry parking, category classifier
# - widget_test / app_smoke_test   item tile, full app boot + every tab at phone width
```

---

## 📄 License

Distributed under the MIT License. See [LICENSE](LICENSE) for more details.
