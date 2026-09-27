# Implementation Roadmap & Milestones

| Phase | Milestone Objective | Key Deliverables & Modules | Success Criteria |
| :--- | :--- | :--- | :--- |
| **Phase 1** | **Base Sync & Local Persistence**[cite: 1] | • SQLite Schema with Drift ORM[cite: 1]<br>• Dual-channel Home Assistant WebSocket client (`todo/`)[cite: 1]<br>• LWW-HLC offline mutation engine[cite: 1] | Zero state loss during offline edits; delta sync latency < 200 ms upon reconnecting.[cite: 1] |
| **Phase 2** | **Routing Engine & Constraint Solver**[cite: 1] | • Geospatial Matrix engine (GraphHopper / Valhalla)[cite: 1]<br>• Background OR-Tools solver isolate[cite: 1]<br>• MILP VRPTW model with candidate disjunctions & thermal decay penalties[cite: 1]<br>• UI manual override lock toggles[cite: 1] | Route solve completed in < 1.5s for up to 10 candidate store stops.[cite: 1] |
| **Phase 3** | **Spatial Preferences & Layout Learning**[cite: 1] | • Dual-ring geofencing engine with hysteresis filtering[cite: 1]<br>• Timestamped check-off logger[cite: 1]<br>• DAG topological sort layout engine[cite: 1]<br>• Store-specific list view overlays[cite: 1] | In-store aisle sorting accuracy improves over 3 visit iterations per store layout.[cite: 1] |
