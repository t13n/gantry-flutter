import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/session.dart';

void main() {
  test('starts without a customer', () {
    expect(Session().customerId, isNull);
  });

  test('identify accepts the documented customer id format', () {
    final session = Session();
    for (final id in ['cust-1001', 'A_b.c:d-9', 'x', 'a' * 64]) {
      session.identify(id);
      expect(session.customerId, id);
    }
  });

  test('identify rejects anything else and keeps the current customer', () {
    final session = Session()..identify('cust-1');
    for (final id in ['', ' ', 'a b', 'müşteri', 'a/b', 'a' * 65, 'cust-1\n']) {
      expect(() => session.identify(id), throwsArgumentError, reason: '"$id"');
    }
    expect(session.customerId, 'cust-1');
  });

  test('a new customer and a reset drop the customer cache', () {
    final session = Session()..identify('cust-1');
    final generation = session.generation;

    session.targeted = const TargetedCache(etag: '"a"', body: '{}');
    session.identify('cust-1');
    expect(session.targeted, isNotNull);
    expect(session.generation, generation);

    session.identify('cust-2');
    expect(session.targeted, isNull);
    expect(session.generation, greaterThan(generation));

    session.targeted = const TargetedCache(etag: '"b"', body: '{}');
    session.reset();
    expect(session.customerId, isNull);
    expect(session.targeted, isNull);
  });
}
