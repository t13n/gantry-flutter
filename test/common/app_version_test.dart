import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/common/app_version.dart';

void main() {
  test('parses one, two and three part versions', () {
    for (final value in ['1', '1.2', '1.2.3', '10.20.30', '0.0.1']) {
      expect(AppVersion.tryParse(value), isNotNull, reason: value);
    }
  });

  test('rejects other shapes', () {
    for (final value in [
      '',
      '1.',
      '.1',
      'v1',
      '1.2.3.4',
      '1.2-beta',
      ' 1.2',
      '1.2\n',
      '1,2'
    ]) {
      expect(AppVersion.tryParse(value), isNull, reason: '"$value"');
    }
  });

  test('rejects parts too large for an int', () {
    expect(AppVersion.tryParse('99999999999999999999.1'), isNull);
  });

  test('compares parts numerically, not as text', () {
    expect(AppVersion.parse('2.10') >= AppVersion.parse('2.9'), isTrue);
    expect(AppVersion.parse('2.9') >= AppVersion.parse('2.10'), isFalse);
    expect(AppVersion.parse('10') >= AppVersion.parse('9.9.9'), isTrue);
  });

  test('treats missing parts as zero', () {
    expect(AppVersion.parse('2.3').compareTo(AppVersion.parse('2.3.0')), 0);
    expect(AppVersion.parse('2') >= AppVersion.parse('2.0.0'), isTrue);
    expect(AppVersion.parse('2') >= AppVersion.parse('2.0.1'), isFalse);
  });

  test('parse throws an ArgumentError that names the argument', () {
    expect(
      () => AppVersion.parse('abc', name: 'appVersion'),
      throwsA(isA<ArgumentError>()
          .having((error) => error.name, 'name', 'appVersion')),
    );
  });
}
