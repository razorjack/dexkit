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
- Keep writing clear, concise, and technical, with practical Ruby examples where applicable.
