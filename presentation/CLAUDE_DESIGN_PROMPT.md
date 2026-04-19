# Prompt for Claude Design

> Upload `CUREBAY_PITCH_BRIEF.md` first, then paste the block below as the chat message.

---

Build a **12-slide pitch deck** for an app called **CureBay** — an offline multimodal AI triage assistant for India's 1.05 M ASHA (rural community health) workers. The full content, stats, and slide-by-slide narrative are in the attached `CUREBAY_PITCH_BRIEF.md`. Use it as the single source of truth — don't rewrite the numbers, disease counts, or feature lists; they're load-bearing.

**Hard design rules — follow all of them:**

1. **Brand palette (healthcare-grade, NOT startup-purple):** Primary teal `#0FB5AE`, deep teal `#087C78`, ink `#0F1F2C`, mist background `#F4FAFA`, pulse green `#3DD598`, alert amber `#F5A524`, critical red `#E5484D`. Use the hero gradient `#0FB5AE → #087C78` at 135° only on the cover and closing slide.
2. **Typography:** Inter or Manrope. Display weight 700, tight tracking (-0.02em). Body 400/500, 1.6 line-height. Numeric stats use tabular figures at weight 600.
3. **Layout:** 16:9. 64 px outer margin. One hero element per slide. White space is mandatory — if a slide feels crowded, cut content, don't shrink type.
4. **Shadows:** soft, tinted (`0 4px 24px rgba(15, 181, 174, 0.08)`). No hard drop shadows.
5. **Corners:** 16 px on cards, 12 px on chips, 24 px on hero elements.
6. **Icons:** Lucide/Phosphor-style, 1.5–2 px stroke, outlined, monochrome teal unless indicating status.
7. **No stock photos.** Only flat 2-color line illustrations (teal + pulse-green accent). No 3D, no photorealism, no clip art.
8. **Logo — search the web for the real CureBay mark first.** Before you design anything, run a web search for **"CureBay logo"** (try `curebay.com`, their LinkedIn company page, and Google Images). Pull the highest-resolution official wordmark or symbol you can find and use *that* as the CureBay logo across the deck. Place it in the bottom-left of every slide except the cover, at 24 px from the edges, with height ~32 px. If — and only if — you cannot find an official asset after a genuine search, fall back to the construction spec in §1 and §4 of the attached brief (lowercase "curebay" in Inter 700, teal `#0FB5AE`, -0.02em tracking, with a 4 px `#3DD598` pulse dot above the "a"). Do not invent a new logo; either use the real one or use the documented fallback.
9. **Numbers over adjectives.** When the brief gives a stat (~55 MB, 162 diseases, 12 languages, 10 on-device models), render it as the largest element on the slide.
10. **Every slide answers one question.** Title is the question or declaration. Body is the single-sentence answer plus ≤ 5 supporting points.

**Specific slide treatments to nail:**

- **Slide 1 (Cover):** Full-bleed teal gradient. Big wordmark centered. Subtitle in white at 60% opacity. Team names + GitHub URL in a thin 14 px footer.
- **Slide 2 (Problem):** Three stat blocks across: `1.05M`, `70%`, `<15 min`. Numbers huge (~160 px), captions tiny underneath. Background: mist with a subtle 4 px dot grid at 4 % opacity.
- **Slide 3 (Market gap):** 2 × 2 positioning matrix. "CureBay" cell is filled teal with white text; other cells are mist with muted text. No hand-drawn feel — keep it crisp.
- **Slide 5 (4-stage pipeline):** Horizontal flow diagram, four rounded rectangles connected by thin arrows, each annotated with the count (642 / 295 / 162 / 11). This is the technical heart of the deck — give it space.
- **Slide 6 (10 models grid):** 2 × 5 grid of mini-cards (or 5 × 2 stacked, whichever reads better at 16:9). Each card: model icon, name, size badge in the corner. Use three color weights so the tiers read at a glance — general booster (lightest teal), 6 specialist tabular models (mid teal), 4 computer-vision models (darkest teal). The **Skin (8 clinical supergroups)** card must carry a small shield icon + a "Triage, not diagnosis" pill-shaped badge. Do not hide this caveat — it signals to medical-AI judges that we understand the safety posture.
- **Slide 7 (Scenario):** Three phone-frame mockups in a row, with a dotted timeline connecting them. Use placeholder screenshots — the designer should generate stylized app-screen mockups matching the teal palette (assessment chips on screen 1, red emergency card on screen 2, handoff PDF on screen 3).
- **Slide 10 (Big metrics):** Four numbers in a single row: `~55 MB`, `12`, `162`, `₹0`. Each on its own column with a 1 px divider. Numbers at 120–140 px.
- **Slide 12 (Team & Ask):** Three circular avatars (initials MH, DG, AB in teal-bordered circles on mist background — no face photos). GitHub URL as a prominent button-styled element.

**Do NOT:**
- Use emojis in slide titles (only in body bullets, max 1 per bullet).
- Add a "Thank you" closing slide — the Team & Ask slide IS the closing slide.
- Use purple, pink, or any non-healthcare color.
- Include the word "revolutionary" or "disrupting" anywhere.
- Let any slide have more than 5 bullet points.

**Deliverable format:** A 12-slide Claude Design artifact, 16:9, exportable as PDF. Each slide's content must match the brief exactly; only the visual composition is yours to craft.

Make this the best deck Claude Design has produced. We're entering it into the CureBay Hackathon 2026 and the team (Mridul Harsh, Dhaval Gupta, Ahan Bansal) is counting on it.
