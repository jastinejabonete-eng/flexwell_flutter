---
target: all app screens
total_score: 29
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 1
target_identity: "file:C:\\Users\\Janelyn\\Downloads\\Flutter\\Flexwell\\flexwell_flutter\\lib\\main_navigation_screen.dart"
target_fingerprint: "sha256:b9d20b9f0cf593bbcf7b9065eeb8cac83ccccc8443cd6741be8eb9be76bcd7bb"
target_path: "C:\\Users\\Janelyn\\Downloads\\Flutter\\Flexwell\\flexwell_flutter\\lib\\main_navigation_screen.dart"
timestamp: 2026-10-18T13-09-04Z
slug: lib-main-navigation-screen-dart
---
# UI Review — All App Screens

**Scope and evidence:** Reviewed the routed app shell and all primary screens: Dashboard, Tutorials, Achievements, User manual, Settings, camera setup, live camera, session summary, and Terms & Conditions. Inspected screenshots from an Android 17 emulator (1080 × 2400) in dark appearance and Settings in light appearance, then cross-checked the screen source. Landscape, tablet, iOS, and enlarged system text were not captured. Evaluation only; no source changes were made.

## Design specificity verdict

FlexWell has a recognizable training identity: deep slate surfaces, electric volt accents, exercise-specific camera directions, and a direct scan action. The UI reads as a fitness coach rather than a generic admin dashboard. Material 3 navigation and controls are used, and the onboarding/manual content supports first-time users. The main cohesion risks are system-bar contrast in light mode and unnecessary reserved space across the routed screens.

## Heuristic scores

| # | Heuristic | Score | Evidence |
|---|---|---:|---|
| 1 | Visibility of system status | 2/4 | Clear camera guidance and navigation state, but Android status icons become white on the pale light-theme status area; live scan has no visible rep/hold progress. |
| 2 | Match between system and real world | 3/4 | Exercise names, camera-view guidance, and plain-language form tips map well to the workout task. |
| 3 | User control and freedom | 3/4 | Tab navigation, tutorial collapse, camera cancel/back, and scan exit are available; no major trap observed. |
| 4 | Consistency and standards | 2/4 | Shared palette and Material 3 shell are coherent, but the light system-bar appearance and extra body inset diverge from the otherwise polished shell. |
| 5 | Error prevention | 3/4 | Camera setup guidance states body framing and view direction before permission/camera entry. |
| 6 | Recognition rather than recall | 3/4 | Navigation labels, scan CTAs, search, filters, and the manual make actions visible; some filters are offscreen in the horizontal chip row. |
| 7 | Flexibility and efficiency | 3/4 | Search/filter and alternate tutorial-to-scan path are useful; the catalog is small and has no favorites/recent shortcuts. |
| 8 | Aesthetic and minimalist design | 3/4 | Strong exercise imagery and clear visual hierarchy; extra bottom whitespace weakens the compact screen layouts. |
| 9 | Error recognition and recovery | 3/4 | Camera permission/error states offer retry or Settings; a no-data session is still presented as 0% accuracy. |
| 10 | Help and documentation | 4/4 | A dedicated manual covers quick start, camera placement, form states, streaks, and troubleshooting. |
| **Total** |  | **29/40 (72.5%) — Good** | Fix the concrete contrast and workout-feedback issues before visual polish. |

## Cognitive load

The five labeled bottom destinations are at the upper end of a comfortable mobile tab bar but remain understandable. The dashboard's search, six category chips, and exercise cards are clearly grouped; the chip strip requires horizontal discovery for later filters. Camera setup reduces uncertainty with a named view and short instructions. The manual and Terms screen are long vertical reads; the manual's sectioning helps, while Terms is inherently dense. No workflow presents more than four simultaneous decision buttons in the reviewed states.

## Emotional journey

The journey begins with a clear exercise choice, follows with reassuring camera setup, and gives immediate form guidance during the scan. The summary is celebratory and action-oriented. The emotional low point is an empty/too-short session rendered as a literal 0% score, which can feel like a form failure rather than insufficient data. The onboarding overlay is prominent but skippable.

## Strengths

- Dashboard prioritizes exercise choice and the primary “Start scan” action.
- Camera setup translates model requirements into specific human instructions (view direction and visible joints).
- Tutorials use clear, exercise-specific image cards and direct scan entry points.
- Manual is task-oriented and includes useful camera/setup troubleshooting.

## Priority issues

1. **[P1] Light-theme Android status bar is unreadable.** The emulator screenshot shows white clock/connectivity/battery icons against the pale light-theme top inset. This hides system information for the entire app in light mode. Set system-bar icon brightness consistently with the active theme and verify both themes. Location: app theme/system UI treatment, with reproduction through Settings' Dark mode toggle.
2. **[P2] Routed screens reserve redundant space above bottom navigation.** The shell subtracts `MediaQuery.padding.bottom + kBottomNavigationBarHeight` from the `IndexedStack`, even though `Scaffold.bottomNavigationBar` already occupies its own layout area. On Dashboard and Tutorials this creates a noticeable blank strip and reduces the visible scroll viewport. Remove the duplicate reservation and let each scrollable account for its actual insets. Location: `lib/main_navigation_screen.dart`, around line 128.
3. **[P2] Live scan gives no visible rep/hold progress.** The camera screen shows the skeleton/form guidance and stop/switch controls, but no current rep total or hold timer. Users cannot confirm whether the movement is being counted until the summary. Add a compact, legible live metric without competing with the pose overlay. Location: `lib/camera_screen.dart`, around lines 702 and 815.
4. **[P2] No-data sessions look like failed performance.** Ending a scan with no qualifying movement yields a large `0% Accuracy` and `0` reps. Distinguish “not enough tracked data” from a genuine zero score, and make the next step explicit. Location: `lib/summary_screen.dart`, around lines 171 and 260.

## Screen-by-screen notes

| Screen | Evaluation |
|---|---|
| Main navigation / first-run tour | Five destinations are labeled and the shell switches to a NavigationRail at wider widths. Tour steps are skippable and point to real controls. Remove the redundant bottom inset noted above. |
| Dashboard | Strong task hierarchy, exercise illustrations, searchable catalog, filters, and clear scan CTAs. The filter row is intentionally horizontal, so later categories are not visible until swiped. The streak card is secondary, which is appropriate. |
| Tutorials | Exercise-specific imagery and “Watch tutorial” affordances are easy to scan. Cards are tall, so only a few appear per viewport; the expanded Pull-Up video uses a particularly large viewport share. No critical issue observed in the captured default state. |
| Achievements | Unlocked count, latest area, and milestone grid are understandable; the first-unlock empty state gives a next action. Three columns make individual badge tiles relatively narrow, but labels remained readable in the phone capture. |
| User manual | Good quick-start sequence, camera guidance, and troubleshooting content. It is a long single scroll; section shortcuts/search would help returning users, but this is a lower-priority convenience. |
| Settings | Clear, compact grouping for theme, replay tour, and Terms. The light-theme content palette is readable; the system status bar is not. |
| Camera setup | Exercise-specific view and body-part requirements are clear, and Cancel/Continue choices are visible. |
| Live camera | Full-screen preview and high-contrast form guidance keep attention on the exercise; camera switch and stop controls have tooltips and large tap areas. Add live rep/hold progress as noted above. |
| Session summary | Strong headline score, useful exercise metric, and prominent retry/dashboard actions. Handle insufficient data separately from an actual 0% score. |
| Terms & Conditions | Native scrolling and readable section headings are present. The consent checkbox plus Accept/Decline actions are explicit; content length is unavoidable but remains a dense reading task. |

## Persona red flags

- **Jordan, first-time exerciser:** The manual and camera setup are strong guides. On Dashboard, the horizontally scrollable category row does not reveal all filters at once, so Jordan may not realize more categories exist.
- **Sam, screen-reader/low-vision user:** Camera controls expose tooltips and the tab bar has labels. In light mode, the status-bar icons have insufficient contrast; verify semantics and dynamic text across the full app, not just Dashboard.
- **Casey, distracted mobile user:** Bottom navigation and cancel/back affordances are easy to reach. The live scan's absent rep/hold count makes it harder to resume confidence after looking away.

## Minor observations

- The manual could add in-page section jumps for repeat visits.
- Tutorial banners occupy substantial vertical space; consider a tighter list/card density only if faster catalog scanning is a product goal.
- Verify tablet, landscape, and large-text layouts on target hardware; those states were not captured in this pass.

## Recommended order

1. Fix the light-theme Android system-bar contrast.
2. Remove the redundant bottom padding in the shared navigation shell.
3. Add live rep/hold progress, then distinguish insufficient-data summaries.
4. Re-check light/dark, large text, landscape, and tablet layouts; finish with a focused polish pass.
