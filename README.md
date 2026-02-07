# Callout

Open-source Computer-Aided Dispatch for emergency services.

Built by a former firefighter who spent too long staring at dispatch software that looked like it was designed as a punishment. This is an attempt to do better.

## Why

Commercial CAD systems cost somewhere between "a lot" and "the entire budget." They're closed-source, often baffling to use, and if you're a volunteer department or a small agency, you probably can't afford one. So you end up with paper, or a spreadsheet, or a whiteboard with magnets on it.

This is a proper dispatch engine you can run yourself. Event-sourced, offline-capable, authority-ranked. The sort of thing that should exist but somehow doesn't.

## Architecture

The guiding principle: the software that tells fire engines where to go probably shouldn't crash.

| Layer | Technology | Why |
|-------|-----------|-----|
| Server | **C** (Mongoose) | Proven, minimal, no runtime surprises |
| Core logic | **OCaml** | Algebraic types, exhaustive pattern matching, the compiler catches your mistakes before the user does |
| Frontend | **js_of_ocaml** | Same type safety, all the way to the browser |
| Maps | **OpenStreetMap + Leaflet** | Fully open, self-hostable tiles |
| Database | **SQLite** | Embedded, zero-config, works without a network |
| Real-time | **WebSocket** | Persistent connections for live dispatch updates |

### Design Decisions

- **Event-sourced.** Every state change is an immutable event. Nothing is deleted. You can replay the entire history of a shift from the event log alone.
- **Authority-ranked sync.** Dispatcher outranks Incident Commander outranks Crew Leader outranks Field Unit. When two people disagree, rank wins. Same rank, latest timestamp wins. Just like real ICS.
- **Offline-first.** The client works without a network connection and syncs when it gets one back. Because radio dead spots are a real thing.
- **Deterministic engine.** The core dispatch engine is a pure function: state + command = state + events. No I/O, no randomness. Given the same inputs it will produce the same outputs every single time. We've tested this up to 37 million commands.

## Constraints

Rules the codebase holds itself to, because dispatch software that misbehaves is not the fun kind of exciting.

- No dynamic memory allocation in C hot paths after initialisation
- All OCaml types are exhaustively matched. No wildcards on critical paths. If you add a state, the compiler makes you handle it everywhere.
- Every state transition is explicit in the type system
- SQLite in WAL mode for concurrent read/write safety
- All network input validated at the C boundary before it reaches OCaml
- Event log is append-only. Nothing is ever deleted, only superseded.

## Project Structure

```
src/
  server/     C server (HTTP, WebSocket, SQLite)
  core/       OCaml domain logic (incidents, dispatch, units, auth, sync)
  engine/     Headless dispatch engine (pure, deterministic, replayable)
  harness/    Stress test harness (synthetic dispatch scenarios)
  client/     Frontend (js_of_ocaml)
  shared/     Types shared between core and client
db/           SQLite schema
vendor/       Mongoose and SQLite3 (vendored)
static/       HTML, CSS, Leaflet
test/         Core logic test suite
```

## Building

### Prerequisites

- GCC (or Clang)
- OCaml 5.x + opam
- SQLite3 development headers

Mongoose, SQLite3, and Leaflet are vendored in the repo. No extra downloads needed.

### Setup

```bash
# Install OCaml dependencies
make setup

# Build everything
make

# Run the test suite
make test
```

### Run

```bash
make run
# or directly:
./build/callout-server -p 8080 -r ./static -d callout.db
```

Then open `http://localhost:8080`.

### Headless Engine

You can run the dispatch engine without the server, the database, or a browser. Useful for testing, benchmarking, or just seeing what 10 million synthetic dispatches looks like.

```bash
make harness                                          # build the harness
dune exec callout-harness -- --test 1000 --seed 42    # run 1000 dispatches
dune exec callout-harness -- --stress --seed 42       # escalate from 100 to 1M
```

## Data Model

### Incident Lifecycle

```
Reported -> Dispatched -> En_route -> On_scene -> Under_control -> Resolved
                                                        |
Any state -> Cancelled                          (can escalate back)
```

Every transition is explicit in the type system. The compiler won't let you skip one.

### Authority Hierarchy

```
Dispatcher (highest) > Incident Commander > Crew Leader > Field Unit (lowest)
```

This follows ICS (Incident Command System). Higher authority overrides lower. A field unit can't overrule a dispatcher, and the software enforces that.

### Sync Protocol

1. Client records events locally (works offline)
2. On reconnect, client pushes unsynced events via WebSocket
3. Server validates authority and applies events
4. Server broadcasts accepted events to all connected clients
5. Clients apply and mark as synced

If two events conflict, authority wins. If authority is equal, the later timestamp wins. Same rules you'd use on the fireground.

## Scope

This project provides a dispatch engine. It handles incidents, units, state transitions, authority, sync, and event replay. That's the bit that needs to be correct, and that's the bit we test obsessively.

What this project does **not** provide:

- **Compliance certification.** NENA, APCO, NFPA, and other standards exist for good reason. Meeting them requires validation specific to your jurisdiction, your deployment, and your use case. That's not something an open-source project can do for you.
- **Radio integration.** Every agency has different hardware. Tying into your specific radio system is a deployment concern, not an engine concern.
- **CAD-to-CAD interop.** If you need to talk to a neighbouring agency's system, that's an integration layer on top.
- **Production readiness guarantees.** This is dispatch software. It is not certified for operational use. If you're considering deploying it for real emergency dispatch, you are responsible for testing, validating, and certifying it in your environment. The Apache 2.0 licence makes this explicit, but it bears repeating in plain English.

The goal is to give you a correct, tested, replayable engine that you can build on. What you build on top of it, and whether it's suitable for your needs, is your call.

## Status

This is early. The core engine works and has been stress-tested to 10 million dispatches. The C server, database layer, and frontend exist but the OCaml-to-C bridge isn't wired up yet. If you're expecting a finished product, come back later. If you're interested in where it's going, stick around.

## Contact

Zane Hambly — zanehambly@gmail.com

For bugs and feature requests, open an issue. For everything else, send an email.

## License

Apache 2.0. See [LICENSE](LICENSE).
