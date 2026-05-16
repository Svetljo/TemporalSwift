# ``TemporalSwiftCore``

Core data structures, protocols, and error types for the TemporalSwift framework.

## Overview

`TemporalSwiftCore` provides the foundational building blocks for working with
temporal knowledge graphs. It defines the data models, storage and query protocols,
and error types used across all TemporalSwift targets.

### Architecture

TemporalSwift is organized into three library targets:

| Target | Responsibility |
|--------|---------------|
| ``TemporalSwiftCore`` | Data models, protocols, error types |
| `TemporalSwiftStorage` | In-memory and persistence backends |
| `TemporalSwiftQuery` | Graph traversal, temporal reasoning, context packaging |

### Key Concepts

- **Nodes** represent entities (people, places, things) in the knowledge graph.
- **Edges** represent directional relationships between nodes.
- **TemporalState** records attribute snapshots with time-bounded validity.
- **Episodes** group related state changes into named events.
- **ContextSnapshots** are pruned subgraphs serialized for LLM context windows.

## Topics

### Data Models

- ``Node``
- ``Edge``
- ``TemporalBounds``
- ``TemporalState``
- ``Episode``
- ``ContextSnapshot``
- ``AttributeValue``

### Protocols

- ``GraphStore``
- ``TemporalQueryable``
- ``ContextPackaging``
- ``GraphTraversing``
- ``TraversalResult``

### Errors

- ``TemporalSwiftError``
