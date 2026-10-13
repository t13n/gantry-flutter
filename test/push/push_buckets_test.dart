import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/gantry.dart';
import 'package:gantry/src/log/gantry_log.dart' show LogSink;

class _FailingStore implements GantryStore {
  _FailingStore({this.failRead = false, this.failWrite = false});

  final bool failRead;
  final bool failWrite;
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async =>
      failRead ? throw StateError('read failed') : values[key];

  @override
  Future<void> write(String key, String value) async =>
      failWrite ? throw StateError('write failed') : values[key] = value;

  @override
  Future<void> remove(String key) async => values.remove(key);
}

void main() {
  late List<String> subscribed;
  late List<GantryLogEvent> logs;

  Future<void> record(String topic) async => subscribed.add(topic);

  Gantry build({
    GantryStore? store,
    TopicSubscriber? subscribeToTopic,
    bool withSubscriber = true,
  }) {
    return Gantry(
      apiKey: 'gk_dev_test',
      appVersion: '2.3.1',
      platform: GantryPlatform.ios,
      store: store ?? MemoryGantryStore(),
      subscribeToTopic: withSubscriber ? (subscribeToTopic ?? record) : null,
      onLog: logs.add,
    );
  }

  setUp(() {
    subscribed = [];
    logs = [];
  });

  test('picks a number between 0 and 99 and keeps it', () async {
    final seen = <int>{};
    for (var seed = 0; seed < 300; seed++) {
      final store = MemoryGantryStore();
      final buckets = PushBuckets(
          store: store,
          subscribe: record,
          log: const LogSink(null),
          random: Random(seed));
      await buckets.sync();
      final saved = int.parse((await store.read(PushBuckets.storeKey))!);
      expect(saved, inInclusiveRange(0, 99));
      seen.add(saved);
    }
    expect(seen.length, greaterThan(80));
  });

  test('subscribes to the bucket, the decile and the marker, in that order',
      () async {
    final store = MemoryGantryStore();
    await store.write(PushBuckets.storeKey, '37');

    await build(store: store).push.sync();

    expect(subscribed, ['bo_bucket_37', 'bo_decile_3', 'bo_bucketed']);
    expect(logs.where((event) => event.level != GantryLogLevel.debug), isEmpty);
  });

  test('topic names are zero padded and the decile is the tens digit', () {
    expect(PushBuckets.topicsFor(7),
        ['bo_bucket_07', 'bo_decile_0', 'bo_bucketed']);
    expect(PushBuckets.topicsFor(0),
        ['bo_bucket_00', 'bo_decile_0', 'bo_bucketed']);
    expect(PushBuckets.topicsFor(99),
        ['bo_bucket_99', 'bo_decile_9', 'bo_bucketed']);
  });

  test('a new Gantry instance on the same store keeps the number', () async {
    final store = MemoryGantryStore();
    await build(store: store).push.sync();
    final first = List.of(subscribed);
    subscribed.clear();

    await build(store: store).push.sync();

    expect(subscribed, first);
  });

  test('reset keeps the number', () async {
    final store = MemoryGantryStore();
    final gantry = build(store: store);
    await gantry.push.sync();
    final first = List.of(subscribed);
    subscribed.clear();

    gantry.identify('cust-1');
    gantry.reset();
    await gantry.push.sync();

    expect(subscribed, first);
  });

  test('every sync subscribes again', () async {
    final gantry = build();
    await gantry.push.sync();
    await gantry.push.sync();

    expect(subscribed.length, 6);
    expect(subscribed.sublist(0, 3), subscribed.sublist(3));
  });

  test('a failed subscription skips the rest and does not throw', () async {
    final store = MemoryGantryStore();
    await store.write(PushBuckets.storeKey, '37');
    Future<void> failOnDecile(String topic) async {
      if (topic.startsWith('bo_decile')) throw StateError('offline');
      subscribed.add(topic);
    }

    await build(store: store, subscribeToTopic: failOnDecile).push.sync();

    expect(subscribed, ['bo_bucket_37']);
    final warning =
        logs.singleWhere((event) => event.level == GantryLogLevel.warning);
    expect(warning.message, contains('bo_decile_3'));
    expect(warning.error, isA<StateError>());
  });

  test('a subscriber that throws synchronously does not break sync', () async {
    Future<void> broken(String topic) => throw StateError('no firebase');

    await build(subscribeToTopic: broken).push.sync();

    expect(logs.where((event) => event.level == GantryLogLevel.warning),
        hasLength(1));
  });

  test('nothing is subscribed when the number cannot be saved', () async {
    await build(store: _FailingStore(failWrite: true)).push.sync();

    expect(subscribed, isEmpty);
    expect(logs.single.level, GantryLogLevel.warning);
  });

  test('nothing is subscribed when the store cannot be read', () async {
    await build(store: _FailingStore(failRead: true)).push.sync();

    expect(subscribed, isEmpty);
    expect(logs.single.level, GantryLogLevel.warning);
  });

  test('a corrupt saved value is replaced', () async {
    for (final corrupt in ['abc', '100', '-1', '', ' 7', '1.5']) {
      subscribed.clear();
      final store = MemoryGantryStore();
      await store.write(PushBuckets.storeKey, corrupt);

      await build(store: store).push.sync();

      final saved = (await store.read(PushBuckets.storeKey))!;
      expect(saved, matches(RegExp(r'^\d{1,2}$')), reason: 'was "$corrupt"');
      expect(subscribed, PushBuckets.topicsFor(int.parse(saved)));
    }
  });

  test('two concurrent syncs subscribe once', () async {
    final gate = Completer<void>();
    Future<void> slow(String topic) async {
      await gate.future;
      subscribed.add(topic);
    }

    final gantry = build(subscribeToTopic: slow);
    final first = gantry.push.sync();
    final second = gantry.push.sync();
    gate.complete();
    await Future.wait([first, second]);

    expect(subscribed, hasLength(3));
  });

  test('without a subscriber sync logs and does nothing', () async {
    final store = MemoryGantryStore();

    await build(store: store, withSubscriber: false).push.sync();

    expect(subscribed, isEmpty);
    expect(await store.read(PushBuckets.storeKey), isNull);
    expect(logs.single.level, GantryLogLevel.warning);
    expect(logs.single.message, contains('subscribeToTopic'));
  });

  test('log events never contain the customer id or the API key', () async {
    final gantry = build(subscribeToTopic: (topic) async {
      throw StateError('offline');
    });
    gantry.identify('cust-secret');

    await gantry.push.sync();

    final text = logs.map((event) => event.toString()).join(' ');
    expect(text, isNot(contains('cust-secret')));
    expect(text, isNot(contains('gk_dev_test')));
  });
}
