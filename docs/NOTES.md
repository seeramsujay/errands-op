# Engineering Notes, Pitfalls & Architectural Choices

## 1. Matrix API Cost & Throttling Mitigation
* **Geohash Caching**: Route matrix queries map coordinates to 6-character Geohashes (~1.2 km grid resolution)[cite: 1]. Results are stored locally with a 7-day TTL[cite: 1].
* **Displacement Thresholds**: Dynamic route recalculations trigger only when physical device displacement exceeds 500 meters from the previous route calculation[cite: 1].
* **Haversine Fallback**: When offline, travel duration matrices are computed using Haversine distances adjusted by a road network tortuosity multiplier ($\tau \approx 1.28$)[cite: 1].

## 2. Indoor Geofencing Noise Strategies
* GPS accuracy degrades inside concrete structures[cite: 1]. Avoid using a single-radius geofence to prevent "pinballing" in and out of the store.
* Enforce a **Dual-Ring Hysteresis**:
  * Inner Arrival: $40\text{m}$ radius + 120s dwell time requirement[cite: 1].
  * Outer Exit: $80\text{m}$ radius + 180s exit grace period[cite: 1].
* Filter incoming raw GPS locations through a 2D Kalman filter, discarding updates with horizontal accuracy worse than $30\text{m}$[cite: 1].

## 3. Human-in-the-Loop Manual Overrides
* **Never hide items**: Items flagged as perishable (or unsuggested for the current stop) must remain visible in the main list[cite: 1]. Use visual cues (e.g., greyed-out text, thermal icon tags)[cite: 1].
* **User Pins Take Priority**: Hard locks set by the user (e.g., "Must visit Stop A before Stop B") override solver optimizations[cite: 1]. If a manual lock results in arriving after store closing hours, keep the user's explicit order and show a non-intrusive warning toast[cite: 1].
