import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/log/gantry_log.dart';

void main() {
  test('forwards events with their level', () {
    final events = <GantryLogEvent>[];
    final cause = StateError('boom');
    LogSink(events.add)
      ..debug('a')
      ..warning('b', cause)
      ..error('c');

    expect(events.map((event) => event.level),
        [GantryLogLevel.debug, GantryLogLevel.warning, GantryLogLevel.error]);
    expect(events.map((event) => event.message), ['a', 'b', 'c']);
    expect(events[1].error, same(cause));
  });

  test('does nothing without a logger', () {
    expect(() => const LogSink(null).warning('ignored'), returnsNormally);
  });

  test('a logger that throws is ignored', () {
    final sink = LogSink((event) => throw StateError('logger failed'));
    expect(() => sink.error('still fine'), returnsNormally);
  });
}
