import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/version.dart';

void main() {
  test('packageVersion matches pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('\nversion: $packageVersion\n'));
  });
}
