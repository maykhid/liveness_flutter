# Custom look, custom UI and the controller

Three levels, from least to most work. Pick the lowest one that meets the
design.

## 1. Theme and text: `LivenessTheme` and `LivenessStrings`

No custom widgets. `LivenessTheme` sets colors, text styles, the target's
size, position and shape, and the close button. The target is also the
detection zone: the face must be inside what is drawn.

| Field | Default | Notes |
|---|---|---|
| `backgroundColor` | `Color(0xCC000000)` | Scrim outside the target. |
| `ovalBorderColor` / `ovalBorderColorActive` | white / green | Border before and after the face is in position. |
| `ovalBorderWidth` | 3 | |
| `progressColor` / `progressTrackColor` | green / translucent white | Progress arc around the target. |
| `instructionStyle`, `hintStyle`, `counterStyle` | white text | The instruction, the guidance hint, "Step N of M". |
| `successColor` / `failureColor` | green / red | |
| `ovalShape` | `TargetShape.oval` | Also `circle` and `roundedRect`. |
| `ovalSizeFactor` | 0.72 | Target width as a fraction of the shorter screen side. |
| `ovalCenter` | `Offset(0.5, 0.44)` | Normalised to the view. |
| `ovalAspectRatio` | 1.35 | Height / width; ignored for circles. |
| `closeIconColor`, `closeButtonAlignment` | white, top left | Pick a dark icon on a light scrim. |
| `flashTintOpacity` | 0.75 | Flash challenge tint strength. |
| `resultHoldDuration` | 400 ms | How long the end state shows before `onResult`. |
| `strings` | English | A `LivenessStrings`. |

`LivenessStrings` holds every visible string. The three maps
(`actionInstructions`, `guidanceMessages`, `failureMessages`) are merged
over the English defaults, so pass only the entries to change. Both
classes have `copyWith`.

```dart
import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

const frenchStrings = LivenessStrings(
  initializing: 'Démarrage de la caméra…',
  searchingFace: 'Placez votre visage dans le cadre',
  centeringFace: 'Ajustez votre visage dans le cadre',
  multipleFaces: 'Un seul visage doit être visible',
  awaitingNeutral: 'Revenez à une expression neutre',
  completed: 'Terminé !',
  failed: 'Échec de la vérification',
  holdStill: 'Ne bougez plus…',
  close: 'Fermer',
  stepCounter: _frenchStep,
  actionInstructions: {
    LivenessAction.blink: 'Clignez des yeux',
    LivenessAction.smile: 'Souriez',
    LivenessAction.lookLeft: 'Tournez la tête à gauche',
  },
  guidanceMessages: {
    FaceGuidance.tooFar: 'Rapprochez-vous',
    FaceGuidance.lowLight: 'Trouvez un endroit mieux éclairé',
  },
  failureMessages: {
    LivenessFailureReason.actionTimeout: 'Trop long, réessayez',
  },
);

String _frenchStep(int current, int total) => 'Étape $current sur $total';

const brandedTheme = LivenessTheme(
  backgroundColor: Color(0xF2FFFFFF),
  ovalShape: TargetShape.circle,
  ovalBorderColor: Color(0xFFB0BEC5),
  ovalBorderColorActive: Color(0xFF00897B),
  progressColor: Color(0xFF00897B),
  instructionStyle: TextStyle(
    color: Color(0xFF263238),
    fontSize: 20,
    fontWeight: FontWeight.w600,
  ),
  hintStyle: TextStyle(color: Color(0xFF546E7A), fontSize: 14),
  counterStyle: TextStyle(color: Color(0xFF546E7A), fontSize: 13),
  closeIconColor: Color(0xFF263238),
  strings: frenchStrings,
);
```

For app localization, build `LivenessStrings` from the app's own
localizations in `build` (a non-const theme is fine), and list every
action the config can ask for in `actionInstructions`.

`LivenessDetector` layout parameters: `instructionAlignment` (default
`Alignment(0, 0.72)`), `showCloseButton`, `closeButtonBuilder`
(`(context, onClose) => ...`).

## 2. Your own widgets: `overlayBuilder` and `instructionBuilder`

Both are `Widget Function(BuildContext, LivenessSessionState)` and rebuild
on every state change. `overlayBuilder` replaces the scrim and target;
`instructionBuilder` replaces the instruction panel.

**If you draw your own window, pass the same rectangle as
`targetRegion`**, normalised to the widget (0..1), with
`theme.ovalShape` set to the shape you drew. Without it, the face must
still fit the default oval that is no longer visible, and users get stuck
on "centering".

`LivenessSessionState` fields:

| Field | Meaning |
|---|---|
| `phase` | `initializing`, `searchingFace`, `centeringFace`, `performingAction`, `awaitingNeutral`, `completed`, `failed`. |
| `currentAction`, `currentActionIndex` | The action now, and its index. |
| `actionPlan` | Every action in this session's order, known from the first state. |
| `completedActions`, `totalActions` | |
| `actionProgress`, `overallProgress` | 0 to 1 for this action and for the session. |
| `remaining`, `actionTimeout` | Countdown for this action (only while performing) and its limit. |
| `sessionRemaining` | Time before `sessionTimeout`, or null. |
| `faceInPosition` | One face, inside the target, at the right size. |
| `guidance` | A `FaceGuidance`: `none`, `noFace`, `multipleFaces`, `tooFar`, `tooClose`, `notCentered`, `lowLight`, `tooBright`, `blurry`. |
| `failureReason` | Set when `phase` is `failed`. |

```dart
import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

/// Where the window is drawn, normalised to the screen. The same rect is
/// passed as targetRegion so detection follows the drawing.
const windowRect = Rect.fromLTWH(0.125, 0.18, 0.75, 0.44);

class BrandedLivenessPage extends StatelessWidget {
  const BrandedLivenessPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LivenessDetector(
        config: const LivenessConfig(
          actions: [LivenessAction.blink, LivenessAction.smile],
          shuffleActions: true,
          capture: {CaptureType.images},
        ),
        theme: const LivenessTheme(ovalShape: TargetShape.roundedRect),
        targetRegion: windowRect,
        overlayBuilder: (context, state) => CustomPaint(
          painter: _WindowPainter(
            color: state.faceInPosition ? Colors.tealAccent : Colors.white38,
          ),
        ),
        instructionBuilder: (context, state) => Text(
          _instruction(state),
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        onResult: (result) {
          if (!context.mounted) return;
          if (ModalRoute.of(context)?.isCurrent ?? false) {
            Navigator.pop(context, result);
          }
        },
      ),
    );
  }
}

String _instruction(LivenessSessionState state) {
  return switch (state.phase) {
    LivenessPhase.initializing => 'Starting…',
    LivenessPhase.searchingFace || LivenessPhase.centeringFace =>
      switch (state.guidance) {
        FaceGuidance.tooFar => 'Move closer',
        FaceGuidance.tooClose => 'Move back a little',
        FaceGuidance.lowLight => 'Find better light',
        _ => 'Fit your face in the window',
      },
    LivenessPhase.performingAction =>
      LivenessStrings.defaultActionInstructions[state.currentAction] ?? '',
    LivenessPhase.awaitingNeutral => 'Relax your face',
    LivenessPhase.completed => 'Done',
    LivenessPhase.failed => 'Let’s try that again',
  };
}

class _WindowPainter extends CustomPainter {
  _WindowPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final window = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        windowRect.left * size.width,
        windowRect.top * size.height,
        windowRect.width * size.width,
        windowRect.height * size.height,
      ),
      const Radius.circular(24),
    );
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Offset.zero & size),
        Path()..addRRect(window),
      ),
      Paint()..color = Colors.black87,
    );
    canvas.drawRRect(
      window,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_WindowPainter oldDelegate) => oldDelegate.color != color;
}
```

The package's example app has fuller versions: `example/lib/recipes/custom_ui.dart`
and a fully branded KYC flow in `example/lib/recipes/fintech/`.

## 3. `LivenessController`: drive it from outside

For your own Cancel and Try again buttons, or to read state elsewhere.
Create it in a `State`, dispose it there; one controller drives one
detector at a time.

| Member | Does |
|---|---|
| `state` | The latest `LivenessSessionState`. It's a `ChangeNotifier`, so wrap UI in `ListenableBuilder`. |
| `actionPlan` | This session's actions in order. |
| `sessionId` | The current session's ID, or null when detached. |
| `isAttached` | Whether a detector is using it. |
| `cancel()` | Ends the session; `onResult` gets `cancelled` with `cancelledBy: 'user'`. |
| `restart()` | New session, session ID and shuffle. A running session is delivered as `cancelled` with `cancelledBy: 'restart'`. Throws `StateError` when detached. |

```dart
import 'package:flutter/material.dart';
import 'package:liveness_flutter/liveness_flutter.dart';

class ControlledLivenessPage extends StatefulWidget {
  const ControlledLivenessPage({super.key});

  @override
  State<ControlledLivenessPage> createState() => _ControlledLivenessPageState();
}

class _ControlledLivenessPageState extends State<ControlledLivenessPage> {
  final _controller = LivenessController();
  LivenessResult? _last;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          LivenessDetector(
            controller: _controller,
            showCloseButton: false,
            config: const LivenessConfig(
              actions: [LivenessAction.blink, LivenessAction.nod],
              shuffleActions: true,
            ),
            // Every session, including one ended by restart(), lands here
            // exactly once.
            onResult: (result) {
              if (mounted) setState(() => _last = result);
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: ListenableBuilder(
                listenable: _controller,
                builder: (context, _) {
                  final phase = _controller.state.phase;
                  final ended = phase == LivenessPhase.completed ||
                      phase == LivenessPhase.failed;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: ended ? null : _controller.cancel,
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 12),
                      FilledButton(
                        onPressed: _controller.restart,
                        child: Text(_last == null ? 'Restart' : 'Try again'),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

## Callbacks and accessibility

| Parameter | Signature | Notes |
|---|---|---|
| `onActionStarted` | `(action, index)` | Sync or async, never awaited. |
| `onActionCompleted` | `(action, index)` | Same. Photos are in the final result, not here. |
| `onFeedback` | `(LivenessFeedback event)` | `actionStarted`, `actionProgressHalf`, `actionCompleted`, `sessionSucceeded`, `sessionFailed`: hook sounds, haptics or text-to-speech here. |
| `onError` | `(error, stackTrace)` | Camera, ML and attestor `prepare()` errors. |
| `permissionDeniedBuilder` | `(context, retry)` | Your page when camera access is denied; `retry` starts a fresh session. |
| `showDebugOverlay` | `bool` | Live angles and probabilities. Development only. |

Instructions are a screen-reader live region, so each new one is
announced. `hapticFeedback: true` in the config adds built-in haptics.
