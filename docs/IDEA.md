# Product Specification: Overpowered Errand Engine

## Core Philosophy: Human-in-the-Loop Optimization
The Overpowered Errand Engine is an open-source, spatial shopping and errand assistant designed to handle the heavy math of multi-stop routing without taking control away from the user. 

Unlike rigid automation systems, this app treats algorithmic suggestions as **non-destructive visual overlays**. The user maintains 100% manual control over list items, store selections, and visit sequences at all times. The app makes life easier—it does not dictate it.

---

## Key Features & User Experience

### 1. Unified & Accessible Shopping List
* **Direct Primary Control**: View, edit, add, and manually drag-and-drop items into any order. The primary list view never hides items or locks sequence states.
* **Home Assistant Sync**: Real-time bidirectional sync with Home Assistant `todo` entities. Edits made at home or via voice assistant instantly update on-device.

### 2. Spatial Errand Planning & Route Engine
* **"I'm Going Out" Trigger**: Open the app, tap "Going Out," and the engine evaluates candidate stores and errand stops (e.g., getting passport signed, visiting RTO, buying brake wire).
* **Multi-Store & Fixed Stop Optimization**: Distinguishes between fixed-location time-sensitive stops (like administrative offices) and flexible item buys across multiple candidate markets (e.g., DMart vs. Star Bazaar).
* **Dynamic Time & Delay Factor**: Considers travel time, traffic, opening hours, and estimated in-store wait times.
* **Perishable Item Handling**: Logic flags items like ice cream or cold fresh goods. These stay visible on your main list but are dimmed/greyed out with thermal tags, reserving them for the final leg of your itinerary so they don’t melt while you run administrative errands.

### 3. Store Preference & In-Store Layout Learning
* **Preference Tracking**: When an item is checked off within a store’s geofence, a counter increments for that item-store pair. Over time, the route solver automatically prefers your favorite stores for specific goods.
* **In-Store Aisle Order Sorting**: The app records the check-off order and time deltas ($\Delta T$) between items during a shop. It builds a directed walk-graph of the store layout. On your next visit to that shop, items on your active list automatically sort in the exact sequence you historically walk the store.
