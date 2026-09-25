part of 'liveness_detector.dart';

/// Reads state from, and drives, a [LivenessDetector] from outside the
/// widget — for custom UIs that hide the built-in close button, "try
/// again" flows, or analytics.
///
/// ```dart
/// final controller = LivenessController();
/// LivenessDetector(controller: controller, showCloseButton: false, ...);
/// // later:
/// controller.cancel();          // result delivered with cancelledBy: 'user'
/// await controller.restart();   // new session, new sessionId, new shuffle
/// ```
///
/// Listeners are notified (on a microtask) whenever [state] changes. Create
/// it in a `State` and dispose it there; one controller drives one
/// detector at a time.
class LivenessController extends ChangeNotifier {
  _LivenessDetectorState? _host;
  _LivenessRunState? _currentRun;
  Completer<void>? _runStart;
  bool _notifyScheduled = false;
  bool _disposed = false;

  static const _idle = LivenessSessionState(
    phase: LivenessPhase.initializing,
    totalActions: 0,
  );

  /// The current session's latest state. `initializing` with no actions
  /// while no detector is attached.
  LivenessSessionState get state => _currentRun?._session.current ?? _idle;

  /// The actions in the order this session runs them (after any shuffle).
  /// Empty while no detector is attached.
  List<LivenessAction> get actionPlan =>
      _currentRun?._session.actionOrder ?? const [];

  /// Audit ID of the current session, or null while no detector is
  /// attached. Changes on [restart].
  String? get sessionId => _currentRun?._sessionId;

  /// Whether a [LivenessDetector] is currently using this controller.
  bool get isAttached => _host != null;

  /// Cancels the running session; `onResult` receives a `cancelled` result
  /// with `metadata['cancelledBy'] == 'user'`. Does nothing if the session
  /// already ended or no detector is attached.
  void cancel() => _currentRun?._cancel();

  /// Ends the current session and starts a new one with a fresh session,
  /// session ID and action shuffle. If the current session is still
  /// running, `onResult` receives it as `cancelled` with
  /// `metadata['cancelledBy'] == 'restart'`; every session gets exactly one
  /// result.
  ///
  /// Completes once the new session's camera is running (or has failed to
  /// start, which is reported through `onResult` as usual). Throws a
  /// [StateError] if no detector is attached.
  Future<void> restart() {
    final host = _host;
    if (host == null) {
      throw StateError('LivenessController is not attached to a '
          'LivenessDetector.');
    }
    return host._restart();
  }

  Future<void> _expectRun() {
    final previous = _runStart;
    if (previous != null && !previous.isCompleted) previous.complete();
    final next = _runStart = Completer<void>();
    return next.future;
  }

  void _attach(_LivenessRunState run) {
    _currentRun = run;
    _scheduleNotify();
  }

  void _detach(_LivenessRunState run) {
    if (_currentRun != run) return;
    _currentRun = null;
    _scheduleNotify();
  }

  void _runStarted(_LivenessRunState run) {
    if (_currentRun != run) return;
    final pending = _runStart;
    _runStart = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  /// Coalesces notifications and keeps them out of build/dispose.
  void _scheduleNotify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    final pending = _runStart;
    if (pending != null && !pending.isCompleted) pending.complete();
    super.dispose();
  }
}
