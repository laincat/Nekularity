# Dynamic Liquid Glass and cross-platform UI goals

[简体中文](LIQUID-GLASS.md) | English

On 2026-11-04, the user specified iOS-first and a shared desktop direction: “iOS 27-level” dynamic Liquid Glass, animated icons, large image/comic/video presentation, tags and extensive customization. This describes experience quality, not an automatic minimum-OS increase from iOS26 to27. Foundations remain first. Initial material work preserves existing layout, spacing, radii, fonts, icon identities and copy; layout reconstruction is a separate phase.

## References and verified capabilities

- The user supplied [Kubai087](https://x.com/Kubai087) and a complete material recipe. Browser access failed with `APP_BOUND_ENCRYPTION_UNSUPPORTED` while using copied sign-in state, so other posts were not read. This document uses the supplied text without claiming a full profile review.
- Apple's official [custom-view Liquid Glass guidance](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views) covers `glassEffect`, `.interactive()`, `GlassEffectContainer`, stable effect IDs and morphing transitions. Availability metadata starts at iOS26. Numerous independent effect containers can reduce performance.
- Pinned MIT MyGo0.7.3 already provides [plugins/glass](https://github.com/egoist/mygo/tree/v0.7.3/plugins/glass): `Glass{Style,Tint,Interactive,Clarity}`, `ScrollEdge` and progressive backdrop blur. Its renderers draw native UI without JS or CSS.
- Window-level `VibrancyGlass/Clear` uses system Liquid Glass on macOS26+ and maps to Acrylic on Windows11. This differs from `Material(glass.Glass{})` over content within a window; the two results must not be conflated.

## Surface inventory and initial treatment

| Existing surface/location | Initial material direction | Refraction/dispersion and preserved behavior |
|---|---|---|
| iOS `VideoPlayerView.transport` control capsule | System glass over video; theme/dense material when background cannot be read | System rim without SVG layering; preserve position, dimensions, typography and copy |
| iOS `DesignSystem.PosterTile` image caption | Native material adapting to an image, prioritizing readability | No custom lens/RGB split on small captions; leave cover pixels unchanged |
| iOS `DesignSystem.Pill` floating actions | Retain existing glassEffect and evaluate system interaction | Preserve icon identity and geometry; solid primary actions retain semantic color |
| iOS `PromptCenter.PromptPresenter` toast/loading overlays | Shared denser material over busy backgrounds | No additional custom lens on transient/moving panels |
| iOS `RootView`/`ReaderView` system navigation and menus | System materials and accessibility behavior | No second glass layer; preserve original comic-page pixels |
| iOS `GlassCard` and discovery/library/profile content cards | Currently solid; retain their surface over plain backgrounds | Choose material semantically if later placed over wallpaper/images; avoid blanket gray surfaces |
| Desktop `internal/ui/app.go` toolbars/panels | Retain plain-background styling; prefer MyGo Glass over native images | Reuse upstream refraction instead of porting CSS optics |
| Desktop reader `internal/reader/assets/reader.html` sticky `#bar` | Shared CSS material tokens and appearance settings | CSS-only by default; small/composited surfaces skip SVG lenses; page images have no filter |
| Desktop player `internal/player/assets/player.html` `#bar` and native video controls | The current bar is below video on a plain background; retain it initially | Replacing browser playback controls is a new component requiring a separate proposal and confirmation |
| Source code, long text, errors and settings forms | Stable high-contrast content surfaces | Preserve focus, disabled states and semantic error red |

No new custom controls are part of the initial pass. If an effect requires replacing player controls or adding a component, prepare a concrete proposal and seek user confirmation first. System effect containers compose existing views without changing layout parameters.

## Shared material tokens and persistence

Material belongs in the theme layer; components select semantic roles instead of owning separate opacity/blur constants. Current iOS `Theme` only supplies accent/background/surface/radius/dark; `RootView` applies preferredColorScheme and `DesignSystem` maps colors. New fields must decode old themes. Desktop MyGo themes and reader CSS tokens need separate adapters; they are not already unified.

| Semantic configuration | Constraint and purpose |
|---|---|
| `material.role` | navigation, mediaOverlay, notification, content; content is not glass by default |
| `light.tintScale` / `dark.tintScale` | Each0…1.5, default1, persisted per theme ID; user overrides separate from downloaded theme files |
| `glass.style` | regular/clear; video and unknown backgrounds prioritize contrast over transparency |
| `glass.clarity` | MyGo maps0…1; SwiftUI has no equivalent public dial, so do not promise identical blur values |
| `ink.primary/secondary` | Fixed appearance-specific color steps; increase material density before weakening text opacity |
| `motion.interaction` | Press feedback, state replacement, expansion/morphing; static or simplified under Reduce Motion |
| `fallback.solid` | Reduced transparency and forced/high-contrast colors override decorative theme settings |

The supplied alpha, 2px blur, saturation, rim and brightness values are starting points for Web experiments, not equivalent SwiftUI or MyGo shader parameters. Persistence and animated theme switching for both tint settings need execution evidence; settings UI is not implemented yet.

## Background adaptation, readability and animated icons

Readable local images can use a5×3 sample grid, discard two brightest/darkest samples, share decisions across a row and apply0.5±0.05 hysteresis. Clamp density to0…1. Cache samples and invalidate on image/theme/position changes rather than reading video every frame on the main thread. Live video, cross-origin and unreadable backgrounds use theme colors and denser surfaces.

The recipe's0.299/0.587/0.114 luminance is an appearance heuristic, not WCAG linear relative luminance. Actual composited normal text should meet4.5:1, and large text or required controls/icons3:1. Check darkest/busiest allowed backgrounds, retaining focus rings, disabled states and error colors. System/user reduced transparency, increased contrast and reduced motion take priority.

Animated icons communicate state: play/pause transitions, one-shot favorite feedback and real loading. Preserve identity and accessible names; avoid meaningless loops. Large media stays clear while glass primarily carries floating controls. The later layout phase adds cover proportions/information density, module visibility/order/size, content tags/groups and navigation-tab configuration, with theme tokens, layout presets and business data kept separate.

## Platform boundaries and implementation order

1. Continue foundational work; complete the material inventory and upstream selection without another visual matrix for the old UI.
2. Pilot materials on existing video-control capsules, image captions and reader bars, preserving geometry and testing SwiftUI, MyGo and WebView separately.
3. Use system containers, interaction and morphing on iOS and existing MyGo Glass on desktop. MyGo captures content painted into its scene; cross-compositor sampling of embedded WebViews/video requires separate verification.
4. Start Web surfaces with CSS-only glass. Enable SVG displacement/RGB split only on stable, sufficiently large eligible surfaces after actual rendering checks. CSS.supports parsing alone does not prove correct output. Handle unique filter IDs, decoded resources, caching and size changes.
5. Validate worst-case light/dark backgrounds, reduced transparency/motion, scrolling/video frame pacing and energy before the full large-media/customizable-layout rewrite.

## Evidence from this round

Official Apple documentation and availability metadata are saved in `E:/Temp/nk-liquid-glass/`. On Windows, MyGo0.7.3 `go test -count=1 -v ./plugins/glass` passed, including CPU rendering and Direct3D11 offscreen comparisons; log `mygo-glass-tests.log`. This is evidence for the upstream material, not current product UI, Mac/iOS execution, video composition or performance acceptance. No product SwiftUI layout or theme fields changed this round.
