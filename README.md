# TemporalSwift

A Swift 6 framework for temporal long-term memory in AI agents. TemporalSwift models a knowledge graph where every fact is time-stamped, versioned, and preserved forever — enabling agents to reason about how the world has changed over time.

## Overview

AI agents accumulate knowledge over many interactions. TemporalSwift gives that knowledge a timeline: facts can be recorded with validity periods, queried at any point in history, and packed into a character-budgeted JSON snapshot ready to drop into an LLM context window.

```
Alice lives in New York  (valid Jan–Jun 2025)
Alice lives in Milan     (valid Jun 2025–present)

→ "Where did Alice live in March 2025?"  →  New York
→ "Where does Alice live now?"           →  Milan
→ "What changed between Jan and Jul?"    →  Alice's location
```

## Features

- **Temporal fact storage** — every node and edge attribute set is stored as an immutable `TemporalState` with a `[validFrom, validUntil)` interval. History is append-only; nothing is ever overwritten.
- **Point-in-time queries** — ask what was true at any moment in the past or present.
- **Time-range queries** — retrieve all facts that were active during a window, or all entities whose state changed.
- **Graph traversal** — BFS from any node with configurable depth, optional temporal filtering (only follow edges active at a given date), and optional edge-type filtering.
- **Cycle constraint enforcement** — per-edge-type acyclicity constraints with DFS cycle detection. Hierarchical relationship types (e.g. `"parent_of"`) can be declared DAG-only; general types (e.g. `"knows"`) allow cycles.
- **LLM context packaging** — extract a relevance-ranked subgraph centred on a focal entity and serialize it to JSON within a character budget, with ≤5% overshoot tolerance.
- **Swift 6 strict concurrency** — `InMemoryGraphStore` is an `actor`; all data models are `Sendable` value types. No data races under concurrent agent workloads.
- **Persistent storage** — `SQLiteGraphStore` (in `TemporalSwiftSQLite`) provides a cross-platform, file-backed store that survives process restarts. Drop-in replacement for `InMemoryGraphStore`.
- **Zero third-party dependencies** — Foundation and system SQLite only.

## Package Structure

```
Sources/
├── TemporalSwiftCore/       # Data models, protocols, errors
├── TemporalSwiftStorage/    # InMemoryGraphStore actor
├── TemporalSwiftQuery/      # TemporalQueryEngine, GraphTraverser, ContextPackager
├── TemporalSwiftPersistence/# SwiftDataGraphStore (Apple platforms only)
└── TemporalSwiftSQLite/     # SQLiteGraphStore (cross-platform)

Tests/
├── TemporalSwiftCoreTests/
├── TemporalSwiftStorageTests/
├── TemporalSwiftQueryTests/
├── TemporalSwiftPersistenceTests/
└── TemporalSwiftSQLiteTests/
```

| Target | Role |
|--------|------|
| `TemporalSwiftCore` | `Node`, `Edge`, `TemporalState`, `Episode`, `ContextSnapshot`, `AttributeValue`, `TemporalBounds`, protocol definitions, `TemporalSwiftError` |
| `TemporalSwiftStorage` | `InMemoryGraphStore` — thread-safe in-memory backend |
| `TemporalSwiftQuery` | `TemporalQueryEngine`, `GraphTraverser`, `ContextPackager` |
| `TemporalSwiftPersistence` | `SwiftDataGraphStore` — persistent store using SwiftData (macOS 14+, iOS 17+) |
| `TemporalSwiftSQLite` | `SQLiteGraphStore` — persistent store using raw SQLite (macOS + Linux) |

## Requirements

- Swift 6.0+
- macOS 14+ or Linux (Ubuntu 22.04+, Amazon Linux 2023)

## Installation

Add TemporalSwift to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/your-org/TemporalSwift.git", from: "0.1.0")
]
```

Then add the targets you need:

```swift
.target(
    name: "YourApp",
    dependencies: [
        .product(name: "TemporalSwiftCore", package: "TemporalSwift"),
        .product(name: "TemporalSwiftStorage", package: "TemporalSwift"),
        .product(name: "TemporalSwiftQuery", package: "TemporalSwift"),
    ]
)
```

To use persistent storage, add the appropriate target instead of (or in addition to) `TemporalSwiftStorage`:

```swift
// Cross-platform SQLite store (macOS + Linux)
.product(name: "TemporalSwiftSQLite", package: "TemporalSwift")

// SwiftData store (Apple platforms only: macOS 14+, iOS 17+)
.product(name: "TemporalSwiftPersistence", package: "TemporalSwift")
```

## Usage

### Choose a storage backend

TemporalSwift ships three `GraphStore` implementations. All expose the same protocol — swap between them by changing a single line at initialization.

| Store | Module | Persistence | Platforms |
|-------|--------|-------------|-----------|
| `InMemoryGraphStore` | `TemporalSwiftStorage` | None (process lifetime) | All |
| `SQLiteGraphStore` | `TemporalSwiftSQLite` | File-backed SQLite | macOS + Linux |
| `SwiftDataGraphStore` | `TemporalSwiftPersistence` | File-backed SwiftData | macOS 14+, iOS 17+ |

```swift
import TemporalSwiftStorage
let store = InMemoryGraphStore()              // development / testing

import TemporalSwiftSQLite
let store = try SQLiteGraphStore(            // production (cross-platform)
    path: "/path/to/graph.db"
)

import TemporalSwiftPersistence
let store = try SwiftDataGraphStore(         // production (Apple-only)
    url: URL(fileURLWithPath: "/path/to/graph.sqlite")
)
```

The `SQLiteGraphStore` also accepts `":memory:"` as a path for a fast, isolated in-memory database — useful in tests that need the full persistence code path without touching disk.

### Store your first facts

```swift
import TemporalSwiftCore
import TemporalSwiftStorage

let store = InMemoryGraphStore()

// Create nodes
let alice = try await store.addNode(
    type: "Person",
    attributes: ["name": .string("Alice")]
)
let newYork = try await store.addNode(
    type: "Location",
    attributes: ["name": .string("New York")]
)

// Create a time-bounded edge
let livesIn = try await store.addEdge(
    type: "lives_in",
    sourceID: alice.id,
    targetID: newYork.id,
    attributes: [:],
    bounds: TemporalBounds(validFrom: Date(), validUntil: nil) // currently active
)
```

### Query facts at a point in time

```swift
import TemporalSwiftQuery

let engine = TemporalQueryEngine(store: store)

// What was Alice's location at a specific moment?
if let state = try await engine.query(entityID: livesIn.id, at: someDate) {
    print("Edge was active with attributes: \(state.attributes)")
}

// Full history for an entity
let history = try await engine.history(for: alice.id)

// Which entities changed between two dates?
let changed = try await engine.changedEntities(from: startDate, to: endDate)
```

### Update a fact (temporal evolution)

```swift
let now = Date()

// Close the old relationship
try await store.addState(
    for: livesIn.id,
    attributes: [:],
    bounds: TemporalBounds(validFrom: livesIn.createdAt, validUntil: now)
)

// Create the new one
let milan = try await store.addNode(
    type: "Location",
    attributes: ["name": .string("Milan")]
)
let livesInMilan = try await store.addEdge(
    type: "lives_in",
    sourceID: alice.id,
    targetID: milan.id,
    attributes: [:],
    bounds: TemporalBounds(validFrom: now, validUntil: nil)
)

// Both facts are preserved — history is never deleted
```

### Traverse the graph

```swift
let traverser = GraphTraverser(store: store)

// BFS up to 2 hops from Alice, only following active edges at `now`
let result = try await traverser.traverse(
    from: alice.id,
    maxDepth: 2,
    at: Date(),
    edgeTypeFilter: nil // nil = all edge types
)

print("Reachable nodes: \(result.nodes.count)")
```

### Enforce DAG constraints on edge types

```swift
// Declare that "parent_of" edges must form a DAG
await store.setAcyclicConstraint(for: "parent_of")

let parent = try await store.addNode(type: "Person", attributes: [:])
let child  = try await store.addNode(type: "Person", attributes: [:])

_ = try await store.addEdge(type: "parent_of", sourceID: parent.id, targetID: child.id,
                             attributes: [:], bounds: TemporalBounds(validFrom: Date(), validUntil: nil))

// This would create a cycle — throws TemporalSwiftError.cycleViolation
_ = try await store.addEdge(type: "parent_of", sourceID: child.id, targetID: parent.id,
                             attributes: [:], bounds: TemporalBounds(validFrom: Date(), validUntil: nil))
```

### Pack context for an LLM

```swift
let packager = ContextPackager(store: store, traverser: traverser)

// Extract a subgraph centred on Alice, budget of 8 000 tokens
let snapshot = try await packager.snapshot(
    focalEntityID: alice.id,
    at: Date(),
    maxDepth: 2,
    characterBudget: 8_000,
    charsPerToken: 4,   // ~4 chars per token (GPT-family approximation)
    edgeTypeFilter: nil
)

// snapshot is Codable — include it in your prompt
let json = try JSONEncoder().encode(snapshot)
```

Entities are ranked by proximity to the focal node (closer = higher priority) then by recency (more recent state = higher priority). The packager stops adding entities once the character budget would be exceeded, with a maximum 5% overshoot.

## Data Model

| Type | Description |
|------|-------------|
| `Node` | An entity in the graph (`id`, `type`, `attributes`, `createdAt`) |
| `Edge` | A directional relationship (`id`, `type`, `sourceID`, `targetID`, `attributes`, `createdAt`) |
| `TemporalBounds` | A validity interval `[validFrom, validUntil?)` |
| `TemporalState` | An immutable attribute snapshot with bounds and a monotonic `version` |
| `Episode` | A named group of related `TemporalState` records |
| `ContextSnapshot` | A budget-bounded, serialized subgraph for LLM consumption |
| `AttributeValue` | Enum: `.string`, `.int`, `.double`, `.bool`, `.date`, `.null` |

### Overlap resolution

When multiple `TemporalState` records are active at the same point in time (e.g. concurrent writes), the one with the **highest version number** is authoritative. Version numbers are monotonically assigned by the store, so the last write always wins.

## Protocols

You can swap the storage backend or provide custom query/traversal implementations by conforming to the core protocols:

| Protocol | Responsibility |
|----------|---------------|
| `GraphStore` | Node, edge, state, episode CRUD + acyclicity configuration |
| `TemporalQueryable` | Point-in-time, range, history, and change-detection queries |
| `GraphTraversing` | BFS/DFS traversal with temporal and type filters |
| `ContextPackaging` | Budget-bounded context snapshot extraction |

## Error Handling

All errors are cases of `TemporalSwiftError`:

| Case | When thrown |
|------|-------------|
| `nodeNotFound(id:)` | Node lookup fails |
| `edgeNotFound(id:)` | Edge lookup fails |
| `referentialIntegrityViolation(missingNodeID:)` | Edge added with unknown source or target |
| `cycleViolation(edgeType:sourceID:targetID:)` | Constrained edge type would form a cycle |
| `invalidTemporalBounds(reason:)` | Logically invalid bounds |
| `budgetExceeded(requested:actual:)` | Snapshot exceeds budget |

## Running Tests

```sh
swift test
```

All 129 tests cover temporal edge cases, Codable round-trips, referential integrity, concurrency correctness (10 concurrent agents, zero corruption), cycle detection, BFS traversal, context packaging budget enforcement, SQLite persistence round-trips across process restarts, and version counter monotonicity.

## License

MIT
