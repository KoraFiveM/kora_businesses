# kora_businesses agent guide

`kora_businesses` bundles several civilian jobs (mechanic, taxi, garbage, recycle, tow, CCTV, plus an unloaded hotdog job) for a Kora FiveM server. `config.lua` toggles and loads each job from `jobs/<job>/` (`shared.lua` config, `client.lua`, `server.lua`), `init.lua` registers the job config tables with `Kora.config.adopt` (overrides in `businesses.config.local.lua`), `locales/en.lua` holds recycle and hotdog strings, and `tests/` contains offline Lua tests and kora_qa scenarios.

## Documentation

User-facing documentation lives in `docs/` (Markdown, published via the Kora Docusaurus site, kora_docs_next). Read `docs/index.md` first for an overview of features, configuration, commands, exports, events and database usage.

When you add, change, or remove a feature, config option, command, export, event, item, permission, or database table/column, update the matching page in `docs/` in the same change. Keep docs accurate to the code; do not document behaviour that does not exist.

Docs rules: plain Markdown with `title`/`sidebar_position` front matter (no `id`/`slug`), relative links only between docs pages, assets inside `docs/`, fenced code blocks with a language, and no raw `<`, `>`, `{`, `}` outside code (pages are parsed as MDX). The release version comes from `fxmanifest.lua`'s `version` field.
