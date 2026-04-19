# CureBay — Pitch Deck Brief

> **Upload this file to Claude Design, then paste the companion prompt (`CLAUDE_DESIGN_PROMPT.md`) into the chat.**

This document is the complete content source for a ~12-slide investor/judge-facing presentation of **CureBay**, an offline multimodal AI assistant for ASHA (rural community health) workers in India.

---

## 0. Meta

| Field | Value |
|---|---|
| **Product name** | CureBay |
| **One-liner** | Clinical-grade diagnostic reasoning for 1.1M ASHA workers — offline, in their language, on their existing phone. |
| **Hackathon** | CureBay Hackathon 2026 |
| **GitHub** | https://github.com/MridulHarsh/rural-health-ai |
| **Platform** | Android (Flutter), 6.0+, ARM64, ~50 MB APK |
| **Status** | Working prototype. Installable APK built via CI on every push to `main`. |
| **Team** | Mridul Harsh · Dhaval Gupta · Ahan Bansal |

---

## 1. Brand direction (CureBay)

Design the deck around CureBay's healthcare identity: **trustworthy, clinical, warm, accessible**. Not another generic startup-purple gradient deck.

### Palette (matches CureBay's public brand tone — verify/override if an official brand guide is available)

| Token | Hex | Use |
|---|---|---|
| **Primary / CureBay Teal** | `#0FB5AE` | Headlines, primary CTAs, accent bars |
| **Primary Dark** | `#087C78` | Deep backgrounds, titles on light |
| **Ink** | `#0F1F2C` | Body text, charts |
| **Mist** | `#F4FAFA` | Page background, card fills |
| **Pulse Green** | `#3DD598` | Positive metrics, "Normal" triage |
| **Alert Amber** | `#F5A524` | "Urgent" triage, warnings |
| **Critical Red** | `#E5484D` | Emergency / red-flag triage |
| **Muted** | `#6B7280` | Secondary text, captions |

**Gradient hero**: `#0FB5AE → #087C78` at 135°, no noise, no rainbow.

### Typography

- **Display / Headlines**: Inter or Manrope, 700 weight, tight tracking (`-0.02em`).
- **Body**: Inter 400 / 500, 1.6 line-height.
- **Numerics** (stats, percentages): Tabular figures, weight 600.

### Visual language

- **Minimal line illustrations** over photo overlays. Think Stripe-docs cleanliness with healthcare warmth.
- **Rounded corners**: 16px on cards, 12px on chips, 24px on hero elements.
- **Soft shadows** (`0 4px 24px rgba(15, 181, 174, 0.08)`), never harsh drop-shadows.
- **White space is a feature**, not a bug. Judges read 30 decks an hour; breathing room wins.
- **One hero visual per slide**, never three competing elements.

### Iconography

Use outlined, 1.5–2px stroke icons (Lucide / Phosphor style). Categories you'll need:
stethoscope · wifi-off · microphone · camera · pill · shield-check · heart-pulse · users · globe · lock · chart-line · alert-triangle.

### Logo treatment for CureBay mark

If using the wordmark: lowercase "curebay" in teal `#0FB5AE` on white, or white on teal. Maintain clear space = height of the "c". Never rotate, never gradient-fill the mark itself.

---

## 2. Slide-by-slide content

### Slide 1 — Cover

**Title:** CureBay
**Subtitle:** An offline AI triage assistant for every ASHA worker in India.
**Footer (small):** CureBay Hackathon 2026 · Mridul Harsh · Dhaval Gupta · Ahan Bansal · [github.com/MridulHarsh/rural-health-ai](https://github.com/MridulHarsh/rural-health-ai)

**Visual direction:** Full-bleed gradient (`#0FB5AE → #087C78`). Single line-art illustration of a phone with a pulse line flowing out of it. No stock photos of smiling doctors.

---

### Slide 2 — The ASHA reality

**Title:** 1,054,000 health workers. 900 million patients. 0 bars of signal.

**Body bullets (short, punchy):**
- India's 1.05 M+ ASHA workers are the first (and often only) medical touchpoint for rural families.
- They carry a phone, a notebook, and their judgment. No ultrasound. No lab. No internet in ~40% of their working hours.
- The WHO recommends ≥ 1 CHW per 1,000 people. India's ratio in the poorest districts is closer to 1:2,500.
- A missed red-flag in a newborn, a pregnant mother, or a fever cluster costs lives within hours.

**Visual:** Three stat blocks, large numbers (`1.05M` · `70%` · `<15 min`), each with a one-line caption.

---

### Slide 3 — The gap no existing app fills

**Title:** Telemedicine isn't triage. Chatbots aren't clinicians.

**Content:** A 2×2 positioning matrix.

| | Needs internet | Works offline |
|---|---|---|
| **Generic symptom checker** | Practo, WebMD, Ada | — |
| **Clinical-grade reasoning** | Doctor-in-the-loop apps | **CureBay** (you are here) |

Add a callout: *"Existing telehealth assumes a signal that half of rural India doesn't have. On-device LLMs (Gemma, MedGemma) are 300–500 MB and aren't auditable for medical decisions."*

---

### Slide 4 — Meet CureBay

**Title:** A pocket clinician that never goes offline.

**Three feature columns** (icon + one-line):

1. **🩺 Reasoning-first, not ML-first** — A curated engine of 162 diseases, 11 red-flag rules, and 295 canonical symptoms. Every decision is auditable. ML is a booster layer, gated by confidence thresholds, not the primary diagnostician.
2. **📶 100% offline after install** — Every model, every rule, every translation is on-device. ~55 MB total. Android 6.0+, ~2 GB RAM.
3. **🗣 12 Indian languages** — Text, voice (offline STT), and OCR for prescriptions. The ASHA speaks her language; the app listens.

**Visual:** Three rounded cards, each with the icon oversized in the top-left.

---

### Slide 5 — How a diagnosis happens (the secret sauce)

**Title:** The 4-stage symptom resolution chain.

**Content:** A left-to-right pipeline diagram with 4 nodes:

```
[UI chip] → [Alias resolution] → [Body-system map] → [Disease profile match]
```

With annotations:
- **642** symptom aliases (including native-script phrases)
- **295** canonical body-system symptom keys
- **162** curated disease profiles with cardinal / common / occasional weighting
- **11** red-flag rules that override everything (shock, respiratory distress, severe dehydration…)

Bottom callout: *"Cardinal elimination: a disease without a single cardinal symptom match scores zero. This is why our top-1 isn't malaria every time someone has a fever."*

---

### Slide 6 — Multimodal, multilingual, multi-model

**Title:** One app, ten on-device models, zero cloud calls.

**Content:** 2×5 grid of mini-cards showing each ML model running on-device. Group visually as three tiers: general booster / specialist tabular / computer-vision.

| Model | Type | Size | Purpose |
|---|---|---|---|
| Disease classifier | 754-class RF → TFLite | 410 KB | General boost |
| Heart disease | Binary | 18 KB | Specialist |
| Diabetes | Binary | 17 KB | Specialist |
| Kidney | 3-class | 18 KB | Specialist |
| Liver | Binary | 17 KB | Specialist |
| Stroke | Binary | 18 KB | Specialist |
| Maternal | 3-class | 18 KB | Specialist |
| Eye (cataract, DR, glaucoma) | Image | 2.6 MB | Vision |
| Lung (pneumonia, TB, COVID…) | Image | 2.6 MB | Vision |
| Malaria blood smear | Image | 2.5 MB | Vision |
| Skin (8 clinical supergroups) | Image | 4.3 MB | Triage screen |

**Footer:** Every inference runs in ≤ 200 ms on a ₹8,000 phone.

**Caveat for the skin card (do NOT skip this — it's a credibility builder):** The skin classifier outputs one of 8 clinical supergroups — *Bacterial / Fungal / Viral / Parasitic / Inflammatory / Allergic / Neoplastic / Autoimmune* — the same triage buckets a dermatologist uses. It's a **screening tool**, not a diagnostic, and is gated behind a confidence threshold so the app stays silent when uncertain. This is the correct posture for medical AI: speak up only when sure, and always defer to PHC for confirmation. Design the skin card with a small shield icon + "Triage, not diagnosis" badge so judges see we've thought about the failure modes.

---

### Slide 7 — A day with CureBay (scenario walkthrough)

**Title:** 11:32 AM. Village in Koraput. No signal.

**Three-step storyboard:**

1. **Sunita opens CureBay.** She taps five chips and speaks two more symptoms in Odia. *(screenshot placeholder: assessment screen with chips)*
2. **The engine flags a red alert.** "High fever + stiff neck + drowsiness in child under 5" triggers the meningitis red-flag rule. Screen vibrates. *(screenshot placeholder: emergency triage red card)*
3. **She taps "Send to PHC".** A pre-filled WhatsApp message with the patient summary and assessment PDF goes to the nearest Primary Health Centre — queued and auto-sent when a bar returns. *(screenshot placeholder: PDF export & handoff)*

**Caption:** *Total interaction: 47 seconds. No login. No ads. No data leaves the phone.*

---

### Slide 8 — Trust, security, and the boring stuff that matters

**Title:** A health app has to earn trust every session.

**Four-column list:**

- 🔒 **AES-256-GCM** encryption on every PII column (name, voice transcripts, notes). Keys in Android Keystore.
- 🧾 **Auditable reasoning** — every ranked condition shows the symptoms that explained the decision.
- 🧪 **Label-aware risk scoring** — we use `P(high-risk) + 0.5·P(mid-risk)` for multi-class severity, not naive argmax. (This matters: naive scoring called "low risk" cases high-risk 14% of the time.)
- 🧹 **Zero telemetry, zero ads, zero trackers.** The network permission exists only for the optional PHC handoff.

---

### Slide 9 — Beyond diagnosis

**Title:** The full ASHA toolkit — not just a symptom checker.

**Grid of 6 feature tiles:**

1. **Maternal & Child Health** — Naegele EDD, 4-visit ANC schedule, complete UIP immunization tracker.
2. **Medicine Inventory** — Pre-seeded with the WHO essential list. Expiry alerts. Stock-out prediction.
3. **Dosage Calculator** — Weight-and-age-adjusted dosing for pediatric antibiotics, anti-malarials, rehydration salts.
4. **Outbreak Detection** — 7-day cluster scan across household IDs. Flags anomalies before they become outbreaks.
5. **OCR for Prescriptions** — Scan a paper Rx; extract text with Google ML Kit (offline).
6. **Patient-Summary PDF** — One-tap export; shareable over WhatsApp, SMS, or Bluetooth print.

---

### Slide 10 — Why CureBay wins the hackathon and the market

**Title:** The metrics that matter.

**Four big-number stats in a row:**

- **~55 MB** APK (vs 350 MB for MedGemma-powered alternatives)
- **12** Indian languages, including 5 scripts most apps skip (Odia, Assamese, Gujarati, Kannada, Malayalam)
- **162** auditable disease profiles, 0 hallucinations
- **₹0** per diagnosis, forever (no API, no subscription)

**Sub-caption:** *This isn't a wrapper around a cloud API. It's a self-contained clinical workstation — 10 ML models, 162 disease profiles, 12 languages — in under 60 megabytes.*

---

### Slide 11 — Roadmap

**Title:** What's next.

**Three-column timeline:**

| Q2 2026 | Q3 2026 | Q4 2026 |
|---|---|---|
| Pilot with 500 ASHAs in Odisha + Jharkhand (partner: CureBay eClinics) | Federated learning on anonymized assessments — models improve without data leaving phones | Launch iOS build + integration with India Stack (ABHA, UHI) |
| Dashboard for PHC officers: live outbreak heatmap | Expand disease library to 250 profiles; upgrade skin classifier to EfficientNet + 224×224 to raise it above the ship gate | Clinical validation study, peer-reviewed publication |

---

### Slide 12 — Team & Ask

**Title:** Built in 72 hours. Built for a billion people.

**Team (three avatars / initials circles):**

- **Mridul Harsh** — Product & ML. Led clinical engine, label-aware scoring, symptom-resolution graph.
- **Dhaval Gupta** — Android & Systems. Flutter architecture, offline inference pipeline, SQLite + encryption.
- **Ahan Bansal** — Clinical data & UX. Curated 162 disease profiles with ICMR references, 642-alias dictionary, 12 translations.

**CTA block:**

> **See the code, install the APK, or partner with us.**
> 🔗 github.com/MridulHarsh/rural-health-ai
> 📦 Download signed APK from the GitHub Actions artifact on the latest commit.
> ✉️ Open an issue or PR — we're shipping weekly.

**Footer:** *Thank you, CureBay — for the hackathon, and for the mission of accessible rural healthcare.*

---

## 3. Tone & do-not-do list

### Voice
Confident, clinical, warm. Short sentences. Active verbs. Numbers over adjectives ("50 MB" beats "tiny"). Never use "revolutionary," "disrupting," "AI-powered" as a feature.

### Visual do-not-do
- ❌ Purple/pink gradients (this is healthcare, not crypto).
- ❌ Stock-photo doctors with stethoscopes.
- ❌ Bar charts where a single big number would do.
- ❌ Emojis in titles (sparing use in body bullets only — max 1 per bullet).
- ❌ More than 5 bullet points on any slide.
- ❌ Text smaller than 18px on body slides, 14px on footers.
- ❌ "Thank you" as the final slide. The final slide is Team + Ask.

### Judge-attention hacks
- First 3 slides must survive a 10-second scan. If a judge flips past, the deck has failed.
- Every slide answers a single question. Title = question or declaration. Body = answer.
- The GitHub URL appears on the cover AND the closing slide (redundancy is fine; judges scroll back).

---

## 4. Assets the designer may need to fabricate

If CureBay's official brand assets are not available at generation time, substitute cleanly:

- **Logo:** Render "**curebay**" (lowercase) in Inter 700, color `#0FB5AE`, letter-spacing `-0.02em`, with a 4px circular dot above the "a" in `#3DD598` to represent a pulse.
- **Pattern background:** Subtle dot grid (4px dots, 32px spacing) at 4% opacity of `#0FB5AE` on `#F4FAFA`.
- **Illustrations:** Flat, 2-color line art (teal + green-pulse), no 3D, no gradients inside illustrations.

---

*End of brief.*
