/// How serious a [GantryLogEvent] is.
enum GantryLogLevel {
  /// Routine detail, useful while integrating.
  debug,

  /// Something failed and the SDK carried on with a fallback.
  warning,

  /// A problem that needs fixing, such as a rejected API key.
  error,
}

/// Something the SDK wants the app to know about.
///
/// Events never contain the API key or a customer id.
class GantryLogEvent {
  /// Creates an event.
  const GantryLogEvent(this.level, this.message, {this.error});

  /// How serious the event is.
  final GantryLogLevel level;

  /// What happened.
  final String message;

  /// The underlying error, if any.
  final Object? error;

  @override
  String toString() => error == null
      ? '[gantry ${level.name}] $message'
      : '[gantry ${level.name}] $message: $error';
}

/// Receives the SDK's log events; pass one as `onLog` to `Gantry`.
typedef GantryLogger = void Function(GantryLogEvent event);

/// Hands events to the app's logger and shields the SDK from its failures.
class LogSink {
  /// Creates a sink; with a null [_onLog] every event is dropped.
  const LogSink(this._onLog);

  final GantryLogger? _onLog;

  /// Reports routine detail.
  void debug(String message) => _emit(GantryLogLevel.debug, message, null);

  /// Reports a failure the SDK recovered from.
  void warning(String message, [Object? error]) =>
      _emit(GantryLogLevel.warning, message, error);

  /// Reports a problem that needs fixing.
  void error(String message, [Object? error]) =>
      _emit(GantryLogLevel.error, message, error);

  void _emit(GantryLogLevel level, String message, Object? error) {
    final onLog = _onLog;
    if (onLog == null) return;
    try {
      onLog(GantryLogEvent(level, message, error: error));
    } catch (_) {
      // A broken logger must not break the app's flow.
    }
  }
}
