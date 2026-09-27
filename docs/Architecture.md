File 2: architecture.md
Markdown

# Architecture Specification & System Flow

## System Overview
The architecture is structured around a local-first mobile client connected to an asynchronous operations research solver, geospatial matrix engine, and Home Assistant WebSocket sync engine[cite: 1].

+-----------------------------------------------------------------------------------+

|                                 MOBILE APPLICATION                                |

|                                                                                   |

|  +-----------------------+    Local Mutations    +-----------------------------+  |

|  |   UI / User Action    | --------------------> |   Local Database Engine     |  |

|  |  (Human-in-the-Loop)  | <-------------------- | (SQLite / Drift / Watermelon|  |

|  +-----------------------+    Visual Overlays    +-----------------------------+  |

|                                                               ^                   |

|                                                               | Delta Reconcile   |

|                                                               v                   |

|                                                  +-----------------------------+  |

|                                                  |   Sync Engine & Queue       |  |

|                                                  +-----------------------------+  |

+-----------------------------------------------------------------|-----------------+

|

WebSocket / REST    | WS: /api/websocket

(todo domain)       | Sub: todo/item/subscribe

v

+-----------------------------+

| Home Assistant Core Instance|

+-----------------------------+
Code snippet


---

## Module Breakdown

### 1. Data Layer & HA Sync
* **Database Engine**: Local SQLite (Drift / WatermelonDB) for zero-latency offline performance[cite: 1].
* **HA Integration**: Custom WebSocket client over Home Assistant `/api/websocket` endpoints using standard `todo/` channels[cite: 1].
* **Conflict Resolution**: Mutations appended to a local queue using Hybrid Logical Clocks (HLC) and Last-Write-Wins (LWW) semantics to reconcile edits during intermittent connectivity[cite: 1].

### 2. Spatial Route Solver (Hybrid VRPTW)
* **Optimization Library**: Google OR-Tools (CP-SAT / Local Search) running on a background worker thread[cite: 1].
* **Candidate Disjunction**: Solves disjunctive candidate nodes (`AddDisjunction`) to automatically pick the single optimal store out of multiple choices[cite: 1].
* **Perishable Load Constraints**: Evaluates a thermal decay penalty coefficient $\gamma \ge 0$ to defer temperature-sensitive items to the end of the route[cite: 1].
* **Manual Override Override Layer**: If a user pins or reorders stops manually, the solver enforces hard sequence constraints ($t_A + s_A + C_{AB} \le t_B$)[cite: 1]. If an manual lock creates an infeasible route (e.g., arriving after store hours), constraints gracefully relax to present informative warning banners while respecting user intent[cite: 1].

### 3. Spatial Preference & Layout Learning
* **Dual-Ring Geofencing**: Operates an Inner Arrival Radius ($R_{\text{in}} = 40\text{m}$) with a 120-second dwell filter, and an Outer Exit Radius ($R_{\text{out}} = 80\text{m}$) with a 180-second exit grace period to prevent indoor GPS jitter[cite: 1].
* **Layout Sequence Reconstruction**: Timestamps from item check-offs build a weighted precedence graph[cite: 1]. Directed cycles created by random backtracking are eliminated using Feedback Arc Set reduction before applying Kahn’s Topological Sort to derive the optimal walk sequence[cite: 1].

---

## Core Schema (SQLite)

```sql
-- Home Assistant Synced To-Do Items[cite: 1]
CREATE TABLE items (  
    id TEXT PRIMARY KEY NOT NULL,  
    ha_entity_id TEXT NOT NULL,  
    summary TEXT NOT NULL,  
    description TEXT,  
    category TEXT DEFAULT 'generic',  
    is_perishable INTEGER NOT NULL DEFAULT 0 CHECK (is_perishable IN (0, 1)),  
    status TEXT NOT NULL DEFAULT 'needs_action' CHECK (status IN ('needs_action', 'completed')),  
    human_order_index INTEGER NOT NULL,  
    optimized_order_index INTEGER,  
    is_pinned INTEGER NOT NULL DEFAULT 0 CHECK (is_pinned IN (0, 1)),  
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,  
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP  
);[cite: 1]

-- Item Category to Store Preference Counter[cite: 1]
CREATE TABLE item_store_preferences (  
    id TEXT PRIMARY KEY NOT NULL,  
    item_category TEXT NOT NULL,  
    store_id TEXT NOT NULL,  
    selection_count INTEGER NOT NULL DEFAULT 1,  
    confidence_score REAL NOT NULL DEFAULT 0.5,  
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE  
);[cite: 1]

-- Directed Store Layout Graph[cite: 1]
CREATE TABLE store_layout_edges (  
    store_id TEXT NOT NULL,  
    from_item_category TEXT NOT NULL,  
    to_item_category TEXT NOT NULL,  
    forward_weight REAL NOT NULL DEFAULT 0.0,  
    sample_size INTEGER NOT NULL DEFAULT 0,  
    PRIMARY KEY (store_id, from_item_category, to_item_category),  
    FOREIGN KEY (store_id) REFERENCES stores(id) ON DELETE CASCADE  
);[cite: 1]
