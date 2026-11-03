# agentic-tdd-iris

Companion repository for the article — an **inherited InterSystems IRIS app with a
latent bug and no tests**, ready for a test-first session with
[iris-agentic-dev](https://github.com/intersystems-community/iris-agentic-dev)
in [opencode](https://opencode.ai).

The container ships a small meeting-room reservation service (`rooms.*`):
`scheduler` rules, a persistent `Booking` store and a REST API. Your agent
explores it through introspection — the files in `src/` are here for you to
read; **the agent works against the live namespace**, not against the repo.

## Requirements

- Docker
- IRIS Community (image: `intersystems/iris-community:latest-cd` — 2026.2.0.221
  as of this writing)
- [iris-agentic-dev](https://github.com/intersystems-community/iris-agentic-dev) 1.4.x
- [opencode](https://opencode.ai) (or any MCP client)

## What's here

| Path | What it is |
|------|------------|
| `opencode.json` | project-level opencode config — registers the MCP server when you launch opencode in this directory |
| `images/status.png` | the opencode registration screen — a compact, essentially-visual TUI dialog (the one screenshot the article keeps) |
| `transcripts/` | verbatim per-step TUI text captures — the COMPLETE output of each prompt in terminal format (the article's appendix material) |
| `Dockerfile` · `iris.script` · `docker-compose.yml` | the environment — `docker compose up -d --build` gives you IRIS with the app loaded; the one-time account fix, the REST web app and the seed load are all baked into the image during the build |
| `src/rooms.Scheduler.cls` | the overlap rules — where the story lives |
| `src/rooms.Booking.cls` | persistent store + `CanBook` / `Book` |
| `src/rooms.API.cls` | REST dispatch (`POST /api/rooms/bookings`, `GET /api/rooms/availability`) |

## Quick start

1. Build and start the container (everything is baked into the image — nothing
   manual):

   ```bash
   docker compose up -d --build
   ```

2. Open opencode **in this directory** — the repo ships `opencode.json`, which
   registers the MCP server for the project:

   ```bash
   opencode
   ```

3. Follow the article: explore the `rooms` package, plan the suite, write it,
   watch the red, decide pin-or-fix, go green.

## Tips

- The admin on this image is `SuperUser` (not `_SYSTEM`).
- The seed intentionally contains a defect against its own stated intent — do
  not "fix" `src/` before the session; the point is to catch it test-first.
- Run suites with the `%UnitTest.Manager` call — on fresh 2026.2 Community
  containers the `iris_test` tool may report `NO_TESTS_FOUND` even when the
  suite is compiled and fine; the Manager is the reliable path:

  ```
  iris_execute:
    Do ##class(%UnitTest.Manager).RunTest("rooms.Tests","/noload/nodelete")
  ```

- The Manager resolves a suite against `^UnitTestRoot`; the build pre-creates
  `.../dev/tests/rooms/Tests` for the suite name used in the article
  (`rooms.Tests`). A different suite name may need its matching directory
  (you would see `ERROR #5007: Directory name ... is invalid`).
- Quick API smoke test once the container is up:

  ```bash
  curl -s -X POST localhost:52778/api/rooms/bookings \
       -H 'Content-Type: application/json' \
       -d '{"room":"atlantis","start":"09:00","end":"10:00","owner":"you"}'
  ```

- Never commit a real `.iris-agentic-dev.toml` (it carries credentials).
- opencode's documented global config is `~/.config/opencode/opencode.json`
  (or `.jsonc`); some tooling READMEs (including iris-agentic-dev's, as of this
  writing) say `config.json` — if one doesn't register for you, try the other.
