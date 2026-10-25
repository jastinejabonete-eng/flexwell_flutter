---
target: lib/dashboard_screen.dart
total_score: 26
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 0
target_identity: "file:C:\\Users\\Janelyn\\Downloads\\Flutter\\Flexwell\\flexwell_flutter\\lib\\dashboard_screen.dart"
target_fingerprint: "sha256:96e1f71491050349b756907c82c23f4bd393568167bd8a3cf87c732bad573bab"
target_path: "C:\\Users\\Janelyn\\Downloads\\Flutter\\Flexwell\\flexwell_flutter\\lib\\dashboard_screen.dart"
timestamp: 2026-10-18T11-53-13Z
slug: lib-dashboard-screen-dart
---
Method: design review only (detector not applicable, native platform)

# Dashboard UI critique

## Design Health Score

| # | Heuristic | Score | Key Issue |
|---|-----------|-------|-----------|
| 1 | Visibility of System Status | 2 | The page explains streak loading/errors, but the main scan action has no explicit CTA on each exercise. |
| 2 | Match System / Real World | 3 | Exercise names, body areas, reps/time, and the camera setup dialog map well to gym tasks. |
| 3 | User Control and Freedom | 3 | Search/filter can be cleared and the setup dialog offers a cancel path. |
| 4 | Consistency and Standards | 2 | Exercise tile accent colors and category chips use several unrelated colors. |
| 5 | Error Prevention | 3 | Setup confirmation and filters reduce mistakes; active scan remains gated by the setup dialog. |
| 6 | Recognition Rather Than Recall | 3 | Exercise type and body area appear on each tile, but the scan affordance is implied by tapping the whole tile. |
| 7 | Flexibility and Efficiency | 2 | Search and filters help, but there is no recent/favorite shortcut for repeat workouts. |
| 8 | Aesthetic and Minimalist Design | 2 | The date/time header and multi-part streak card compete with the exercise chooser. |
| 9 | Error Recovery | 3 | Empty search has a clear reset; cloud history failures have a retry path. |
| 10 | Help and Documentation | 3 | Camera setup is contextual and the app includes a manual/tutorial path. |
| **Total** | | **26/40** | **Good foundation; simplify the hierarchy around starting a scan.** |

## Design Specificity Verdict

**LLM assessment:** The screen is recognizably about exercise tracking because of the exercise-specific tiles, rep/time labels, body-area labels, and camera setup flow. The hierarchy and component language are less distinctive: the streak card is a generic stats panel, while tile tint colors, chip colors, and the Volt brand accent do not form one clear visual system. The best product-specific opportunity is to make the exercise selection feel like starting a coached scan, not selecting a generic catalog card.

**Deterministic scan:** not applicable (native platform). No live device/browser capture was available, so findings are from source review rather than rendered visual evidence.

## Overall Impression

The structure is functional and scannable, but the dashboard leads with progress reporting before the core action. Make “start a scan” visually primary, and let the streak support that task rather than dominate it.

## What's Working

- Exercise tiles show the movement, body area, and reps-versus-time distinction in one place.
- Search, horizontal filters, and a useful empty state support finding the right exercise.
- The setup guide appears before camera navigation, helping users choose the expected view and know what to keep in frame.

## Priority Issues

### [P2] The primary action is below the progress summary
**Why it matters:** A returning user opens the dashboard to train, yet must first scan a sizable streak card before reaching exercise selection. This adds friction to the most frequent task.
**Fix:** Reduce the streak panel to a compact summary and place a clear “Choose an exercise” heading and scan-ready state at the top. Keep the fuller weekly/milestone detail secondary or expandable.
**Suggested command:** `/impeccable layout`

### [P2] Exercise tiles do not visibly signal “tap to scan”
**Why it matters:** The whole tile is tappable but it looks like a static information card; first-time users may miss the action or not know what happens next.
**Fix:** Add a consistent, compact action cue such as “Start scan” or a trailing camera icon with a visible label. Preserve the current setup confirmation after selection.
**Suggested command:** `/impeccable clarify`

### [P2] The streak card has too many competing details
**Why it matters:** Current streak, best streak, week squares, next milestone, days-to-go, and a progress bar all compete inside one block. The user has to parse multiple progress representations before acting.
**Fix:** Lead with current streak and a short status sentence. Keep either the week strip or milestone progress as the supporting visual, not both at equal prominence.
**Suggested command:** `/impeccable distill`

### [P3] Accent color changes by exercise without a clear semantic rule
**Why it matters:** Cyan, purple, orange, blue category tags, and the neon/lime brand accent create multiple competing signals. Color begins to imply meaning without a consistent legend.
**Fix:** Use the brand accent for primary actions and selected states; keep category/type labels in a restrained, consistent palette. If exercise colors remain, define them as intentional categories and use them consistently.
**Suggested command:** `/impeccable colorize`

### [P3] The header spends space on a live clock
**Why it matters:** The date and minute-updating time are not needed to choose an exercise, but occupy the dashboard’s top identity area and cause periodic rebuilds.
**Fix:** Keep the date only if it supports workout context, or replace it with a brief “Ready to train?” heading and move date/time to a less prominent location.
**Suggested command:** `/impeccable distill`

## Persona Red Flags

- **Jordan (First-Timer):** The exercise tiles explain what each movement is, but not that tapping starts a camera scan after setup. Add an action label and a concise “camera setup first” cue.
- **Casey (Distracted Mobile User):** The large streak card pushes exercise selection down the page. Prioritize a one-tap route to the exercise chooser and keep secondary progress content compact.
- **Sam (Accessibility-Dependent User):** Tappable cards rely on affordance from a whole-card ink response rather than an explicit scan control. A labeled, comfortably sized action improves discoverability and screen-reader clarity.

## Minor Observations

- The search hint says “muscle groups”; matching comes from exercise title/subtitle, which currently contain those muscle labels. If the catalog expands, use structured searchable tags rather than relying on display copy.
- The 6-item catalog is small enough that the screen can keep all tiles discoverable without requiring search; filters should remain secondary, not become the primary navigation burden.

## Questions to Consider

- Should the first screenful prioritize starting a workout or celebrating workout history?
- Would a compact streak summary plus a visible “Start scan” action better serve returning users?

Questions skipped: This was an advice-only review; no implementation choice is required yet.
