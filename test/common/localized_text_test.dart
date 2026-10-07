import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/common/localized_text.dart';

void main() {
  const both = LocalizedText(tr: 'Merhaba', en: 'Hello');

  test('resolves the requested language', () {
    expect(both.resolve('tr'), 'Merhaba');
    expect(both.resolve('en'), 'Hello');
  });

  test('accepts locale tags', () {
    expect(both.resolve('en-US'), 'Hello');
    expect(both.resolve('en_GB'), 'Hello');
    expect(both.resolve('EN'), 'Hello');
  });

  test('falls back to Turkish', () {
    expect(both.resolve('de'), 'Merhaba');
    expect(const LocalizedText(tr: 'Merhaba').resolve('en'), 'Merhaba');
    expect(const LocalizedText(tr: 'Merhaba', en: '').resolve('en'), 'Merhaba');
  });

  test('fromJson reads tr and optional en', () {
    expect(LocalizedText.fromJson({'tr': 'Merhaba', 'en': 'Hello'}), both);
    expect(LocalizedText.fromJson({'tr': 'Merhaba'}),
        const LocalizedText(tr: 'Merhaba'));
    expect(LocalizedText.fromJson({'tr': 'Merhaba', 'de': 'Hallo'}),
        const LocalizedText(tr: 'Merhaba'));
  });

  test('fromJson returns null without a Turkish text', () {
    expect(LocalizedText.fromJson(null), isNull);
    expect(LocalizedText.fromJson('Merhaba'), isNull);
    expect(LocalizedText.fromJson({'en': 'Hello'}), isNull);
    expect(LocalizedText.fromJson({'tr': 1}), isNull);
  });
}
