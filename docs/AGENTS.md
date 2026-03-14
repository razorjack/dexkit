# AGENTS.md

## Project Layout

- VitePress config lives in `docs/.vitepress/config.ts`.
- Documentation pages live under `docs/` as Markdown files.
- Sidebar and top nav are defined in `themeConfig` inside `docs/.vitepress/config.ts`.
- SEO metadata and sitemap generation also live in `docs/.vitepress/config.ts`.

## Adding a New Page

1. Create a new `.md` file in the appropriate section directory under `docs/`.
2. Add the page to the relevant sidebar group in `docs/.vitepress/config.ts`.
3. If needed, add or update a top-nav entry in `themeConfig.nav`.
4. Make sure the page is not excluded by `srcExclude`. Built docs pages are included in the sitemap automatically.
5. If adding a page to the Operation section, add it to the "What's next" list in `docs/operation/index.md` with a short description.
6. Add a `description` field in the page's YAML frontmatter. This is used for the `<meta name="description">` tag, Open Graph/Twitter cards, and JSON-LD structured data. Keep it under 160 characters, specific to the page content, and include relevant class names (e.g., `Dex::Operation`). Lead with the class name, then describe what it does — not a feature shopping list. Example:
   ```yaml
   ---
   description: Dex::Operation callbacks — before, after, around, and after_commit hooks that run inside the execution pipeline.
   ---
   ```

## Adding a New Top-Level Pattern Section

1. Create a new section directory under `docs/` (example: `docs/form/`).
2. Add at least one entry page (typically `index.md`).
3. Register the section in `themeConfig.nav`.
4. Add a new grouped section in `themeConfig.sidebar` with `collapsed` behavior set intentionally.
5. Update `SECTION_TITLES` and `SECTION_ENTRY_PATHS` in `docs/.vitepress/config.ts` so canonical metadata, structured data, and sitemap priority/changefreq work correctly for the new section.

## Run and Build

- Dev server: `cd docs && npm run docs:dev`
- Production build: `cd docs && npm run docs:build`
- Preview build: `cd docs && npm run docs:preview`

## Content Conventions

- Every page should use a single `# H1` as the page title.
- Every page **must** have YAML frontmatter with a `description` field for SEO. VitePress uses this for the meta description tag, social cards, and structured data.
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

- **78-character max width** – the VitePress layout allows 78 characters per line in code snippets before a horizontal scrollbar appears. Wrap lines that exceed 78 characters. Exceptions where longer lines are preferred: single-expression blocks (`after_commit { ... }`), trailing-`if` one-liners (`error!(...) if condition`), output comments (`# => { ... }`), pipeline diagrams, ERB conditionals, and assertion calls. If breaking a line makes idiomatic Ruby look awkward, keep it on one line.
- **Use `Ok` / `Err`, not `Dex::Ok` / `Dex::Err`** – on each page that uses pattern matching outside of an operation class body, mention `include Dex::Match` before the first code example, then use plain `Ok` / `Err` throughout. Shorter and more readable.
- **Use `it` not `_1`** – code samples target modern Ruby. Prefer `it` (Ruby 3.4+) over `_1` in single-argument lambdas and blocks. Example: `-> { it&.strip&.downcase.presence }` not `-> { _1&.strip&.downcase.presence }`.
- **Align inline comments** – when several consecutive lines have trailing `#` comments, align all `#` signs to the same column.
- Examples should be realistic – use the established example domains (see below), not `Foo`/`Bar`
- Show the calling code, not just the class definition
- Keep examples short. If an example needs more than ~15 lines, it's probably demonstrating too many things at once
- Don't add comments explaining what's obvious from the code. Only comment when the behavior is surprising or non-obvious

### What NOT to Do

- Don't repeat information that's already on another page – link to it instead
- Don't document internal implementation details (method names starting with `_`, internal modules)
- Don't add "Note:" or "Important:" callouts for things that are just normal behavior
- Don't use VitePress info/tip/warning boxes unless it's genuinely a warning (something that could break or surprise)

## Naming Conventions

All code examples follow a `Model::Action` naming pattern where the model is the top-level namespace:

- **Operations** use the imperative mood (a command): `Order::Place`, `Leave::Approve`
- **Events** use the past participle (a fact): `Order::Placed`, `Leave::Approved`
- **Forms** use a `Form` suffix: `Order::Form`, `Leave::RequestForm`
- **Queries** use a `Query` suffix: `Order::Query`, `Employee::Query`

This works naturally with Zeitwerk in Rails apps. If `Order` is an ActiveRecord model defined in `app/models/order.rb`, nesting `Order::Place` in `app/operations/order/place.rb` is perfectly fine – Zeitwerk loads `Order` first, sees it's a class, and defines `Place` under it.

The grammatical distinction between operations and events is intentional – you can tell at a glance whether something is a command (`Order::Place`) or a notification (`Order::Placed`).

## Example Domains

Documentation uses exactly **two domains** for all code examples. Do not invent new domains, models, or business concepts outside these two areas. Consistency across pages creates a cohesive story and avoids forcing the reader to re-learn context on every page.

### E-commerce

Models: `Order`, `LineItem`, `Product`, `Customer`, `Shipment`

| Type | Examples |
|---|---|
| Operations | `Order::Place`, `Order::Fulfill`, `Order::Cancel`, `Order::Refund`, `Shipment::Ship` |
| Events | `Order::Placed`, `Order::Fulfilled`, `Order::Cancelled`, `Order::Refunded`, `Shipment::Shipped` |
| Forms | `Order::Form`, `Product::Form` |
| Queries | `Order::Query`, `Product::Query` |

### HR

Models: `Employee`, `Department`, `LeaveRequest`, `Position`

| Type | Examples |
|---|---|
| Operations | `Leave::Request`, `Leave::Approve`, `Leave::Reject`, `Employee::Transfer`, `Employee::Onboard` |
| Events | `Leave::Requested`, `Leave::Approved`, `Leave::Rejected`, `Employee::Transferred`, `Employee::Onboarded` |
| Forms | `Employee::Form`, `Leave::RequestForm` |
| Queries | `Employee::Query`, `LeaveRequest::Query` |

### Flexibility

These lists are a strong recommendation, not a hard constraint. When documenting a pattern that doesn't fit naturally into any of the above entities, you may introduce a new entity – as long as it belongs to one of the two domains. For example, an `Invoice::Issue` operation or a `Payroll::Query` are fine because they live within e-commerce and HR respectively. What you must avoid is reaching for unrelated domains (blog posts, todo items, chat messages, etc.).
