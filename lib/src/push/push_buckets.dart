import 'dart:math';

import '../log/gantry_log.dart';
import '../store/gantry_store.dart';

/// Subscribes the device to an FCM topic; pass one as `subscribeToTopic` to
/// `Gantry`, usually `FirebaseMessaging.instance.subscribeToTopic`.
typedef TopicSubscriber = Future<void> Function(String topic);

/// Puts the device into a push bucket, so Gantry can send a topic push in
/// parts instead of to everyone at once.
///
/// The device gets a number from 0 to 99 once and keeps it: it belongs to the
/// device and survives `Gantry.reset()`. [sync] subscribes the device to the
/// three topics of that number: `bo_bucket_37`, `bo_decile_3` and
/// `bo_bucketed`. A device outside the buckets still receives the push, in
/// the last step together with every other such device.
class PushBuckets {
  /// Creates the bucket keeper; [subscribe] is null when the app gave none.
  PushBuckets({
    required GantryStore store,
    required TopicSubscriber? subscribe,
    required LogSink log,
    Random? random,
  })  : _store = store,
        _subscribe = subscribe,
        _log = log,
        _random = random ?? Random();

  /// Key of the device's bucket number in the store.
  static const String storeKey = 'gantry.bucket';

  /// How many buckets there are.
  static const int bucketCount = 100;

  /// The topic that marks a device as being in a bucket.
  static const String markerTopic = 'bo_bucketed';

  static final RegExp _savedFormat = RegExp(r'^\d{1,2}$');

  final GantryStore _store;
  final TopicSubscriber? _subscribe;
  final LogSink _log;
  final Random _random;

  int? _bucket;
  Future<void>? _syncing;

  /// The topics of [bucket], in the order they are subscribed to.
  ///
  /// The marker comes last: a device that got only part of the way stays
  /// outside the buckets and receives a push once, in the last step.
  static List<String> topicsFor(int bucket) => [
        'bo_bucket_${bucket.toString().padLeft(2, '0')}',
        'bo_decile_${bucket ~/ 10}',
        markerTopic,
      ];

  /// Subscribes the device to its bucket topics. Never throws.
  ///
  /// Call it on every app start, after notification permission is settled,
  /// and whenever the FCM token is refreshed. Calling it again is harmless.
  /// Calls made while one is running share its work.
  Future<void> sync() =>
      _syncing ??= _sync().whenComplete(() => _syncing = null);

  Future<void> _sync() async {
    final subscribe = _subscribe;
    if (subscribe == null) {
      _log.warning(
          'Push buckets were not synced: pass subscribeToTopic to Gantry');
      return;
    }
    final bucket = await _loadBucket();
    if (bucket == null) return;

    for (final topic in topicsFor(bucket)) {
      try {
        await subscribe(topic);
      } catch (error) {
        _log.warning(
            'Could not subscribe to $topic; the remaining bucket topics are '
            'skipped until the next sync',
            error);
        return;
      }
    }
    _log.debug('Subscribed to push bucket $bucket');
  }

  // The saved number, or a new one once it has been saved. Null when the
  // number cannot be trusted to still be there on the next launch.
  Future<int?> _loadBucket() async {
    final known = _bucket;
    if (known != null) return known;

    final String? saved;
    try {
      saved = await _store.read(storeKey);
    } catch (error) {
      _log.warning('Could not read the push bucket', error);
      return null;
    }
    if (saved != null && _savedFormat.hasMatch(saved)) {
      return _bucket = int.parse(saved);
    }

    final picked = _random.nextInt(bucketCount);
    try {
      await _store.write(storeKey, '$picked');
    } catch (error) {
      // Subscribing now would put the device into a second bucket on the next
      // launch, and it would receive the same push twice.
      _log.warning('Could not save the push bucket', error);
      return null;
    }
    return _bucket = picked;
  }
}
