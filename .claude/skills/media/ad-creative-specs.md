---
name: ad-creative-specs
description: Massimo's platform specs and creative direction for ad images and social graphics
version: 1.0.0
updated: 2026-04-05
updated_by: ray
---

## When to Use
Before creating any ad creative or social graphic.

## Platform Specs

| Platform | Size (px) | Aspect Ratio | File | Max Size |
|----------|-----------|-------------|------|----------|
| Facebook/IG Feed | 1080×1080 | 1:1 | JPG/PNG | 30MB |
| Facebook/IG Story | 1080×1920 | 9:16 | JPG/PNG | 30MB |
| LinkedIn Feed | 1200×627 | 1.91:1 | JPG/PNG | 5MB |
| Reddit | 1200×628 | ~1.91:1 | JPG/PNG | 20MB |
| Twitter/X | 1200×675 | 16:9 | JPG/PNG | 5MB |

## Creative Direction

### Visual Hierarchy
1. **Pain point** or **outcome** — the main message (large, bold)
2. **Product screenshot** or **visual proof** — what makes it real
3. **Brand mark** — subtle, bottom corner
4. **CTA** — only on Story formats (others use caption)

### What Works
- Real product UI (cropped and framed cleanly, not full-page dumps)
- Before/after comparisons
- Numbers and stats overlaid on clean backgrounds
- Human faces in context (construction workers, contractors, project managers)
- High contrast — must be readable as a 200px thumbnail

### What Doesn't Work
- Generic stock photos (people in suits, handshakes)
- Too much text on the image (Facebook penalizes this)
- Corporate blue + white only — add brand accent color
- Busy backgrounds behind text

## Generation Prompt Pattern

```
Professional product marketing ad for [platform].
Product: [product name + one-line description]
Visual: [specific scene — e.g., "construction site with tablet showing dashboard UI"]
Headline overlay: "[exact headline text]"
Style: clean, modern, [brand color: e.g., "navy and orange accent"]
No stock photo feel. High contrast. Mobile-readable.
Size: [WxH]
```

## Minimum Deliverables Per Request
- 3 variations (A/B/C) — different headlines or layouts
- Labeled clearly: `[platform]-[date]-A.png`, etc.
- Saved to: `content/assets/ads/[platform]/`

## Known Winning Patterns
*(Updated as campaign data comes in)*

| Pattern | Platform | Result |
|---------|----------|--------|
| (first entry after first live campaign) | | |
