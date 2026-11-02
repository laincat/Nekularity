# Interface direction: Liquid Glass and information architecture

[中文](DESIGN.md)

This records the design reasoning, the violations that exist today, and the order to fix them. It is not a style guide: it says the few things this app holds to, and why.

## 1. Liquid Glass belongs to the navigation layer only

Apple's wording is that glass is for "the navigation layer that floats above the content". So:

| Glass | Not glass |
| --- | --- |
| The floating bar and the search orb | Comic cards, chapter lists, body text |
| Toolbar buttons, capsule controls | Every tile of a poster grid |
| The container of a sheet, menu or panel | A whole page background |

One question decides it: **does it carry content, or does it carry an action**. Content stays solid; actions float.

Two prohibitions: never stack two pieces of glass (they refract each other and neither reads), and never cover a screen with glass (body text loses the contrast it needs).

## 2. What the app actually looked like

The deployment target is iOS 26, so `glassEffect` needs no availability check — and the interface used it **nowhere**. Everything was `.ultraThinMaterial`: the iOS 15 blur that scatters light instead of concentrating it.

The violations, concretely:

| Where | Problem |
| --- | --- |
| `.glassCard` on home cards | Glass in the content layer |
| The capsule badge on poster tiles | Same, and stacked on the card's glass |
| The floating bar and the search orb | Two separate materials with a seam between them |

## 3. Order of migration

1. **Give the design system a rule**: one `glassControl` for floating controls, with a note saying why content does not get it.
2. **Make the floating bar one glass container**: the strip and the orb share a `GlassEffectContainer` and read as one material.
3. **Take the material out of the capsule controls**: an unfilled pill becomes glass, a filled one becomes the accent colour — colour carries the action, not material.
4. **Return the content layer to solid**: cards, badges and list rows go back to a plain surface with shadow and corner radius.
5. **Check contrast screen by screen**: 4.5:1 for body text, 3:1 for controls, once each in light, dark and against a colourful wallpaper.

The first two are done. Doing the design system first is deliberate: without a single entry point, "glass" grows back into the content layer by copy and paste.

## 4. Words that do not belong in the interface

The interface handed the implementation model to the user: 组件, 模块, 插件, 布局, 模板 (component, module, plugin, layout, template). Those describe how the code is organised, not what a person came to do.

The rule: **name it for the user's purpose, not for our structure**.

| Today | Should be |
| --- | --- |
| 模块 (modules) | List the content itself: reading, watching, favourites, downloads |
| 插件 (plugins) | Sources and providers — nouns a person can hold onto |
| 模板 / 布局 (templates, layout) | Home cards, and their order |
| 组件 (components) | A block of the home page, called by its own title |

This one is not done: the five words need to be located on the screens that show them first, so the fix lands where the user saw them.

## 5. Appearance has to be installable

The original intent was that appearance is content you can install, not a fixed palette. Two themes did ship — Miuix and Miuix dark — and nobody used them, so they are gone: the only built-in left is follow-the-system, and every other theme is installed.

Where it should get to:

| Ability | Note |
| --- | --- |
| A theme is data | Exists: one JSON with accent, background, radius, light or dark |
| Install from a link | To do: paste a `.json` URL, the same habit as installing a source |
| A theme list | To do: a few themes that are actually worth using, with complete palettes rather than a different accent |
| Subscription updates | To do: a theme with a `url` can be checked for updates, reusing the batch update |

The judgement behind it: a theme is **content**, not a plugin. It has no behaviour, only data, so the install path should be "take a file" — no package, no execution environment.

## 6. Motion: few, short, and switchable

https://liquidglassdesign.com/ is a gallery of liquid-glass interface and motion **work**; it has no parameters or code to copy. The authority remains Apple's HIG and SwiftUI's own animation APIs. What this app takes from either is short enough to list.

| Rule | Why |
| --- | --- |
| Animate transforms and opacity only | Animating blur radius, shadow radius or geometry repaints the layer; scrolling drops frames |
| 0.2–0.35 s, and `.snappy` for springs | Longer reads as sluggish, shorter is not seen |
| Move with one geometry transition, not two cross-fades | Two layers animating at each other look jittery and cost twice as much |
| Looping animation only for "this can be dragged" | A permanent loop is the most expensive thing on screen and the most distracting |
| Honour Reduce Motion | It stops the wobble and places the selected pill without a sliding transition |
| No per-row entrance animation in long lists | Dozens of animations in one frame is what a slow launch is made of |
| Motion never carries information | With animation off, every action still reads |

In place today: the selection pill moves with one `matchedGeometryEffect` (0.28 s, `.snappy`), and the arranging wobble obeys Reduce Motion.

## 7. Wide and folding devices

A device like the iPhone Duo is close to tablet width when opened: two columns leave the screen looking empty and stretch each card too tall. So:

| Width | Columns |
| --- | --- |
| Compact (phone portrait) | 2 |
| Regular (unfolded, iPad portrait) | 3 |
| Wider (iPad landscape, split view) | 4 |

The test is available width, not device model: folding, split view and Stage Manager all change width, and a model name does not. A card's 小 and 中 follow from it — small is one column, medium is two.

