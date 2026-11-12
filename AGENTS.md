# kora_businesses agent guide

`kora_businesses` bundles several civilian jobs (mechanic, taxi, garbage, recycle, tow, CCTV, plus an unloaded hotdog job) for a Kora FiveM server. `config.lua` toggles and loads each job from `jobs/<job>/` (`shared.lua` config, `client.lua`, `server.lua`), `init.lua` registers the job config tables with `Kora.config.adopt` (overrides in `businesses.config.local.lua`), `locales/en.lua` holds recycle and hotdog strings, and `tests/` contains offline Lua tests and kora_qa scenarios.

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first; it has the overview and a documentation map linking every page.

Docs layout: `index.md` (hub), `installation.md` (dependencies, boot, local overrides, file layout), `how-to-use.md` (per-job gameplay), `commands.md` (commands and keybinds), `api/` (one page per module: callbacks, events, functions; `api/index.md` lists them), topic pages (`configuration.md`, `jobs.md`, `exports.md`, `events.md`, `database.md`, `items.md`) and `features/<job>.md`. Update the page that owns the topic you changed, and keep `api/<module>.md` in step with `jobs/<job>/`.

Feature and behaviour changes must update the matching docs in the same change.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.

## Shared contribution standards

Read [CONTRIBUTING.md](CONTRIBUTING.md) before editing. Humans and agents follow
the same Kora standards and self-contained local Lua checks. Preserve the domain
constraints above and in module guides; record policy conflicts explicitly.
