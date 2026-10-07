import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/store/shared_preferences_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads, writes and removes through shared_preferences', () async {
    SharedPreferences.setMockInitialValues(
        {'gantry.shown': '{"a":"2026-10-07T09:00:00.000Z"}'});
    final store = SharedPreferencesGantryStore();

    expect(
        await store.read('gantry.shown'), '{"a":"2026-10-07T09:00:00.000Z"}');
    expect(await store.read('missing'), isNull);

    await store.write('gantry.shown', '{}');
    expect((await SharedPreferences.getInstance()).getString('gantry.shown'),
        '{}');

    await store.remove('gantry.shown');
    expect(await store.read('gantry.shown'), isNull);
  });
}
