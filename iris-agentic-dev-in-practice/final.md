# iris-agentic-dev in Practice: A Test-First Loop on InterSystems IRIS

## TL;DR

iris-agentic-dev is an MCP server that gives an AI coding agent a live connection to InterSystems IRIS — introspection, document read/write, compilation with structured errors, SQL, and test runs on the running instance. This article will walk you through a complete test-first loop against an inherited meeting-room booking service: the agent exploring the package, writing, and running a `%UnitTest` suite that goes red on a documented defect (the code rejects the back-to-back bookings allowed by its own comment), applying a one-character fix, and re-running the suite to green. You simply need to drive everything with plain-language prompts in OpenCode, and every mutation will become a visible and auditable call against the live namespace.

## Who This Article Is For

This guide is for InterSystems developers who maintain ObjectScript applications on IRIS and want to hand out a test-first loop (exploring, testing, red indication, fix, green indication) to an AI agent working against a live namespace. No prior MCP experience is required: the companion repository ships the application, the container, and the client registration.

iris-agentic-dev is an MCP server that gives an AI coding agent a live connection to InterSystems IRIS (introspection, document read/write, compilation with structured errors, and SQL) against a running instance instead of files on disk. In practice, you hand over the busywork. You state the task in plain words: "Explore this package, write a test suite, run it, fix this class," and the agent does the rest against the live instance (finds and reads the classes, probes the data, writes and compiles code in place, runs the tests where the app actually lives, and reports the verdict back into the conversation). No portal hopping, no copy-pasting between editor and terminal, while every mutation becomes a visible and auditable call. It works with any MCP client, and this article runs it in [OpenCode](https://opencode.ai), the open-source terminal agent. If you are new to iris-agentic-dev, Thomas Dyar's [introduction](https://community.intersystems.com/post/iris-agentic-dev-give-your-ai-live-connection-iris-part-1-problem-tool-and-getting-started) covers the problem it solves and the getting-started flow. Here we put it to work the way a developer actually does: **test-first, working against a live namespace, with a real defect to catch.**

## Setup

```bash
curl -LO "https://github.com/jrpereirajr/articles/raw/refs/heads/article/iris-agentic-dev-in-practice/iris-agentic-dev-in-practice/iris-agentic-dev-in-practice.zip" && unzip iris-agentic-dev-in-practice.zip && cd iris-agentic-dev-in-practice/agentic-tdd-iris/
docker compose up -d --build
```

The companion repository ships a small meeting-room reservation service — the `rooms` package — already loaded into an IRIS Community container:

- `rooms.Scheduler` — the overlap rules: `ToMinutes()` and the method that matters, `Overlaps(start1, end1, start2, end2)`.
- `rooms.Booking` — a persistent store with `CanBook()` and `Book()`.
- `rooms.API` — a REST dispatch (`POST /api/rooms/bookings`, `GET /api/rooms/availability`).

It has **no tests**. The reservation calendar is a single-day calendar with `HH:MM` times. However, like any inherited code, it comes with a behavior question nobody wrote down: what exactly happens when one booking ends at 10:00, and another starts at the same time?

The build bakes everything: the fresh-container account fix, the REST web application, the seed classes, and the test-root directory the `%UnitTest.Manager` expects. Just wait for `healthy`, then open OpenCode **in that directory**:

```bash
opencode
```

The repository ships an `opencode.json` that registers the iris-agentic-dev MCP server for the project — nothing to copy.

### Verify the Registration

Before talking to the agent, confirm that the MCP server is registered: type `/mcps` or `/status` in the message box. OpenCode lists its MCP servers and their status:

![opencode's /status screen showing the iris-agentic-dev MCP server registered](https://raw.githubusercontent.com/jrpereirajr/articles/refs/heads/article/iris-agentic-dev-in-practice/iris-agentic-dev-in-practice/agentic-tdd-iris/images/status.png)

That dialog is the registration receipt: one server, `iris-agentic-dev`, **connected** and enabled for this project. Registration is not yet a working channel, though. That is why everything that follows (from reading classes to compiling code and running tests) rides on that one connection. So before asking the agent for anything real, remember that the first prompt is a sanity check of the channel itself:

`**On reproducibility**: every transcript below comes from one real session, but yours will differ. LLM output is nondeterministic: your agent will phrase things in its own way and design its own suite. The IRIS side, however, will be reproduced: the version, the ports, the verdicts, the 409s, and the arc of the loop (red for the documented reason, green after the one-character fix).

**Prompt:**

`Check your connection to IRIS and show me the details.`

```
  ┃
  ┃  Check your connection to IRIS and show me the details.
  ┃

     + Thought: 7.7s

     ⚙ iris-agentic-dev_check_config
     ⚙ iris-agentic-dev_iris_servers [probe=true]

     + Thought: 1.4s

     ⚙ iris-agentic-dev_iris_servers [probe=true]
     ⚙ iris-agentic-dev_iris_execute [code=write $ZVERSION,!]

     + Thought: 32.7s

     + Thought: 1.4s

     Connected and verified live (Atelier REST, SuperUser):

     - Host: localhost:52778 → namespace USER (config file: /home/jose/dev/article-agent/.iris-agentic-dev.toml)
     - IRIS version: 2026.2 (Build 221U, Ubuntu x86-64 containers)
     - MCP server: 1.4.2, execution path atelier (HTTP, no container)
     - Write tools: enabled (inferred from namespace) · Destructive tools: disabled · TLS verify: on

     ▣  Build · GLM-5.3 · 1m 2s
```

Notice the tool calls (shown in the TUI with the `⚙ iris-agentic-dev_` prefix). The agent reached out to the MCP server's own connection-state check and probed the registered-server registry — names you never had to know. That translation is the agent's job — to answer in plain language.

> **If you see a 401 or "not connected"**, the container may still be booting, so wait for `(healthy)` in `docker ps`. The admin on this image is `SuperUser`, not `_SYSTEM`.

## See the Defect Before You Test It (Optional, 30 seconds)

The REST API exposes the behavior question as an HTTP status code:

```bash
curl -s -X POST localhost:52778/api/rooms/bookings \
     -H 'Content-Type: application/json' \
     -d '{"room":"atlantis","start":"09:00","end":"10:00","owner":"you"}'
```
```json
{"id":"1"}
```

Now book the same room **back-to-back** — starting exactly when the first one ends:

```bash
curl -s -w " [%{http_code}]" -X POST localhost:52778/api/rooms/bookings \
     -H 'Content-Type: application/json' \
     -d '{"room":"atlantis","start":"10:00","end":"11:00","owner":"bob"}'
```
```json
{"error":"room busy"} [409]
```

A room that is free at 10:00 sharp rejects a booking that starts at 10:00 sharp. Whether that is a defect depends on the *contract*, and the class comment states it plainly: *"Back-to-back bookings (one ends exactly when the other starts) do NOT conflict."* The code disagrees with its own documentation. That is exactly the kind of bug a test-first loop catches on purpose, whereas we just saw it by accident.

## The Loop

### Step 1 — Explore the Inherited Code, Plan the Suite

The Setup section left you with an untested `rooms` package in a live namespace, and before writing gets tested, you want a plan grounded in what the code actually does, not in what the class names suggest. This is where the live connection pays for itself first: the agent explores the package, reads the sources, and checks the store, so every expectation in its plan is stated against something it has just verified. Plan only, no code yet — in a test-first loop, expectations are written down before any tests even exist.

**Prompt:**

`This IRIS container ships an inherited meeting-room scheduler — the rooms package: rooms.Scheduler, rooms.Booking, and rooms.API. No tests exist at this time. Explore the package and propose a test plan for the interval-overlap logic: which edge cases matter? Plan only — do not code yet.

```
  ┃
  ┃  This IRIS container ships an inherited meeting-room scheduler — the rooms package: rooms.Scheduler, rooms.Booking,
  ┃  rooms.API. No tests exist. Explore the package and propose a test plan for the interval-overlap logic: which edge
  ┃  cases matter? Plan only — no code yet.
  ┃

     + Thought: 8.3s

     ⚙ iris-agentic-dev_iris_doc [mode=list, pattern=rooms.*]
     ⚙ iris-agentic-dev_iris_symbols [query=rooms.*]

     + Thought: 780ms

     ⚙ iris-agentic-dev_iris_doc [mode=get, name=rooms.Scheduler.cls]
     ⚙ iris-agentic-dev_iris_doc [mode=get, name=rooms.Booking.cls]
     ⚙ iris-agentic-dev_iris_doc [mode=get, name=rooms.API.cls]

     + Thought: 4m 39s

     ⚙ iris-agentic-dev_iris_global [action=get, global_name=^rooms.BookingD, subtree=true]
     ⚙ iris-agentic-dev_iris_admin [action=list_webapps]
     ⚙ iris-agentic-dev_iris_symbols [limit=30, query=Test]

     + Thought: 1m 12s

     ⚙ iris-agentic-dev_iris_query [mode=count, query=SELECT COUNT(*) AS cnt FROM rooms.Booking]
     ⚙ iris-agentic-dev_iris_query [query=SELECT ID, Room, StartTime, EndTime, Owner FROM rooms.Booking ORDER BY ID]

     + Thought: 4m 24s

     Package explored — three classes, live web app at /api/rooms, store is empty, %UnitTest framework available.

     + Thought: 2.1s

     What I found

     ┌───────────────────────────────┬──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┐
     │ Class                         │ Role                                                                                                             │
     ├───────────────────────────────┼──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┤
     │ `rooms.Scheduler`             │ Pure logic: `ToMinutes("HH:MM")`, `Overlaps(s1,e1,s2,e2)`                                                        │
     │ `rooms.Booking` (%Persistent) │ `CanBook` (SQL scan + Overlaps), `Book` (check → %Save, returns id or `""`+reason). No time validation anywhere. │
     │ `rooms.API` (%CSP.REST)       │ POST `/bookings` (200/409/400), GET `/availability`. Live at `/api/rooms`.                                       │
     └───────────────────────────────┴──────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘

     Key finding — the overlap logic contradicts its own spec. The comment in rooms.Scheduler promises back-to-back
     bookings do NOT conflict ("the room is free the moment a reservation ends"), but Overlaps computes (s1 <= e2) &&
     (s2 <= e1) — closed intervals. So 09:00–10:00 vs 10:00–11:00 → conflict=1. The <= should be <. This is exactly what
     the tests must catch.

     Test plan — rooms.Tests (%UnitTest.TestCase, USER namespace)

     Setup/TearDown: ##class(rooms.Booking).%KillExtent() — store is currently empty, so tests can own it.

     A. Overlaps boundary matrix (pure, the heart of the plan)
     1. Identical windows → 1; disjoint → 0 (sanity)
     2. Partial overlap, both argument orders → 1
     3. Containment, both orders → 1
     4. Back-to-back: A 09:00–10:00, B 10:00–11:00 → 0 (per spec; fails today) — and the mirrored order, so the fix must
     be symmetric
     5. Symmetry sweep: Overlaps(a,b) == Overlaps(b,a) across the matrix
     6. Zero-length booking (10:00–10:00 vs 09:00–11:00) → decide: half-open semantics say 0; today returns 1
     7. One-minute overlap (09:59–10:58 vs 10:57–11:00) → 1, catches off-by-one beyond exact equality

     B. ToMinutes — "00:00"→0, "23:59"→1439, "09:30"→570, single-digit "9:00"→540; "24:00"→1440 (end-of-day convention).
     Malformed inputs never throw: ""→0, "abc"→0, "0900"→54000 — pin the decision to *validate in Book* rather than
     accept garbage.

     C. CanBook (store-aware) — empty calendar → 1; overlapping stored row → 0; conflict in the 2nd of 3 rows (loop
     scans past non-conflicts); room isolation ("atlantis" vs "olympia"); room-name case/trailing-space collation (pin
     actual SQL behavior); back-to-back at store level → 1 per spec (red today).

     D. Book — happy path round-trips all fields via %OpenId; conflict → "" + reason "room busy" and no row created
     (count unchanged); overlong Room (>32, MAXLEN) → "" + save-error reason; inverted interval (14:00→09:00) currently
     saves silently — desired: reject with "invalid interval"; midnight-crossing 23:00–"00:00" is the same inverted
     class (recommend reject or normalize to 24:00).

     E. API (thin, /api/rooms) — POST valid → 200 {"id":N}; overlapping → 409 "room busy"; malformed JSON → 400 (the
     Rewind/Try pattern is fragile — pin it); missing room field → decide reject; GET /availability shape + StartTime
     sort + empty array for unknown room.

     Execution order (TDD): A4 + C-back-to-back + E-409-then-200 first — red, exposing the <= bug; fix to <; green. Then
     D inverted/zero-length validation as a second red-green cycle. B malformed-time validation as a third. Everything
     else should pass immediately; if not, the suite found another inherited bug. Run via iris_test pattern rooms.Tests,
     then iris_coverage to prove the Overlaps branches are exercised.

     ▣  Build · GLM-5.3 · 11m 44s
```

Notice the tool calls: document listing and symbol queries map the package, and the agent reads the sources before planning, so every expectation in the plan is stated against what it can verify.

### Step 2 — Write the Suite

With the plan from Step 1 agreed, the next move is to turn it into code, and to put it where it will run. The prompt names the cases that matter and pins the contract (back-to-back must be allowed); the agent writes the suite as a real class in the live namespace and compiles it in place — write and compile are one auditable call.

**Prompt:**

`Write the test suite as class rooms.Tests. Cover at least one partial overlap, one interval contained in the other, exact duplicate, back-to-back adjacency (09:00-10:00, then 10:00-11:00 in the same room must be allowed), and different rooms never conflicting. Compile it.

```
  ┃
  ┃  Write the test suite as class rooms.Tests. Cover at least: partial overlap, one interval contained in the other,
  ┃  exact duplicate, back-to-back adjacency (09:00-10:00 then 10:00-11:00 in the same room must be allowed), and
  ┃  different rooms never conflicting. Compile it.
  ┃

     + Thought: 6m 53s

     ⚙ iris-agentic-dev_skill [action=describe, name=objectscript-guardrails]
     ⚙ iris-agentic-dev_skill [action=describe, name=objectscript-review]
     ⚙ iris-agentic-dev_skill [action=describe, name=objectscript-unit-test]
     ⚙ iris-agentic-dev_iris_doc [mode=get, name=%UnitTest.TestCase.cls]
     → Glob pattern=**/*.cls
     → Read .

     + Thought: 7m 16s

     Skills registry entries are empty (nothing extra to follow), and %UnitTest.TestCase confirms the pattern: Include
     %outUnitTest for the $$$Assert* macros, hooks are OnBeforeOneTest/OnAfterAllTests, test methods named Test*. The
     repo keeps source in src/ — checking local conventions before writing:

     → Read src/rooms.Scheduler.cls

     + Thought: 1.2s

     Local source matches the server and uses tabs. Writing the suite:

  ┃
  ┃  ← Create src/rooms.Tests.cls
  ┃
  ┃  Include %outUnitTest
  ┃
  ┃  /// Unit tests for the rooms package's interval-overlap logic.
  ┃  /// Every test starts from an empty booking store (OnBeforeOneTest wipes it),
  ┃  /// so tests are hermetic and order-independent.
  ┃  Class rooms.Tests Extends %UnitTest.TestCase
  ┃  {
  ┃
  ┃  /// Wipes the persistent booking store so tests run on a clean calendar.
  ┃  ClassMethod ClearStore() As %Status
  ┃  {
  ┃  	Quit ##class(rooms.Booking).%KillExtent()
  ┃  }
  ┃
  ┃  Method OnBeforeOneTest(testname As %String) As %Status
  ┃  {
  ┃  	Quit ..ClearStore()
  ┃  }
  ┃
  ┃  Method OnAfterAllTests() As %Status
  ┃  {
  ┃  	Quit ..ClearStore()
  ┃  }
  ┃
  ┃  /// Partial overlap: intervals sharing some — but not all — time conflict.
  ┃  Method TestPartialOverlap()
  ┃  {
  ┃  	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","10:00","09:30","10:30"), 1, "09:00-10:00 overlaps
  ┃  09:30-10:30")
  ┃  	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
  ┃  	Do $$$AssertNotEquals(id1, "", "first booking in an empty room succeeds")
  ┃  	Set id2 = ##class(rooms.Booking).Book("atlantis","09:30","10:30","bob",.reason)
  ┃  	Do $$$AssertEquals(id2, "", "partially overlapping booking in the same room is denied")
  ┃  	Do $$$AssertEquals($Get(reason), "room busy", "denial reports 'room busy'")
  ┃  }
  ┃
  ┃  /// Containment: an interval fully inside another conflicts, in both argument orders.
  ┃  Method TestContainedInterval()
  ┃  {
  ┃  	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","12:00","10:00","11:00"), 1, "09:00-12:00 contains
  ┃  10:00-11:00")
  ┃  	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("10:00","11:00","09:00","12:00"), 1, "containment is
  ┃  symmetric")
  ┃  	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","12:00","alice",.reason)
  ┃  	Do $$$AssertNotEquals(id1, "", "morning block books fine")
  ┃  	Set id2 = ##class(rooms.Booking).Book("atlantis","10:00","11:00","bob",.reason)
  ┃  	Do $$$AssertEquals(id2, "", "booking inside an existing block is denied")
  ┃  }
  ┃
  ┃  /// Exact duplicate: same window, same room — the second booking must be denied.
  ┃  Method TestExactDuplicate()
  ┃  {
  ┃  	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","10:00","09:00","10:00"), 1, "identical windows
  ┃  overlap")
  ┃  	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
  ┃  	Do $$$AssertNotEquals(id1, "", "original booking succeeds")
  ┃  	Set id2 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","mallory",.reason)
  ┃  	Do $$$AssertEquals(id2, "", "exact duplicate in the same room is denied")
  ┃  	Do $$$AssertEquals($Get(reason), "room busy", "duplicate reports 'room busy'")
  ┃  }
  ┃
  ┃  /// Back-to-back: 09:00-10:00 then 10:00-11:00 in the same room must be ALLOWED —
  ┃  /// per rooms.Scheduler, the room is free the moment a reservation ends.
  ┃  Method TestBackToBackSameRoom()
  ┃  {
  ┃  	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","10:00","10:00","11:00"), 0, "09:00-10:00 does not
  ┃  overlap 10:00-11:00")
  ┃  	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("10:00","11:00","09:00","10:00"), 0, "adjacency is
  ┃  symmetric")
  ┃  	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
  ┃  	Do $$$AssertNotEquals(id1, "", "first booking succeeds")
  ┃  	Set id2 = ##class(rooms.Booking).Book("atlantis","10:00","11:00","bob",.reason)
  ┃  	Do $$$AssertNotEquals(id2, "", "back-to-back booking in the same room is allowed")
  ┃  	// Same rule in the other direction: the existing booking starts when the new one ends.
  ┃  	Do $$$AssertStatusOK(..ClearStore())
  ┃  	Set id3 = ##class(rooms.Booking).Book("atlantis","10:00","11:00","carol",.reason)
  ┃  	Do $$$AssertNotEquals(id3, "", "late booking succeeds")
  ┃  	Set id4 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","dave",.reason)
  ┃  	Do $$$AssertNotEquals(id4, "", "booking ending exactly when another starts is allowed")
  ┃  }
  ┃
  ┃  /// Different rooms never conflict: identical or overlapping windows in other rooms book fine.
  ┃  Method TestDifferentRoomsNeverConflict()
  ┃  {
  ┃  	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
  ┃  	Do $$$AssertNotEquals(id1, "", "atlantis booking succeeds")
  ┃  	Set id2 = ##class(rooms.Booking).Book("olympia","09:00","10:00","bob",.reason)
  ┃  	Do $$$AssertNotEquals(id2, "", "identical window in a different room is allowed")
  ┃  	Set id3 = ##class(rooms.Booking).Book("zeus","09:30","10:30","carol",.reason)
  ┃  	Do $$$AssertNotEquals(id3, "", "overlapping window in a third room is allowed")
  ┃  }
  ┃
  ┃  }
  ┃

     + Thought: 26.2s

     ⚙ iris-agentic-dev_iris_doc [content=Include %outUnitTest

       /// Unit tests for the rooms package's interval-overlap logic.
       /// Every test starts from an empty booking store (OnBeforeOneTest wipes it),
       /// so tests are hermetic and order-independent.
       Class rooms.Tests Extends %UnitTest.TestCase
       {

       /// Wipes the persistent booking store so tests run on a clean calendar.
       ClassMethod ClearStore() As %Status
       {
       	Quit ##class(rooms.Booking).%KillExtent()
       }

       Method OnBeforeOneTest(testname As %String) As %Status
       {
       	Quit ..ClearStore()
       }

       Method OnAfterAllTests() As %Status
       {
       	Quit ..ClearStore()
       }

       /// Partial overlap: intervals sharing some — but not all — time conflict.
       Method TestPartialOverlap()
       {
       	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","10:00","09:30","10:30"), 1, "09:00-10:00 overlaps
       09:30-10:30")
       	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
       	Do $$$AssertNotEquals(id1, "", "first booking in an empty room succeeds")
       	Set id2 = ##class(rooms.Booking).Book("atlantis","09:30","10:30","bob",.reason)
       	Do $$$AssertEquals(id2, "", "partially overlapping booking in the same room is denied")
       	Do $$$AssertEquals($Get(reason), "room busy", "denial reports 'room busy'")
       }

       /// Containment: an interval fully inside another conflicts, in both argument orders.
       Method TestContainedInterval()
       {
       	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","12:00","10:00","11:00"), 1, "09:00-12:00 contains
       10:00-11:00")
       	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("10:00","11:00","09:00","12:00"), 1, "containment is
       symmetric")
       	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","12:00","alice",.reason)
       	Do $$$AssertNotEquals(id1, "", "morning block books fine")
       	Set id2 = ##class(rooms.Booking).Book("atlantis","10:00","11:00","bob",.reason)
       	Do $$$AssertEquals(id2, "", "booking inside an existing block is denied")
       }

       /// Exact duplicate: same window, same room — the second booking must be denied.
       Method TestExactDuplicate()
       {
       	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","10:00","09:00","10:00"), 1, "identical windows
       overlap")
       	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
       	Do $$$AssertNotEquals(id1, "", "original booking succeeds")
       	Set id2 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","mallory",.reason)
       	Do $$$AssertEquals(id2, "", "exact duplicate in the same room is denied")
       	Do $$$AssertEquals($Get(reason), "room busy", "duplicate reports 'room busy'")
       }

       /// Back-to-back: 09:00-10:00 then 10:00-11:00 in the same room must be ALLOWED —
       /// per rooms.Scheduler, the room is free the moment a reservation ends.
       Method TestBackToBackSameRoom()
       {
       	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("09:00","10:00","10:00","11:00"), 0, "09:00-10:00 does not
       overlap 10:00-11:00")
       	Do $$$AssertEquals(##class(rooms.Scheduler).Overlaps("10:00","11:00","09:00","10:00"), 0, "adjacency is
       symmetric")
       	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
       	Do $$$AssertNotEquals(id1, "", "first booking succeeds")
       	Set id2 = ##class(rooms.Booking).Book("atlantis","10:00","11:00","bob",.reason)
       	Do $$$AssertNotEquals(id2, "", "back-to-back booking in the same room is allowed")
       	// Same rule in the other direction: the existing booking starts when the new one ends.
       	Do $$$AssertStatusOK(..ClearStore())
       	Set id3 = ##class(rooms.Booking).Book("atlantis","10:00","11:00","carol",.reason)
       	Do $$$AssertNotEquals(id3, "", "late booking succeeds")
       	Set id4 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","dave",.reason)
       	Do $$$AssertNotEquals(id4, "", "booking ending exactly when another starts is allowed")
       }

       /// Different rooms never conflict: identical or overlapping windows in other rooms book fine.
       Method TestDifferentRoomsNeverConflict()
       {
       	Set id1 = ##class(rooms.Booking).Book("atlantis","09:00","10:00","alice",.reason)
       	Do $$$AssertNotEquals(id1, "", "atlantis booking succeeds")
       	Set id2 = ##class(rooms.Booking).Book("olympia","09:00","10:00","bob",.reason)
       	Do $$$AssertNotEquals(id2, "", "identical window in a different room is allowed")
       	Set id3 = ##class(rooms.Booking).Book("zeus","09:30","10:30","carol",.reason)
       	Do $$$AssertNotEquals(id3, "", "overlapping window in a third room is allowed")
       }

       }
       , mode=put, name=rooms.Tests.cls]

     + Thought: 212ms

     Saved to IRIS. Compiling:

     ⚙ iris-agentic-dev_iris_compile [target=rooms.Tests.cls]

     + Thought: 1.5s

     Compiled clean. Running it to confirm it executes and show current status:

     ⚙ iris-agentic-dev_iris_test [pattern=rooms.Tests]

     + Thought: 3m 1s

     ⚙ iris-agentic-dev_docs_introspect [class_name=%UnitTest.Manager]

     + Thought: 1m 29s

     RunTest treats its spec as a directory under ^UnitTestRoot — that's why the exact class name didn't match. Trying
     the package as the spec:

     ⚙ iris-agentic-dev_iris_test [pattern=rooms]

     + Thought: 1m 58s

     Probing how the manager resolves the class, and checking the container layout:

     ⚙ iris-agentic-dev_iris_execute [code=Set sc = ##class(%UnitTest.Manager).RunTest("rooms.Tests", "/noload
       /nodelete")
       Write "SC=", $System.Status.GetOneErrorText(sc), !]
     → Read docker-compose.yml
     → Read iris.script

     + Thought: 2m 18s

     The manager claims "All PASSED" — that's suspicious given the <= bug should turn the back-to-back test red.
     Verifying what actually ran:

     ⚙ iris-agentic-dev_iris_execute [code=Write "Overlaps 09-10 vs 10-11 => ",
       ##class(rooms.Scheduler).Overlaps("09:00","10:00","10:00","11:00"), !
       Write "Result 3 nodes:", !
       Set node = "", count = 0
       For Set node = $Order(^UnitTest.Result(3, node)) Quit:node = ""  {
       	Write node, !
       	Set count = count + 1
       	Quit:count > 30
       }]
     ⚙ iris-agentic-dev_iris_query [query=SELECT * FROM "%UnitTest"."Result" WHERE ID = 3]

     + Thought: 2m 43s

     Empty output on that execute is odd — splitting into simpler probes:

     ⚙ iris-agentic-dev_iris_execute [code=Write ##class(rooms.Scheduler).Overlaps("09:00","10:00","10:00","11:00"),!]
     ⚙ iris-agentic-dev_iris_global [action=list, global_name=^UnitTest.Result]

     + Thought: 7.5s

     Overlaps returns 1 for back-to-back — the bug is real, so "All PASSED" had to be a vacuous run. Inspecting what
     result 3 recorded:

     ⚙ iris-agentic-dev_iris_global [action=list, global_name=^UnitTest.Result, subscripts=["3"]]

     + Thought: 1m 3s

     The ["3"] string subscript won't match a numeric global subscript — probing the result nodes directly:

     ⚙ iris-agentic-dev_iris_execute [code=Write $Get(^UnitTest.Result(1))," || ",$Get(^UnitTest.Result(2))," ||
       ",$Get(^UnitTest.Result(3)),!]
     ⚙ iris-agentic-dev_iris_execute [code=Write $Order(^UnitTest.Result(3,"")),!]

     + Thought: 3m 50s

     Result 3 has no child nodes — zero tests ran; "All PASSED" was vacuous. The testspec is being treated as a
     directory under ^UnitTestRoot (set in the seed script), not as a class. Reading DebugRunTestCase's source — the
     manager's no-filesystem path for already-compiled classes:

     ⚙ iris-agentic-dev_iris_search [documents=["%UnitTest.Manager.cls"], query=DebugRunTestCase]

     + Thought: 2m 20s

     DebugRunTestCase is the manager's no-filesystem path for already-compiled classes. Trying it directly:

     ⚙ iris-agentic-dev_iris_execute [code=Do
       ##class(%UnitTest.Manager).DebugRunTestCase("rooms","rooms.Tests","/nodelete")]

     + Thought: 2m 42s

     + Thought: 797ms

     Done — src/rooms.Tests.cls (5 test methods, hermetic via %KillExtent in OnBeforeOneTest), pushed to IRIS and
     compiled clean.

     Ran it to verify (via DebugRunTestCase; the iris_test pattern path resolves testspec as a ^UnitTestRoot directory
     and finds nothing):

     - TestPartialOverlap, TestContainedInterval, TestExactDuplicate, TestDifferentRoomsNeverConflict — pass
     - TestBackToBackSameRoom — fails (4 red assertions), exactly as the plan predicted: rooms.Scheduler.cls:18 uses <=
     (closed intervals), so 09:00–10:00 + 10:00–11:00 conflict, contradicting the class comment. One-character fix (<= →
     <) turns it green — say the word.

     ▣  Build · GLM-5.3 · 42m 1s
```

Notice the tool calls: the suite goes in through a single document write with compile — write and compile are one auditable call — and the tail after it is one investigation: a run that comes back vacuously green, the probe that disproves it, the result storage that shows zero tests ran, and the Manager's source that yields the no-filesystem invocation. The two callouts in Step 3 describe that trap and its fix.

### Step 3 — RED: Run the Suite and Face the Failure

Test-first starts red: before touching any code, run the suite and let it fail (the failure guarantees that the test can actually catch the defect). The prompt is deliberately bare: after Step 2's investigation, the agent already knows a reliable way to run the suite, and what you want now is the verdict, not the journey.

**Prompt:**

`Run the test suite and show me the results.

```
  ┃
  ┃  Run the test suite and show me the results.
  ┃

     + Thought: 12.1s

     ⚙ iris-agentic-dev_iris_execute [code=Do
       ##class(%UnitTest.Manager).DebugRunTestCase("rooms","rooms.Tests","/nodelete")]

     + Thought: 14.3s

     + Thought: 775ms

     4 passed, 1 failed (result index 5, USER namespace):

     ┌─────────────────────────────────┬─────────────────────────┐
     │ Test                            │ Result                  │
     ├─────────────────────────────────┼─────────────────────────┤
     │ TestPartialOverlap              │ pass                    │
     │ TestContainedInterval           │ pass                    │
     │ TestExactDuplicate              │ pass                    │
     │ TestDifferentRoomsNeverConflict │ pass                    │
     │ TestBackToBackSameRoom          │ **FAIL** (4 assertions) │
     └─────────────────────────────────┴─────────────────────────┘

     The red test is the expected one: Overlaps uses <= in src/rooms.Scheduler.cls:18, so 09:00–10:00 and 10:00–11:00 in the same room conflict — contradicting the "back-to-back allowed" rule the class documents. Both pure-function assertions and both store-level bookings fail. Changing <= to < on both comparisons is the fix — want me to apply it and re-run?

     ▣  Build · GLM-5.3 · 57.2s
```

Notice the tool call — a single invocation on the path the agent had already proven while writing the suite. The verdict comes back from the runner as data: per-test rows, the failing method with its assertion count, and the source line behind it. The navigation that led here belongs to the Step 2 turn; the two callouts below describe it.

> **If the agent's first run attempt comes back empty (`NO_TESTS_FOUND`)**: on fresh 2026.2 Community containers, the structured runner's pattern path resolves the testspec as a `^UnitTestRoot` directory (a compiled suite class can sit right there in the namespace and not be found). This session hit exactly that, then worked its way to a run that counts, so expect your agent to find its own way too.

> **If your agent reports `All PASSED` suspiciously fast, with no test names in the log**: it means the testspec matched no class, zero tests ran, and the green is vacuous. This session caught it empirically: the agent probed the live predicate (the back-to-back assertions cannot pass against `<=`), then queried the test-result tables and confirmed zero tests had run. Reliable paths exist — the class-name form `RunTest(":rooms.Tests", "/noload/norecursive/nodelete")` (the colon matters), or the Manager's no-filesystem `DebugRunTestCase`, which is what this session derived from the Manager's own source.

### Step 4 — Pin or Fix? (The Decision a Test-First Loop Forces)

The test is red. Now the question is not *how to make it green,* but *which side is right*: does the code define the contract (then the test pins the current behavior, and the comment gets fixed), or does the comment determine the contract (then the code is wrong, and the test stays)? In a reservation system, "back-to-back is allowed" is the classic off-by-one: a room that becomes vacant at 10:00 but cannot be used until 10:01 wastes inventory, and this intent is documented in the code. To fix it, you should change the code, not the test.

**Prompt:**

`The failing adjacency case is a real defect: the class comment says back-to-back bookings do not conflict, but the code rejects them. Fix rooms.Scheduler the TDD way — change the code, not the test — then re-run the suite.

```
  ┃
  ┃  The failing adjacency case is a real defect: the class comment says back-to-back bookings do not conflict, but the
  ┃  code rejects them. Fix rooms.Scheduler the TDD way — change the code, not the test — then re-run the suite.
  ┃

     + Thought: 17.1s

  ┃
  ┃  ← Edit src/rooms.Scheduler.cls
  ┃
  ┃    15   {
  ┃    16   	Set s1 = ..ToMinutes(startTime1), e1 = ..ToMinutes(endTime1)
  ┃    17   	Set s2 = ..ToMinutes(startTime2), e2 = ..ToMinutes(endTime2)
  ┃    18 -   	Quit (s1 <= e2) && (s2 <= e1)
  ┃    18 +   	Quit (s1 < e2) && (s2 < e1)
  ┃    19   }
  ┃    20
  ┃    21   }
  ┃

     + Thought: 36.7s

     Pushing the fix to IRIS and compiling:

     ⚙ iris-agentic-dev_iris_doc [content=/// Scheduling rules for the meeting-room reservation service.
       Class rooms.Scheduler Extends %RegisteredObject
       {

       /// Converts an HH:MM time string to minutes past midnight.
       ClassMethod ToMinutes(time As %String) As %Integer
       {
       	Quit $Piece(time, ":", 1) * 60 + $Piece(time, ":", 2)
       }

       /// Two bookings conflict when they share actual time. Back-to-back bookings
       /// (one ends exactly when the other starts) do NOT conflict — the room is
       /// free the moment a reservation ends.
       ClassMethod Overlaps(startTime1 As %String, endTime1 As %String, startTime2 As %String, endTime2 As %String) As
       %Boolean
       {
       	Set s1 = ..ToMinutes(startTime1), e1 = ..ToMinutes(endTime1)
       	Set s2 = ..ToMinutes(startTime2), e2 = ..ToMinutes(endTime2)
       	Quit (s1 < e2) && (s2 < e1)
       }

       }
       , mode=put, name=rooms.Scheduler.cls]

     ⚙ iris-agentic-dev_iris_compile [target=rooms.Scheduler.cls]

     + Thought: 201ms

     Fix compiled. Re-running the suite:

     ⚙ iris-agentic-dev_iris_execute [code=Do
       ##class(%UnitTest.Manager).DebugRunTestCase("rooms","rooms.Tests","/nodelete")]

     + Thought: 3.7s

     Fixed and green — All PASSED (5/5 tests, 23 assertions).

     - Change: src/rooms.Scheduler.cls:18 — (s1 <= e2) && (s2 <= e1) → (s1 < e2) && (s2 < e1), half-open intervals so
     back-to-back bookings no longer conflict. Tests untouched.
     - Compiled clean on IRIS; re-run confirms TestBackToBackSameRoom now passes both pure checks and both same-room
     adjacency bookings, with no regressions in duplicate/containment/overlap/room-isolation cases.

     ▣  Build · GLM-5.3 · 2m 39s
```

Notice the tool calls: one document write with compile pushes the fixed class (a single auditable write to the live namespace), and the re-run comes through the invocation that the agent derived in the red step. The fix itself was one character, and everything around it is just the agent orchestrating reads, writes, and runs.

All we needed was one character of code. The tests did not move; the code matched them.

### Step 5 — GREEN: The Receipt

The fix in Step 4 already reported green, but one run proves the fix, and a repeat confirms it was not luck. The last prompt asks for the whole suite again: every method, every assertion, the back-to-back case green along with the rest. What this receipt means outside the test runner comes right after.

**Prompt:**

`Run the full suite once more and show me the final result.

```
  ┃
  ┃  Run the full suite once more and show me the final result.
  ┃

     + Thought: 1s

     ⚙ iris-agentic-dev_iris_execute [code=Do
       ##class(%UnitTest.Manager).DebugRunTestCase("rooms","rooms.Tests","/nodelete")]

     + Thought: 3.3s

     All PASSED (result index 7) — 5/5 test methods, 23/23 assertions, ~0.005s total:

     ┌─────────────────────────────────┬─────────────────────┐
     │ Test                            │ Result              │
     ├─────────────────────────────────┼─────────────────────┤
     │ TestBackToBackSameRoom          │ pass (7 assertions) │
     │ TestContainedInterval           │ pass                │
     │ TestDifferentRoomsNeverConflict │ pass                │
     │ TestExactDuplicate              │ pass                │
     │ TestPartialOverlap              │ pass                │
     └─────────────────────────────────┴─────────────────────┘

     TDD cycle complete: red (back-to-back rejected) → one-line fix in rooms.Scheduler → green, no regressions.

     ▣  Build · GLM-5.3 · 40.9s
```

Notice the tool call: a single re-run through the same no-filesystem path makes the answer compose the per-test table with assertion counts and the loop's closing verdict.

As for the API, the same back-to-back shape that failed before the fix works here, even on lobby (a room the suite never leaves behind). Its per-test cleanup wipes the store, so the calendar comes back empty after the green:

```bash
curl -s -X POST localhost:52778/api/rooms/bookings \
     -H 'Content-Type: application/json' \
     -d '{"room":"lobby","start":"09:00","end":"10:00","owner":"you"}'
curl -s -w " [%{http_code}]" -X POST localhost:52778/api/rooms/bookings \
     -H 'Content-Type: application/json' \
     -d '{"room":"lobby","start":"10:00","end":"11:00","owner":"bob"}'
curl -s "localhost:52778/api/rooms/availability?room=lobby"
```
```json
{"id":"1"}
{"id":"2"} [200]
{"room":"lobby","booked":[{"start":"09:00","end":"10:00"},{"start":"10:00","end":"11:00"}]}
```

Back-to-back books now. (The IDs are whatever your session's counter is at. What matters is the second POST's \[200\]: the same request returned \[409\] before the fix.) One character of code (<= → <), one documented contract, one test-first loop caused red because the code betrayed its own comment, and green because the fix matched the intent.

## What the Loop Actually Bought You

- **The agent worked against the live instance through iris-agentic-dev.** Every IRIS-side action in this session went through the MCP connection: the classes were read from the namespace, the overlap predicate was probed with live calls, SQL confirmed the store's state, the suite was written and compiled in place, and the tests ran where the app actually lives. The ground truth always came from the running instance — never from an assumption about the files.
- **Plain words became a full workflow.** Six natural-language prompts (check the connection, explore, write the suite, run it, fix the class, run it again) and the agent assembled every tool call on its own (the connection check, source reads, framework introspection, macro lookups, guarded document writes with compile, structured test runs, and log retrieval). You never needed to know a single tool name. That translation is what the MCP connection does for you.
- **Writes were auditable and atomic.** The suite and the fix each reached the running instance through a single document write with compile. The one-character fix landed in one call, and every mutation the agent made was a visible call in the transcripts.
- **The verdicts came from the runner, not from the agent's confidence.** The red arrived as a structured test result with per-assertion detail, pulled by the agent through the log tool — the same receipts you would open in the `%UnitTest` portal, delivered into the conversation.
- **The defect was caught on purpose, not by chance.** The 409 on back-to-back bookings was live in the API before any test existed; the loop only made the contract explicit and the fix provable.

The same loop applies to any inherited package: clone the companion repository as a template, point the agent at your classes, and start with the same six prompts.

Further reading: the [iris-agentic-dev introduction](https://community.intersystems.com/post/iris-agentic-dev-give-your-ai-live-connection-iris-part-1-problem-tool-and-getting-started) (problem, tool catalog, skills) and the [OpenCode docs](https://opencode.ai/docs) (client setup; the project-level `opencode.json` used here is documented there).

---

*Companion repository: [agentic-tdd-iris](https://github.com/jrpereirajr/articles/iris-agentic-dev-in-practice/agentic-tdd-iris). Everything in this article ran against InterSystems IRIS Community 2026.2.0.221 (`intersystems/iris-community:latest-cd`) with iris-agentic-dev 1.4.x and OpenCode — as of this writing.*

*On AI assistance: this article was written with AI tools, including the agent session shown throughout. The text and every result in it (commands, outputs, test verdicts, the fix) were reviewed and validated manually by the author against live replays before publication.*

---
