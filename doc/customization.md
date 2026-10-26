# Make it look like your app

*You need this if* the default dark oval and white text don't match your
design.

## Theme and text

No custom widgets needed: `LivenessTheme` sets colors, borders, text
styles, the target's size, position and shape (oval, circle or rounded
rectangle — this is also where the face must be), the close button, and
**every piece of text** through `LivenessStrings`:

```dart
LivenessDetector(
  theme: LivenessTheme(
    ovalShape: TargetShape.circle,
    progressColor: Colors.teal,
    strings: LivenessStrings(
      actionInstructions: {LivenessAction.blink: 'Clignez des yeux'},
      stepCounter: (current, total) => 'Étape $current sur $total',
    ),
  ),
  ...
)
```

Text maps (`actionInstructions`, `guidanceMessages`, `failureMessages`)
are merged over the English defaults, so you can override just a few
entries. Both `LivenessTheme` and `LivenessStrings` have `copyWith`. For
layout: `instructionAlignment`, `closeButtonBuilder`, and theme fields
like `closeIconColor` and `resultHoldDuration`.

## Your own widgets

`overlayBuilder` replaces the dimmed overlay and `instructionBuilder` the
instruction area. Both receive the live `LivenessSessionState` and
rebuild on every change. Useful fields:

| Field | What it is |
|---|---|
| `phase` | searching, centering, performing an action, completed, failed… |
| `currentAction`, `actionPlan` | the action now, and every action in this session's order (known from the first frame) |
| `actionProgress`, `overallProgress` | 0–1 for the current action and for the whole session |
| `remaining`, `actionTimeout`, `sessionRemaining` | countdowns |
| `faceInPosition`, `guidance` | whether the face is in place, and what's wrong if not (`tooFar`, `lowLight`…) |
| `failureReason` | why it failed |

**If you draw your own window, tell detection where it is** with
`targetRegion` (normalized to the widget, e.g.
`Rect.fromLTWH(0.15, 0.2, 0.7, 0.5)`); otherwise the theme's oval still
decides where the face must be. Working code: the
[custom UI recipe](https://github.com/maykhid/liveness_flutter/blob/main/example/lib/recipes/custom_ui.dart)
and the [fintech example](examples.md#a-fully-branded-kyc-flow).

## How strict each action is

`DetectorTuning` sets how strict each action is (how big a smile counts,
how far to turn, how long to hold…). Tested defaults, all adjustable. The
[honest notes](limitations.md) list the actions that most often need
loosening.
