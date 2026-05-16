# TemporalSwift — Agent Guidance

## Project Overview

TemporalSwift is a **Swift 6 SPM library** that provides temporal long-term memory for AI agents via a knowledge graph. Every fact is time-stamped, versioned, and append-only, enabling agents to reason about how the world has changed over time.

**Language**: Swift 6 (strict concurrency mode)  
**Build system**: Swift Package Manager only — no Xcode project files  
**Platforms**: macOS 14+, Linux (Ubuntu 22.04+, Amazon Linux 2023)  
**Dependencies**: Foundation only (zero third-party)  
**Testing framework**: Swift Testing (`@Test` macro, `#expect`)

---

## Repository Layout

```
Package.swift

Sources/
├── TemporalSwiftCore/           # Data models, protocols, errors
│   ├── Models/
│   │   ├── AttributeValue.swift      # Enum: .string/.int/.double/.bool/.date/.null
│   │   ├── ContextSnapshot.swift     # Budget-bounded subgraph for LLM consumption
│   │   ├── Edge.swift                # Directional relationship between two nodes
│   │   ├── Episode.swift             # Named group of TemporalState records
│   │   ├── Node.swift                # Entity (vertex) in the graph
│   │   ├── TemporalBounds.swift      # [validFrom, validUntil?) interval
│   │   └── TemporalState.swift       # Immutable versioned attribute snapshot
│   ├── Protocols/
│   │   ├── ContextPackaging.swift    # Protocol: budget-bounded snapshot extraction
│   │   ├── GraphStore.swift          # Protocol: node/edge/state/episode CRUD
│   │   ├── GraphTraversing.swift     # Protocol: BFS/DFS traversal + TraversalResult
│   │   └── TemporalQueryable.swift   # Protocol: point-in-time & range queries
│   ├── Errors/
│   │   └── TemporalSwiftError.swift  # All error cases
│   └── Documentation.docc/
│       └── TemporalSwiftCore.md      # DocC landing page
├── TemporalSwiftStorage/
│   └── InMemoryGraphStore.swift      # Actor-based in-memory GraphStore implementation
└── TemporalSwiftQuery/
    ├── ContextPackager.swift         # ContextPackaging implementation
    ├── GraphTraverser.swift          # GraphTraversing implementation (BFS)
    └── TemporalQueryEngine.swift     # TemporalQueryable implementation

Tests/
├── TemporalSwiftCoreTests/
│   ├── AttributeValueTests.swift
│   ├── CodableConformanceTests.swift
│   └── TemporalBoundsTests.swift
├── TemporalSwiftStorageTests/
│   ├── ConcurrencyTests.swift
│   ├── InMemoryGraphStoreTests.swift
│   └── ReferentialIntegrityTests.swift
└── TemporalSwiftQueryTests/
    ├── ContextPackagerTests.swift
    ├── CycleConstraintTests.swift
    ├── GraphTraversalTests.swift
    ├── PointInTimeQueryTests.swift
    └── TimeRangeQueryTests.swift
```

---

## Target Dependency Rules

```
TemporalSwiftStorage  →  TemporalSwiftCore
TemporalSwiftQuery    →  TemporalSwiftCore
```

`TemporalSwiftStorage` and `TemporalSwiftQuery` **must not** depend on each other. `TemporalSwiftQuery` operates on the `GraphStore` protocol, not on `InMemoryGraphStore` directly.

---

## Key Design Decisions

### Temporal immutability
`TemporalState` records are **never mutated or deleted**. Updating a fact means appending a new `TemporalState` with an updated `bounds`. All history is preserved forever (append-only).

### Overlap resolution
When multiple `TemporalState` records are active at the same point in time, the one with the **highest `version`** is authoritative. Versions are monotonically assigned by the store — last write wins, regardless of wall-clock time.

### Actor isolation
`InMemoryGraphStore` is an `actor`. All public methods are `async`. Never use `NSLock`, `DispatchQueue`, or manual locking — the actor serializes all mutations automatically.

### Protocol-first
Define or modify the protocol in `TemporalSwiftCore/Protocols/` before changing any implementation. The `GraphStore` protocol in particular is the integration point between `Storage` and `Query` targets.

### Cycle detection
`InMemoryGraphStore` stores a `Set<String>` of edge types that require DAG structure. On every constrained edge write, it runs a DFS from `targetID` toward `sourceID`. Only edges of the same type are followed. The check is `O(V+E)` scoped to a single edge type.

---

## Common Commands

```sh
# Build
swift build

# Run all tests
swift test

# Run a specific test suite
swift test --filter TemporalBoundsTests

# Build documentation (requires swift-docc-plugin if added)
swift package generate-documentation
```

---

## Adding New Code

### New model type
1. Add `YourType.swift` under `Sources/TemporalSwiftCore/Models/`
2. Conform to `Codable`, `Sendable`, `Hashable`, `Identifiable` (where appropriate)
3. Add a Codable round-trip test in `Tests/TemporalSwiftCoreTests/CodableConformanceTests.swift`
4. Document all `public` symbols with DocC (`///` triple-slash)

### New `GraphStore` method
1. Add the method signature to `Sources/TemporalSwiftCore/Protocols/GraphStore.swift`
2. Implement it in `Sources/TemporalSwiftStorage/InMemoryGraphStore.swift`
3. Write tests in the appropriate `Tests/TemporalSwiftStorageTests/` file

### New query capability
1. Add to `Sources/TemporalSwiftCore/Protocols/TemporalQueryable.swift` (or create a new protocol)
2. Implement in `Sources/TemporalSwiftQuery/TemporalQueryEngine.swift`
3. Write tests in `Tests/TemporalSwiftQueryTests/`

---

## Testing Conventions

- Use `Swift Testing` (`@Test`, `#expect`, `@Suite`) — not XCTest
- Group related tests with `@Suite("Descriptive Name")`
- Use `Issue.record(...)` instead of `XCTFail` for failure messages within non-throwing test bodies
- **Always** test these categories for any new temporal API:
  - Point-in-time before/at/after valid range
  - Zero-duration bounds (`validFrom == validUntil`)
  - Open-ended bounds (`validUntil == nil`)
  - Multiple overlapping states (highest version wins)
- **Always** test concurrency for any new `InMemoryGraphStore` mutation: spin up ≥10 concurrent tasks and verify no corruption

---

## Error Handling

All errors are `TemporalSwiftError` cases. Never `fatalError` or `preconditionFailure` in library code — always `throw`. The full set of cases:

| Case | Meaning |
|------|---------|
| `nodeNotFound(id:)` | Node UUID not in store |
| `edgeNotFound(id:)` | Edge UUID not in store |
| `stateNotFound(id:)` | TemporalState UUID not in store |
| `episodeNotFound(id:)` | Episode UUID not in store |
| `invalidEdgeType(_:)` | Empty or invalid edge type string |
| `cycleViolation(edgeType:sourceID:targetID:)` | DAG constraint violated |
| `invalidTemporalBounds(reason:)` | Logically invalid bounds |
| `referentialIntegrityViolation(missingNodeID:)` | Edge references non-existent node |
| `budgetExceeded(requested:actual:)` | Context snapshot over budget |

---

## Code Style

- Follow Swift API Design Guidelines
- Format with `swift-format` using the `.swift-format` config at the repo root
- Commit messages use conventional commits: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`
- All `public` and `package` symbols **must** have DocC documentation (at minimum a summary line)
