/// An app version written as `1`, `1.2` or `1.2.3`.
///
/// Parts are compared as numbers and a missing part counts as zero, so
/// `2.10 > 2.9` and `2.3 == 2.3.0`.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion._(this._parts);

  static final RegExp _format = RegExp(r'^\d+(\.\d+){0,2}$');

  final List<int> _parts;

  /// Returns null when [value] is not a valid version.
  static AppVersion? tryParse(String value) {
    if (!_format.hasMatch(value)) return null;
    final parts = <int>[];
    for (final part in value.split('.')) {
      final number = int.tryParse(part);
      if (number == null) return null;
      parts.add(number);
    }
    while (parts.length < 3) {
      parts.add(0);
    }
    return AppVersion._(parts);
  }

  /// Throws an [ArgumentError] named [name] when [value] is not a valid version.
  static AppVersion parse(String value, {String name = 'appVersion'}) {
    final version = tryParse(value);
    if (version == null) {
      throw ArgumentError.value(value, name, 'must look like 1, 1.2 or 1.2.3');
    }
    return version;
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final difference = _parts[i].compareTo(other._parts[i]);
      if (difference != 0) return difference;
    }
    return 0;
  }

  /// Whether this version is the same as or newer than [other].
  bool operator >=(AppVersion other) => compareTo(other) >= 0;
}
