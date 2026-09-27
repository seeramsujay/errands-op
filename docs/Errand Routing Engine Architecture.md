# **Technical Specification and System Architecture for the Overpowered Errand Engine**

## **Open-Source Framework and Ecosystem Map**

Developing a local-first mobile application for multi-stop errand optimization requires an architecture that cleanly separates user interaction, geospatial calculation, constraint-based operations research, and asynchronous synchronization. The system architecture of the Overpowered Errand Engine is built around a non-destructive state model: machine learning and vehicle routing models suggest optimizations as visual overlays, ensuring that user manual ordering remains preserved.  
`+-----------------------------------------------------------------------------------+`  
`|                                 MOBILE APPLICATION                                |`  
`|                                                                                   |`  
`|  +-----------------------+    Local Mutations    +-----------------------------+  |`  
`|  |   UI / User Action    | --------------------> |   Local Database Engine     |  |`  
`|  |  (Human-in-the-Loop)  | <-------------------- | (SQLite / Drift / Watermelon|  |`  
`|  +-----------------------+    Visual Overlays    +-----------------------------+  |`  
`|                                                               ^                   |`  
`|                                                               | Delta Reconcile   |`  
`|                                                               v                   |`  
`|                                                  +-----------------------------+  |`  
`|                                                  |   Sync Engine & Queue       |  |`  
`|                                                  +-----------------------------+  |`  
`+-----------------------------------------------------------------|-----------------+`  
                                                                  `|`  
                                              `WebSocket / REST    | WS: /api/websocket`  
                                              `(todo domain)       | Sub: todo/item/subscribe`  
                                                                  `v`  
                                                   `+-----------------------------+`  
                                                   `| Home Assistant Core Instance|`  
                                                   `+-----------------------------+`

### **Mobile Frameworks and Home Assistant Integration Wrappers**

The choice of mobile application core dictates how efficiently background geospatial processing, local storage, and thread communication execute without impacting user interface responsiveness.

#### **Flutter Framework**

Using Flutter with the Drift (SQLite) ORM provides strong support for offline-first data architectures. Flutter compiles natively to C/C++ binaries on both iOS and Android, offering performance benefits for background routing calculations. Drift enables reactive SQL queries that stream directly to UI widgets, ensuring that list state updates render instantly.  
Dart isolates allow running constraint solvers and matrix operations on background threads, preventing main UI thread stutter during heavy route solves. Communicating with Home Assistant requires a custom WebSocket client built over web\_socket\_channel to interact directly with Home Assistant’s /api/websocket endpoint. This architecture supports listening to todo/item/subscribe event streams and issuing todo/update\_item payloads without additional bridge dependencies.

#### **React Native Framework**

React Native with WatermelonDB offers a flexible, lazy-loaded relational database model over SQLite via C++ JSI bindings. WatermelonDB handles large lists by loading items lazily, reducing memory overhead when operating on large store inventory or historical check-off datasets.  
The official home-assistant-js-websocket library simplifies authentication, state management, and real-time event subscriptions. However, running optimization workloads in React Native requires offloading execution to native C++ threads or external web workers to keep JavaScript event loops responsive during intensive matrix operations.

### **Geospatial Routing Engines and Distance Matrix Processors**

Calculating routes across multiple stops requires a routing engine capable of rapidly generating N \\times N travel time and distance matrices. Because mobile errand planning involves evaluating candidate stores dynamically, the routing engine must handle matrix calculations with low latency.

| Routing Engine | Primary Language | Algorithm Base | Memory Footprint | Matrix Query Latency | Dynamic Edge Weighting |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **OSRM (Open Source Routing Machine)** | C++ | Contraction Hierarchies (CH) | 4 GB \- 8 GB (High) | Sub-millisecond (Ultra-Fast) | Low (Requires graph re-processing) |
| **GraphHopper** | Java | CH & Landmark (LM) Routing | 1 GB \- 3 GB (Medium) | 2 ms \- 15 ms (Fast) | High (Dynamic profiles supported via LM) |
| **Valhalla** | C++ | Tile-based Dynamic Graph | 500 MB \- 1.5 GB (Low) | 5 ms \- 25 ms (Moderate) | High (Real-time dynamic costing) |
| **Openrouteservice** | Java (GraphHopper Core) | CH & Landmark Routing | 2 GB \- 4 GB (Medium-High) | 5 ms \- 20 ms (Fast) | High (Advanced profile customization) |

OSRM delivers fast matrix evaluations via Contraction Hierarchies, but its static graph preprocessing makes dynamic adjustments (such as adding turn penalties or live traffic modifications) difficult without rebuilding dataset tiles. GraphHopper provides a balanced alternative by combining Contraction Hierarchies for static lookups with Landmark routing for dynamic edge weighting.  
Valhalla uses a memory-mapped tile architecture with a lower memory footprint, making it suitable for deployment on low-cost edge servers or embedded directly within local network environments.

### **Operations Research and Vehicle Routing Solvers**

Solving the hybrid errand routing problem requires balancing vehicle routing constraints, time windows, candidate node choices, and thermal decay penalties.

| Solver Library | Core Architecture | Disjunction & Candidate Selection | Time Window Support (VRPTW) | Custom Penalty Integration | Execution Footprint |
| :---- | :---- | :---- | :---- | :---- | :---- |
| **Google OR-Tools** | C++ with CP-SAT & Local Search | Native (AddDisjunction) | Fully supported via dimension bounds | High (Supports custom cost evaluator functions) | Compiles to native binary / isolate worker |
| **VROOM** | C++ Local Search Heuristics | Limited (Requires pre-selected nodes) | Supported via strict job time windows | Low (Fixed objective functions) | Lightweight C++ execution |
| **PyVRP** | Python / C++ Hybrid Genetic Search | Supported via optional clients & prize collecting | Supported | Medium (Extensible metaheuristic callbacks) | Requires Python runtime environment |

Google OR-Tools provides explicit support for disjunctive node choices (solver.AddDisjunction(\[nodes\], penalty)), allowing the algorithm to select the single best store location from a set of candidate nodes to satisfy an item request. It also supports custom cost evaluations, making it straightforward to add thermal decay penalties for perishable items.  
VROOM delivers high execution speeds for fixed-destination VRP instances, but its lack of native disjunctive choice logic makes it less suitable for solving candidate choice problems directly. PyVRP implements Hybrid Genetic Search algorithms for vehicle routing, but running its Python runtime on mobile clients introduces performance overhead.

## **Mathematical Formulations and Spatial Algorithms**

### **Mixed-Integer Linear Programming Formulation for Hybrid VRPTW**

The route optimization problem is modeled as a Hybrid Vehicle Routing Problem with Time Windows, Candidate Choice Disjunctions, and Perishable Thermal Decay Penalties.

#### **Node Sets and Indices**

> * Let \\mathcal{V}\_0 \= \\{0\\} be the starting origin node (the user's current spatial position).  
> * Let \\mathcal{V}\_{n+1} \= \\{n+1\\} be the terminal destination node (the user's home location).  
> * Let \\mathcal{K} \= \\{1, 2, \\dots, K\\} be the set of requested errand tasks.  
> * For each task k \\in \\mathcal{K}, let \\mathcal{S}\_k be the non-empty set of candidate store nodes capable of fulfilling task k.  
> * The full graph node set is defined as \\mathcal{V} \= \\mathcal{V}\_0 \\cup \\left( \\bigcup\_{k \\in \\mathcal{K}} \\mathcal{S}\_k \\right) \\cup \\mathcal{V}\_{n+1}.  
> * Let \\mathcal{E} \= \\{(i, j) \\mid i, j \\in \\mathcal{V}, i \\neq j\\} represent the set of directed spatial travel edges connecting nodes.

#### **Parameters**

> * C\_{ij} \\ge 0: Travel time duration in seconds between node i and node j, extracted from the geospatial matrix engine.  
> * D\_{ij} \\ge 0: Physical distance in meters between node i and node j.  
> * \[e\_i, l\_i\]: Hard opening time e\_i and closing time l\_i for node i.  
> * s\_i \\ge 0: Service time required at node i (e.g., standard in-store shopping duration).  
> * p\_k \\in \\{0, 1\\}: Binary indicator flag equal to 1 if task k involves temperature-sensitive or perishable items, and 0 otherwise.  
> * \\alpha \[span\_14\](start\_span)\[span\_14\](end\_span)\\in \[0, 1\]: Weighting factor balancing travel duration versus physical travel distance.  
> * \\beta \\ge 0: Penalty coefficient applied per unit of wait time spent at early-arriving stops.  
> * \\gamma \\ge 0: Thermal decay coefficient penalizing elapsed transit time while carrying perishable items.  
> * M: A large positive scalar value (Big-M formulation).

#### **Decision Variables**

> * x\_{ij} \\in \\{0, 1\\}: Binary decision variable equal to 1 if travel occurs directly along edge (i, j), and 0 otherwise.  
> * y\_i \\in \\{0, 1\\}: Binary indicator variable equal to 1 if candidate store node i \\in \\bigcup \\mathcal{S}\_k is visited, and 0 otherwise.  
> * t\_i \\ge 0: Continuous variable representing the arrival timestamp at node i.  
> * w\_i \\ge 0: Continuous variable representing wait time at node i prior to opening time e\_i.  
> * q\_i \\ge 0: Accumulation variable representing the total quantity of perishable items carried upon departing node i.

#### **Objective Function Formulation**

\\min Z \= \\sum\_{(i,j) \\in \\mathcal{E}} \\left( \\alpha C\_{ij} \+ (1-\\alpha) D\_{ij} \\right) x\_{ij} \+ \\sum\_{i \\in \\mathcal{V}} \\beta w\_i \+ \\sum\_{i \\in \\mathcal{V} \\setminus \\{n+1\\}} \\gamma q\_i \\left( t\_{n+1} \- (t\_i \+ s\_i) \\right)  
The objective minimizes a combined function of travel duration, physical distance, waiting time penalties at early stops, and thermal decay penalties accumulated from carrying perishable goods before reaching the final destination.

#### **Constraints**

> 1. Candidate Selection Disjunction: \\sum\_{i \\in \\mathcal{S}\_k} y\_i \= 1 \\quad \\forall k \\in \\mathcal{K}  
> 2. Flow Balance across Selected Store Nodes: \\sum\_{j \\in \\mathcal{V}, j \\neq i} x\_{ji} \= y\_i \\quad \\forall i \\in \\bigcup\_{k \\in \\mathcal{K}} \\mathcal{S}\_k \\sum\_{j \\in \\mathcal{V}, j \\neq i} x\_{ij} \= y\_i \\quad \\forall i \\in \\bigcup\_{k \\in \\mathcal{K}} \\mathcal{S}\_k  
> 3. Route Origin and Destination Flow Constraints: \\sum\_{j \\in \\mathcal{V} \\setminus \\{0\\}} x\_{0,j} \= 1, \\quad \\sum\_{i \\in \\mathcal{V} \\setminus \\{n+1\\}} x\_{i, n+1} \= 1  
> 4. Arrival Precedence, Time Windows, and Subtour Elimination: t\_i \+ s\_i \+ w\_i \+ C\_{ij} \- t\_j \\le M(1 \- x\_{ij}) \\quad \\forall (i, j) \\in \\mathcal{E} e\_i \\le t\_i \+ w\_i \\le l\_i \\quad \\forall i \\in \\mathcal{V} w\_i \\ge e\_i \- t\_i \\quad \\text{and} \\quad w\_i \\ge 0 \\quad \\forall i \\in \\mathcal{V}  
> 5. Perishable Load Propagation: q\_j \\ge q\_i \+ \\sum\_{k \\in \\mathcal{K} : j \\in \\mathcal{S}\_k} p\_k \- M(1 \- x\_{ij}) \\quad \\forall (i, j) \\in \\mathcal{E} q\_0 \= 0  
> 6. Manual Sequence Order Constraints (Hard Locks): If a user explicitly pins stop A to be visited before stop B, the system enforces: t\_A \+ s\_A \+ C\_{AB} \\le t\_B

### **Algorithmic Sequence Reconstruction for In-Store Walk-Order Learning**

In-store navigation auto-sorts item lists based on learned user walking paths without requiring manual layout mapping. When shopping inside a store geofence S, the application records item check-off events with timestamps: W \= \\{(a\_1, \\tau\_1), (a\_2, \\tau\_2), \\dots, (a\_m, \\tau\_m)\\}, where \\tau\_1 \< \\tau\_2 \< \\dots \< \\tau\_m.  
`+-----------------------------------------------------------------------------------+`  
`|                   WALK-ORDER RECONSTRUCTION PIPELINE                              |`  
`+-----------------------------------------------------------------------------------+`  
`|                                                                                   |`  
`|                   [ Raw Check-Off Log: (Item, Timestamp) ]                        |`  
`|                                         |                                         |`  
`|                                         v                                         |`  
`|                     [ Build Directed Precedence Matrix P ]                        |`  
`|                    (Filter deltas via time-decay weighting)                       |`  
`|                                         |                                         |`  
`|                                         v                                         |`  
`|                   [ Construct Probabilistic Graph G = (V, E) ]                    |`  
`|                        (Edge weights w(A->B) = P[A][B])                           |`  
`|                                         |                                         |`  
`|                                         v                                         |`  
`|                   [ Feedback Arc Set Cycle Elimination ]                          |`  
`|                       (Remove lowest weight edge loops)                           |`  
`|                                         |                                         |`  
`|                                         v                                         |`  
`|                     [ Kahn's Algorithm Topological Sort ]                         |`  
`|                     (Derive optimized in-store walk order)                        |`  
`|                                                                                   |`  
`+-----------------------------------------------------------------------------------+`

#### **Graph Construction and Time-Decay Weighting**

Historical visit logs are aggregated into a weighted precedence matrix P, where P\[A\]\[B\] measures the empirical likelihood that item category A is picked before item category B. The influence of time deltas (\\Delta \\tau \= \\tau\_B \- \\tau\_A) is weighted using an exponential decay function:  
w(\\Delta \\tau) \= \\begin{cases} \\exp\\left(-\\frac{\\tau\_B \- \\tau\_A}{\\sigma}\\right) & \\text{if } 0 \< \\tau\_B \- \\tau\_A \\le \\Delta \\tau\_{\\max} \\\\ 0 & \\text{otherwise} \\end{cases}  
This weighting minimizes the effect of non-linear walking paths, such as backtracking across the store for forgotten items.

#### **Cycle Elimination and Topological Sorting**

Random backtracking can introduce directed cycles into the learned adjacency matrix. To produce a deterministic sort order, directed cycles are removed using a greedy Feedback Arc Set heuristic prior to running Kahn’s topological sorting algorithm.  
`def generate_store_sort_order(item_categories, precedence_matrix, confidence_threshold=0.1):`  
    `"""`  
    `Transforms historical check-off precedence matrix into a deterministic`  
    `in-store layout walk order using topological sorting over a DAG.`  
    `"""`  
    `nodes = set(item_categories)`  
    `adj_matrix = {u: {v: 0.0 for v in nodes} for u in nodes}`  
    `in_degree = {u: 0 for u in nodes}`

    `# 1. Populate initial edge weights based on relative precedence confidence`  
    `for u in nodes:`  
        `for v in nodes:`  
            `if u != v:`  
                `forward_w = precedence_matrix.get(u, {}).get(v, 0.0)`  
                `backward_w = precedence_matrix.get(v, {}).get(u, 0.0)`  
                `delta_w = forward_w - backward_w`  
                `if delta_w > confidence_threshold:`  
                    `adj_matrix[u][v] = delta_w`

    `# 2. Iteratively break directed cycles via Feedback Arc Set reduction`  
    `def extract_cycle(start_node, visited, stack, graph):`  
        `visited.add(start_node)`  
        `stack.add(start_node)`  
        `for neighbor, w in graph[start_node].items():`  
            `if w > 0:`  
                `if neighbor not in visited:`  
                    `res = extract_cycle(neighbor, visited, stack, graph)`  
                    `if res:`  
                        `return res`  
                `elif neighbor in stack:`  
                    `return [neighbor, start_node]`  
        `stack.remove(start_node)`  
        `return None`

    `while True:`  
        `cycle_found = False`  
        `for node in list(nodes):`  
            `visited_set, stack_set = set(), set()`  
            `cycle = extract_cycle(node, visited_set, stack_set, adj_matrix)`  
            `if cycle:`  
                `cycle_found = True`  
                `# Identify and sever the weakest link in the detected cycle`  
                `u_target, v_target = cycle[1], cycle[0]`  
                `adj_matrix[u_target][v_target] = 0.0`  
                `break`  
        `if not cycle_found:`  
            `break`

    `# 3. Calculate in-degrees for DAG topological sort`  
    `for u in nodes:`  
        `for v in nodes:`  
            `if adj_matrix[u][v] > 0:`  
                `in_degree[v] += 1`

    `# 4. Kahn's Algorithm for deterministic layout derivation`  
    `zero_in_queue = [n for n in nodes if in_degree[n] == 0]`  
    `sorted_layout = []`

    `while zero_in_queue:`  
        `# Sort queue by item category popularity to handle ties deterministically`  
        `zero_in_queue.sort()`  
        `curr = zero_in_queue.pop(0)`  
        `sorted_layout.append(curr)`

        `for neighbor, w in adj_matrix[curr].items():`  
            `if w > 0:`  
                `in_degree[neighbor] -= 1`  
                `if in_degree[neighbor] == 0:`  
                    `zero_in_queue.append(neighbor)`

    `# 5. Append isolated or unvisited nodes to ensure complete output`  
    `for item in item_categories:`  
        `if item not in sorted_layout:`  
            `sorted_layout.append(item)`

    `return sorted_layout`

## **System Architecture, Flow Control, and Database Schema**

### **Database Schema Specification**

The local database serves as the source of truth for offline operations, caching remote state, storing historical check-off events, and persisting learned layout models.  
`-- Home Assistant Synced To-Do Items`  
`CREATE TABLE items (`  
    `id TEXT PRIMARY KEY NOT NULL,`  
    `ha_entity_id TEXT NOT NULL,`  
    `summary TEXT NOT NULL,`  
    `description TEXT,`  
    `category TEXT DEFAULT 'generic',`  
    `is_perishable INTEGER NOT NULL DEFAULT 0 CHECK (is_perishable IN (0, 1)),`  
    `status TEXT NOT NULL DEFAULT 'needs_action' CHECK (status IN ('needs_action', 'completed')),`  
    `human_order_index INTEGER NOT NULL,`  
    `optimized_order_index INTEGER,`  
    `is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),`  
    `created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,`  
    `updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP`  
`);`

`-- Store Master Entities`  
`CREATE TABLE stores (`  
    `id TEXT PRIMARY KEY NOT NULL,`  
    `name TEXT NOT NULL,`  
    `brand TEXT,`  
    `latitude REAL NOT NULL,`  
    `longitude REAL NOT NULL,`  
    `geofence_radius_meters REAL NOT NULL DEFAULT 50.0,`  
    `opening_time_sec INTEGER,`  
    `closing_time_sec INTEGER,`  
    `avg_checkout_delay_sec INTEGER DEFAULT 600`  
`);`

`-- Item Category to Store Preference Counter`  
`CREATE TABLE item_store_preferences (`  
    `id TEXT PRIMARY KEY NOT NULL,`  
    `item_category TEXT NOT NULL,`  
    `store_id TEXT NOT NULL,`  
    `selection_count INTEGER NOT NULL DEFAULT 1,`  
    `confidence_score REAL NOT NULL DEFAULT 0.5,`  
    `FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE`  
`);`

`-- Historical In-Store Visit Records`  
`CREATE TABLE visits (`  
    `id TEXT PRIMARY KEY NOT NULL,`  
    `store_id TEXT NOT NULL,`  
    `entry_timestamp DATETIME NOT NULL,`  
    `exit_timestamp DATETIME,`  
    `FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE`  
`);`

`-- In-Store Check-Off Event Timestamps`  
`CREATE TABLE visit_checkoffs (`  
    `id TEXT PRIMARY KEY NOT NULL,`  
    `visit_id TEXT NOT NULL,`  
    `item_id TEXT NOT NULL,`  
    `checkoff_timestamp DATETIME NOT NULL,`  
    `FOREIGN KEY (visit_id) REFERENCES visits(id) ON DELETE CASCADE,`  
    `FOREIGN KEY (item_id) REFERENCES items(id) ON DELETE CASCADE`  
`);`

`-- Directed Store Layout Graph`  
`CREATE TABLE store_layout_edges (`  
    `store_id TEXT NOT NULL,`  
    `from_item_category TEXT NOT NULL,`  
    `to_item_category TEXT NOT NULL,`  
    `forward_weight REAL NOT NULL DEFAULT 0.0,`  
    `sample_size INTEGER NOT NULL DEFAULT 0,`  
    `PRIMARY KEY (store_id, from_item_category, to_item_category),`  
    `FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE`  
`);`

`-- Active Route Executions`  
`CREATE TABLE active_routes (`  
    `id TEXT PRIMARY KEY NOT NULL,`  
    `generated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,`  
    `total_distance_meters REAL NOT NULL,`  
    `total_duration_seconds REAL NOT NULL,`  
    `solver_status TEXT NOT NULL`  
`);`

`CREATE TABLE route_stops (`  
    `id TEXT PRIMARY KEY NOT NULL,`  
    `route_id TEXT NOT NULL,`  
    `stop_sequence INTEGER NOT NULL,`  
    `store_id TEXT NOT NULL,`  
    `estimated_arrival DATETIME NOT NULL,`  
    `estimated_departure DATETIME NOT NULL,`  
    `is_completed INTEGER NOT NULL DEFAULT 0 CHECK (is_completed IN (0, 1)),`  
    `FOREIGN KEY (route_id) REFERENCES active_routes(id) ON DELETE CASCADE,`  
    `FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE`  
`);`

`-- Indices for Low-Latency Spatial and Status Lookups`  
`CREATE INDEX idx_items_status ON items(status);`  
`CREATE INDEX idx_stores_spatial ON stores(latitude, longitude);`  
`CREATE INDEX idx_edges_lookup ON store_layout_edges(store_id, from_item_category);`

### **Event-Driven System Architecture and Inter-Module Workflow**

System actions process asynchronously through an event-driven architecture that keeps the UI responsive while managing network synchronization, location tracking, and route recalculation.

| Event Type | Trigger Origin | Event Pipeline Action | Target System Component |
| :---- | :---- | :---- | :---- |
| **Manual Item Reorder** | Primary UI Touch Drag | Updates human\_order\_index locally; sets is\_pinned \= 1; dispatches background route recalculation. | Local SQLite DB & Route Solver Worker |
| **HA Entity Change** | Inbound WebSocket Stream | Applies delta updates locally; preserves human indices; updates UI visual state. | Local DB Sync Engine & Main UI Thread |
| **Location Update** | Device GPS Service | Filters noise via Kalman filter; checks proximity against candidate store stops. | Geofence Listener Module |
| **Store Entry Event** | Geofence Boundary Check | Registers active visit log; applies store-specific walk order to item list views. | Visits Module & Main UI Visual Overlay |
| **Item Check-Off** | In-Store User Interaction | Records timestamped check-off event; updates store preference counters. | Layout Learning Engine & Local DB |
| **Store Exit Event** | Geofence Exit Boundary | Closes visit log; triggers asynchronous layout reconstruction graph update. | Layout Learning Worker Module |
| **Route Re-Solve** | Item List / Pin Modification | Fetches travel matrix; solves MILP model; updates proposed route overlays. | OR-Tools Worker Thread & Route UI Overlay |

## **Operational Playbook and Edge-Case Strategies**

### **Indoor Geofencing Noise and Signal Degradation**

Indoor locations often degrade GPS accuracy, leading to position drift that can cause false geofence exits and disrupt visit logging.  
`+-----------------------------------------------------------------------------------+`  
`|                        GEOFENCE STATE MACHINE & HYSTERESIS                        |`  
`+-----------------------------------------------------------------------------------+`  
`|                                                                                   |`  
`|                                 [ OUTSIDE STORE ]                                 |`  
`|                                         |                                         |`  
`|                 Raw GPS Position Entry  | Distance <= Geofence Radius             |`  
`|                 + Accuracy <= 30m       v                                         |`  
`|                                                                                   |`  
`|                                 [ PENDING ENTRY ]                                 |`  
`|                                         |                                         |`  
`|                 Dwell Timer Expires     | Continuous Presence for                 |`  
`|                 (t >= 120 sec)          v                                         |`  
`|                                                                                   |`  
`|                                  [ INSIDE STORE ]                                 |`  
`|                                  (Start Visit Log)                                |`  
`|                                         |                                         |`  
`|                 Signal Jitter / Drift   | Distance > Outer Radius                 |`  
`|                 (Temporary Out-of-Bounds)v (Radius + 40m Buffer)                  |`  
`|                                                                                   |`  
`|                                 [ PENDING EXIT ]                                  |`  
`|                                         |                                         |`  
`|           +-----------------------------+-----------------------------+           |`  
`|           | Re-enters Inner Radius                                    | Grace     |`  
`|           v                                                           v Period    |`  
`|   [ INSIDE STORE ]                                            [ FINAL EXIT ]      |`  
`|  (Cancel Exit Timer)                                      (Close Visit Record &   |`  
`|                                                            Trigger Layout Update) |`  
`|                                                                                   |`  
`+-----------------------------------------------------------------------------------+`

#### **Dual-Ring Hysteresis Geofencing**

Geofences use two boundary rings rather than a single radius. An *Inner Arrival Boundary* (R\_{\\text{in}} \= 40\\text{ meters}) triggers a PENDING\_ENTRY state, while an *Outer Exit Boundary* (R\_{\\text{out}} \= 80\\text{ meters}) governs exit detection.

#### **Temporal Dwell Thresholds**

Entry events require staying within R\_{\\text{in}} for at least 120 continuous seconds before transitioning to INSIDE\_STORE. Exit events require staying outside R\_{\\text{out}} for at least 180 continuous seconds (*Exit Grace Period*). If GPS lock is lost inside a building, the application maintains the INSIDE\_STORE state until clear location fixes resume.

#### **Adaptive Kalman Filtering**

Incoming GPS positions pass through a 2D Kalman filter that weights updates based on reported horizontal accuracy (H\_{\\text{acc}} \\le 30\\text{m}). Low-accuracy updates are discarded before reaching the geofencing engine.

### **Network Disruption and Sync Reconciliation**

When operating in locations with poor cellular coverage, local modifications are queued and reconciled automatically once connectivity resumes.  
\#\#\#\# Local Mutation Queuing All list modifications append to a local mutation queue table inside a single database transaction. The primary UI updates optimistically, remaining fully interactive.

#### **Synchronization and Backoff**

The sync engine uses exponential backoff with jitter to retry connections without overloading the server:

T\_{\\text{retry}} \= \\min\\left(T\_{\\max}, T\_{\\text{base}} \\cdot 2^{\\text{attempt}} \+ \\text{rand}(0, 1000\\text{ms})\\right)

#### **Conflict Resolution**

When reconnecting, local mutations submit as atomic delta operations (item\_id, field, value, hlc\_timestamp) rather than full list states. Conflicts between concurrent edits are resolved using Hybrid Logical Clocks (HLC) with Last-Write-Wins (LWW) semantics.

### **Matrix API Cost and Rate Limit Throttling**

To minimize latency and prevent excessive requests to matrix APIs, travel distance queries are managed through caching and displacement limits.

#### **Geohash Spatial Caching**

Coordinates map to 6-character Geohashes (\~1.2 km precision grids). Matrix pairs (G\_{\\text{origin}}, G\_{\\text{destination}}) are stored in a local SQLite cache table with a 7-day TTL.

#### **Spatial Displacement Thresholding**

Automatic route recalculations are suppressed unless the user's physical position changes by more than 500 meters from the path used in the previous solve run.

#### **Local Distance Fallback**

When offline, matrices are estimated locally using Haversine formulas scaled by a local road network tortuosity factor (\\tau \\approx 1.28).  
`def calculate_fallback_matrix(nodes, tortuosity=1.28, avg_speed_m_s=11.1):`  
    `"""`  
    `Computes an estimated travel duration and distance matrix locally`  
    `using Haversine calculations adjusted by a tortuosity factor.`  
    `"""`  
    `import math`  
    `n = len(nodes)`  
    `durations = [[0.0] * n for _ in range(n)]`  
    `distances = [[0.0] * n for _ in range(n)]`  
    `earth_radius = 6371000.0  # Meters`

    `for i in range(n):`  
        `for j in range(n):`  
            `if i != j:`  
                `lat1, lon1 = math.radians(nodes[i][0]), math.radians(nodes[i][1])`  
                `lat2, lon2 = math.radians(nodes[j][0]), math.radians(nodes[j][1])`

                `dlat, dlon = lat2 - lat1, lon2 - lon1`  
                `a = math.sin(dlat/2)**2 + math.cos(lat1) * math.cos(lat2) * math.sin(dlon/2)**2`  
                `c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))`

                `direct_dist = earth_radius * c`  
                `est_road_dist = direct_dist * tortuosity`  
                `est_duration = est_road_dist / avg_speed_m_s`

                `distances[i][j] = est_road_dist`  
                `durations[i][j] = est_duration`

    `return distances, durations`

### **Graceful UI Fallbacks for Manual Override Conflicts**

If a user manually orders stops in a way that violates operational constraints (such as ordering stops after a store's closing time), the optimization engine handles the conflict through constraint relaxation.

#### **Constraint Relaxation Cascade**

If OR-Tools returns INFEASIBLE for a user-specified route, the solver relaxes constraints systematically:

> 1. Relax hard time windows on remaining unpinned candidate stops, converting them into soft constraints with high penalty weights.  
> 2. Relax perishable thermal deferral penalties while keeping manual stop pins strictly locked.  
> 3. If physical deadlines are breached (e.g., arriving at an administrative office after closing), the UI maintains the user's manual ordering, marks the route as sub-optimal, and displays an informative warning banner (e.g., *"Selected stop sequence arrives after 5:00 PM closing time"*).

## **System Implementation Roadmap and Strategic Synthesis**

### **Phased Implementation Plan**

| Phase | Milestone Objective | Deliverables & Platform Modules | Validation Metrics |
| :---- | :---- | :---- | :---- |
| **Phase 1** | **Base Sync & Local Persistence** | Local SQLite schema; Drift ORM implementation; dual-channel HA WebSocket client (todo/); LWW-HLC delta sync engine. | Zero state loss during offline edits; delta sync latency under 200 ms upon reconnect. |
| **Phase 2** | **Routing Engine & Constraint Solver** | Geospatial Matrix engine integration; background OR-Tools solver isolate; MILP VRPTW solver with disjunctions & thermal decay penalties. | Route solve time under 1.5 seconds for up to 10 candidate store locations. |
| **Phase 3** | **Spatial Preferences & Layout Learning** | Geofence state engine with hysteresis; background visit check-off tracker; DAG topological sort layout engine; dynamic UI overlay layer. | In-store item sorting accuracy improves over 3 visit iterations per store layout. |

### **Strategic Synthesis**

The architecture of the Overpowered Errand Engine demonstrates how automated route optimization can operate alongside user-driven list management. By modeling vehicle routing constraints, spatial choice options, and in-store layout learning into a non-destructive state layer, the application provides useful routing defaults while giving the user full manual control. Combining offline-first local databases, real-time Home Assistant synchronization, and constraint-based optimization libraries creates a dependable platform for personal errand navigation.

#### **Works cited**

1\. WebSocket Bridge (ws\_bridge) for Home Assistant · GitHub, https://github.com/eigger/hass-ws-bridge 2\. ovos-PHAL-plugin-homeassistant \- PyPI, https://pypi.org/project/ovos-PHAL-plugin-homeassistant/ 3\. Home Assistant Dashboard using WebSocket API \- GitHub Gist, https://gist.github.com/JerryWorkman/d64740b619b211f6398eb67f39e2e438 4\. Any Ideas What Could Be Wrong Here \- Home Assistant Community, https://community.home-assistant.io/t/any-ideas-what-could-be-wrong-here/922903 5\. ha-mcp/homeassistant-addon/DOCS.md at master \- GitHub, https://github.com/homeassistant-ai/ha-mcp/blob/master/homeassistant-addon/DOCS.md 6\. Full changelog for Home Assistant Core 2023.12, https://www.home-assistant.io/changelogs/core-2023.12/ 7\. Symt Docs — Maps & Location Intelligence API, https://docs.symt.ai/ 8\. OSRM: The Reference Architecture for Lightning-Fast Routing, https://ayedo.de/en/posts/osrm-die-referenz-architektur-fur-blitzschnelles-routing-logistik-ohne-api-kosten/ 9\. Top 10 Open-Source Tools for Route Optimization in 2025, https://nextbillion.ai/blog/top-open-source-tools-for-route-optimization 10\. Open Source Routing Machine \- Wikipedia, https://en.wikipedia.org/wiki/Open\_Source\_Routing\_Machine 11\. tutorials/general/foss\_routing\_engines\_overview.md at master, https://github.com/gis-ops/tutorials/blob/master/general/foss\_routing\_engines\_overview.md 12\. Compute a matrix \- GraphHopper Directions API, https://docs.graphhopper.com/openapi/matrices/getmatrix 13\. OR-Tools, VROOM & Nextplot: Open source vehicle routing and, https://www.youtube.com/watch?v=8TPZa5hWKVk 14\. Penalties and Dropping Visits | OR-Tools \- Google for Developers, https://developers.google.com/optimization/routing/penalties 15\. VROOM-Project/vroom: Vehicle Routing Open-source Optimization, https://github.com/vroom-project/vroom 16\. Local-search phase for CVRP · Issue \#92 · VROOM-Project ... \- GitHub, https://github.com/VROOM-Project/vroom/issues/92 17\. How Vehicle Routing Solvers Work: From Exact Methods to Hybrid, https://medium.com/@barzidehmilad/how-vehicle-routing-solvers-work-from-exact-methods-to-hybrid-metaheuristics-0c7de327072a 18\. PyVRP: a high-performance VRP solver package \- arXiv, https://arxiv.org/html/2403.13795v2 19\. Why choose PyVRP? \- PyVRP 1.0.0a0 documentation, https://pyvrp.org/setup/why\_pyvrp.html