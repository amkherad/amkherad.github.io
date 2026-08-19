# amkherad.github.io — Agent Guide

Jekyll blog (Chirpy theme) with localization. Configured languages live in `_config.yml` under `languages` (currently `en`, `fa`).

## Mandatory: post translations

**Every published post must exist in every configured language.**

When you create, edit, publish, or delete anything under `_posts/`:

1. **Read** [sync-post-translations](skills/sync-post-translations/SKILL.md) and follow it completely.
2. **Run** the translation checker before finishing:
   ```bash
   ruby .agents/skills/sync-post-translations/scripts/check-translations.rb
   ```
3. Do not mark the task done if the checker reports missing or orphaned translations.

Draft posts (filename starts with `.` or path contains `_drafts/` / `wip/`) are exempt until published.

## Localization conventions

| Item | Location |
|------|----------|
| Languages list | `_config.yml` → `languages`, `default_lang` |
| UI strings | `_data/locales/{lang}.yml` |
| English posts | `_posts/YYYY-MM-DD-slug.md` |
| Other languages | `_posts/YYYY-MM-DD-slug.{lang}.md` |
| Link translations | Same `translation_key` in every language version |
| Non-default URLs | `permalink: /{lang}/posts/{slug}/` |

## Other project rules

- Prefer minimal theme changes; override via `_includes/`, `_layouts/`, `_data/`.
- Production builds use `JEKYLL_ENV=production` (see `tools/build.sh`).
- Do not commit unless the user asks.

## Skill index

| Task | Skill |
|------|-------|
| Create/edit/delete blog posts | [sync-post-translations](skills/sync-post-translations/SKILL.md) |
| Add a new site language | sync-post-translations → "Adding a new language" |
