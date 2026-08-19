---
name: sync-post-translations
description: >-
  Keeps Jekyll blog posts translated and synchronized across all configured
  languages (en, fa, …). Use when creating, editing, publishing, or deleting
  files in _posts/, when the user mentions translations, localization, i18n,
  Persian/English posts, or translation_key sync.
priority: high
---

# Sync Post Translations

## Rule

**Each published post must exist in every language listed in `_config.yml` → `languages`.**

Linked versions share the same `translation_key`. Content, titles, and descriptions are translated; structure (headings, code blocks, `<!--more-->`) stays aligned.

## When to apply

Apply this skill whenever you touch `_posts/` — including typo fixes, SEO tweaks, tag changes, and new drafts being published.

Skip only:
- Drafts whose filename starts with `.`
- Files under `_posts/wip/` or `_drafts/` until the user publishes them

When publishing a draft, remove the leading `.`, add `translation_key`, and create all language versions in the same task.

---

## File layout

| Language | File pattern | Example |
|----------|--------------|---------|
| Default (`default_lang`, usually `en`) | `_posts/YYYY-MM-DD-{slug}.md` | `2020-08-06-entity-framework-....md` |
| Other | `_posts/YYYY-MM-DD-{slug}.{lang}.md` | `2020-08-06-entity-framework-....fa.md` |

Use the **same date and slug** across all language files for one article.

---

## Front matter template

### Default language (en)

```yaml
---
title: English title
description: English SEO description
lang: en
translation_key: unique-kebab-slug   # required; shared across languages
tags: [...]
categories: [...]
---
```

### Other language (e.g. fa)

```yaml
---
title: عنوان فارسی
description: توضیح فارسی برای SEO
lang: fa
translation_key: unique-kebab-slug   # same as English version
permalink: /fa/posts/{slug}/
tags: [...]                          # same tags/categories as en
categories: [...]
---
```

Rules:
- `translation_key` is stable, kebab-case, and never changes after publish.
- `permalink` is required for non-default languages: `/{lang}/posts/{slug}/`.
- Keep `tags` and `categories` identical across translations (labels stay English).
- Preserve `<!--more-->` at the same logical position in every version.

---

## Workflows

### A. New post

```
Progress:
- [ ] Pick translation_key (kebab-case slug)
- [ ] Write default-language post with lang + translation_key
- [ ] Create one file per other language with translated title/description/body
- [ ] Align headings and code blocks across versions
- [ ] Run check-translations.rb
```

### B. Edit existing post

1. Read **all** files with the same `translation_key`.
2. Apply the user's change to every language version.
3. If the change is English-only (e.g. code fix), still update other languages' surrounding prose when meaning changed.
4. Run `check-translations.rb`.

### C. Delete post

Delete **every** file sharing that `translation_key`, or the checker will fail.

### D. Publish draft

1. Rename/remove draft prefix (`.filename` → `filename`).
2. Assign `translation_key` if missing.
3. Create missing language files.
4. Run checker.

---

## Translation guidelines

| Keep unchanged | Translate |
|----------------|-----------|
| Code blocks, identifiers, CLI commands | Titles, descriptions, prose, headings |
| URLs (unless locale-specific page exists) | Blockquotes and note callouts |
| `translation_key`, tags, categories | Link anchor text when it is prose |

**Persian (fa):**
- Natural technical Persian; keep API names, types, and NuGet packages in English.
- RTL is handled by `lang: fa` — do not use `layout: post-rtl`.
- Use formal tone consistent with existing `pages/resume-fa.md`.

**Quality bar:** A reader should get equivalent technical meaning in each language, not a literal word-for-word machine translation.

---

## Validation

Always run before completing the task:

```bash
ruby .agents/skills/sync-post-translations/scripts/check-translations.rb
```

Exit code `0` = all published posts have every language.  
Exit code `1` = missing translations, duplicates, or invalid front matter — fix before finishing.

Optional: run after `tools/build.sh` or add to CI.

---

## Adding a new language

1. Add code to `_config.yml` → `languages` (e.g. `- de`).
2. Create `_data/locales/de.yml` (copy `en.yml` structure).
3. Add `de/index.html` and `de/tabs/` pages (see existing `fa/` tree).
4. For **each** published post, add `_posts/...-.de.md` with `lang: de` and `permalink: /de/posts/{slug}/`.
5. Run checker.

---

## Quick reference

```text
_config.yml          → languages: [en, fa, ...]
_data/locales/       → UI strings (not post body)
_posts/*.md          → en (default)
_posts/*.{lang}.md   → fa, de, ...
translation_key      → links language switcher + sync group
```

See [examples.md](examples.md) for a minimal pair.
