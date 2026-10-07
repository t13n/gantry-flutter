import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/store/gantry_store.dart';

void main() {
  test('MemoryGantryStore reads back what it wrote', () async {
    final store = MemoryGantryStore();

    expect(await store.read('a'), isNull);
    await store.write('a', '1');
    expect(await store.read('a'), '1');
    await store.remove('a');
    expect(await store.read('a'), isNull);
  });
}
