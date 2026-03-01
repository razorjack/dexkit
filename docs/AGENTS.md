# AGENTS.md

## Project Layout

- VitePress config lives in `docs/.vitepress/config.ts`.
- Documentation pages live under `docs/` as Markdown files.
- Sidebar and top nav are defined in `themeConfig` inside `docs/.vitepress/config.ts`.

## Adding a New Page

1. Create a new `.md` file in the appropriate section directory under `docs/`.
2. Add the page to the relevant sidebar group in `docs/.vitepress/config.ts`.
3. If needed, add or update a top-nav entry in `themeConfig.nav`.

## Adding a New Top-Level Pattern Section

1. Create a new section directory under `docs/` (example: `docs/form/`).
2. Add at least one entry page (typically `index.md`).
3. Register the section in `themeConfig.nav`.
4. Add a new grouped section in `themeConfig.sidebar` with `collapsed` behavior set intentionally.

## Run and Build

- Dev server: `cd docs && npm run docs:dev`
- Production build: `cd docs && npm run docs:build`
- Preview build: `cd docs && npm run docs:preview`

## Content Conventions

- Every page should use a single `# H1` as the page title.
- VitePress frontmatter is optional, but recommended for page descriptions and metadata.
- Docs are primarily written by LLM coding agents.

## Documentation Style Guide

### Voice & Tone

- Natural, friendly, slightly enthusiastic – the library is genuinely cool, let that come through
- Write like a developer explaining to a peer, not a textbook or a corporate manual
- Avoid LLM-isms: no "Let's dive in", "It's important to note", "In essence", "It's worth mentioning", "as we can see", "straightforward", "leverage", "utilize", "robust", "seamless"
- Use en-dash ` – ` not em-dash ` — `. The em-dash is an LLM tell
- Don't hedge – say "this works" not "this should work" or "this is designed to work"
- Slightly conversational is fine; overly casual is not

### Structure

- Code examples speak louder than words – show, don't tell
- Lead with the most common use case, then show variations
- Keep prose concise but not dry. One good sentence beats three filler sentences, but don't strip out all personality
- Every page should be self-contained – a developer landing on it from a search should understand the feature without reading other pages
- Use tables for reference-style information (options, parameters, comparison)
- Use headings to make pages scannable

### Code Examples

- Examples should be realistic – use domain concepts like users, orders, payments rather than `Foo`/`Bar`
- Show the calling code, not just the class definition
- Keep examples short. If an example needs more than ~15 lines, it's probably demonstrating too many things at once
- Don't add comments explaining what's obvious from the code. Only comment when the behavior is surprising or non-obvious

### What NOT to Do

- Don't repeat information that's already on another page – link to it instead
- Don't document internal implementation details (method names starting with `_`, internal modules)
- Don't add "Note:" or "Important:" callouts for things that are just normal behavior
- Don't use VitePress info/tip/warning boxes unless it's genuinely a warning (something that could break or surprise)
