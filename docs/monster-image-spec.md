# LifeMedals Monster Image Specification

## Goal

A user should recognize a monster's task category from its silhouette and core objects without reading a label. A medal family groups species but never replaces the task's concrete meaning. Basketball and swimming both belong to Athlete, yet must remain different species.

## 1. Taxonomy defines the species

- `monster_tag` describes a reusable activity, not one user's task.
- Explicit sports retain their sport: use `sports.basketball` or `sports.swimming`, never the generic `fitness.workout`.
- Reserve `fitness.workout` for gym sessions, strength training, or unspecified exercise.
- Apply the same specificity elsewhere: use `chores.take_out_trash`, not `chores.household`.
- Tags contain lowercase English taxonomy only. They must not include people, locations, brands, files, dates, or other one-off details.
- Species IDs use `species-[medaltype]-[description]`. Prefer one simple word for the description; if two are necessary, concatenate them after the final hyphen, as in `species-career-jobsearch`.

## 2. Choose one or two strong visual anchors

Every concept response must include `signature_objects` with one or two entries. Each entry is a concrete object or physical material recognizable without explanatory text. Emotions, abstract concepts, medal icons, and generic "tools" do not qualify.

| Species ID | Canonical tag | Suitable anchors |
| --- | --- | --- |
| `species-athlete-basketball` | `sports.basketball` | basketball, hoop |
| `species-athlete-swimming` | `sports.swimming` | water, life ring |
| `species-athlete-baseball` | `sports.baseball` | baseball, bat |
| `species-athlete-tennis` | `sports.tennis` | tennis ball, racket |
| `species-life-trash` | `chores.take_out_trash` | trash can, tied garbage bag |

These examples show the required strength of association. The concept model must derive anchors from the actual canonical tag and must not reuse unrelated example objects.

## 3. Integrate every anchor into the monster

- `task_features` must explain how each signature object becomes body structure, primary silhouette, clothing, held equipment, or worn equipment.
- Every anchor must remain legible in one 48-by-48 logical-pixel sprite.
- Background-only props, scene decoration, implied actions, text, logos, or abstract symbols do not count as integration.
- `image_description` must explicitly repeat each anchor and how it is integrated.
- Do not create a complicated scene to fit more anchors. The output remains one centered monster sprite.

## 4. Preserve species DNA through nine levels

- Level 1 uses the smallest pixel mass and only the strongest one or two anchors.
- Levels 2 through 9 preserve the same face, body structure, palette, pixel scale, and every signature object.
- Each level adds one small, pixel-readable evolution. Unrelated props must not change the species meaning.
- Level N should be produced as an edit of the ready Level N-1 image whenever possible.

## 5. Style, safety, and privacy

- Use a low-resolution grotesque pixel mascot: compact, asymmetric, awkward, and family-friendly.
- Use hard square pixels, stepped contours, and three or four muted dirty-gray colors.
- Do not use antialiasing, gradients, blur, smooth 3D rendering, or dense high-resolution detail.
- Do not include text, numbers, logos, trademarks, copyrighted characters, gore, exposed organs, nudity, or sexual content.
- Concept and image services receive only canonical tag, medal family, level, stable visual DNA, and version metadata. They never receive a user's title, description, evidence, or identity.

## 6. Versions and immutability

- `MONSTER_CONCEPT_PROMPT_VERSION` versions concept rules.
- `MONSTER_PROMPT_VERSION` versions image composition rules.
- `MONSTER_STYLE_VERSION` selects the immutable variant family.
- A regeneration that changes art must increment the style version and write a new R2 object. Existing historical objects must never be overwritten.

The current staging configuration uses `monster-concept-v3`, `monster-image-v4`, and `grotesque-pixel-v2` with `gpt-image-2`.
