# Save/load implementation notes

## Current state

The Godot save menu writes a versioned ConfigFile containing save metadata and a small interface checkpoint. That checkpoint is **not** a simulation save: it cannot restore the date, economy, population, provinces, armies, technology, diplomacy, queued actions, market state, or RNG state. Do not describe it as a complete save.

OpenVic's architecture diagram specifies the intended flow: the UI requests a save, the bridge calls the simulation's save routines, and the simulation writes the current state to disk. The save/load backend belongs in the native simulation layer, not solely in the Godot menu.

## Useful existing work in OpenVic-Simulation

- `docs/ecs/entities.md` documents `World::snapshot_identity`, `World::restore_identity`, and `World::restore_entity`. These preserve ECS entity IDs and free-list allocation order.
- `src/openvic-simulation/core/ecs/World.hpp` defines `WorldIdentitySnapshot`.
- The identity snapshot intentionally stores **only entity identity**. The caller must also serialize every live entity's component data, singleton data, and other simulation state. It does not itself implement a complete save file.
- `docs/ecs/determinism.md` explains why canonical entity recreation order matters for deterministic continuation.

References:
- https://github.com/OpenVicProject/OpenVic/blob/master/docs/contribution/general-program-architecture.md
- https://github.com/OpenVicProject/OpenVic-Simulation/blob/master/docs/ecs/entities.md
- https://github.com/OpenVicProject/OpenVic-Simulation/blob/master/docs/ecs/world.md
- https://github.com/OpenVicProject/OpenVic-Simulation/blob/master/docs/ecs/determinism.md

## Required implementation

1. Add a versioned native save format and a save/load API on the simulation manager.
2. Serialize all mutable state, not only IDs: entity components, singleton state, simulation date/clock, country/province/population data, market/economy, units, diplomacy, global flags, queued actions, and deterministic RNG state where applicable.
3. Validate the save version, game/mod data compatibility, required fields, and all references before mutating a live session.
4. Load into a fresh simulation instance; restore entity identity first, then recreate live entities in canonical slot-index order and restore all other state.
5. Expose native save/load methods through the Godot extension, then connect the Save/Load UI to those methods. A load must be able to start from the main menu, not require the same active session/date.
6. Add native round-trip tests that save, advance the simulation, reload, and compare a full-state checksum plus date and key entity data. Also test corrupt files, incompatible versions, and interrupted writes.
7. Keep the UI checkpoint only as explicitly labelled interface metadata until the native round-trip path is implemented and tested.

## Blocking repository boundary

The main repository includes `extension/deps/openvic-simulation` as a Git submodule pointing at `OpenVicProject/OpenVic-Simulation`. The current connected GitHub write access can update the user's `OpenVic` repository, but cannot commit native changes to that upstream simulation repository. A real end-to-end implementation needs a writable fork of `OpenVic-Simulation` and the parent submodule updated to reference its commit.
