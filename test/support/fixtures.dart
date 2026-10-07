import 'dart:convert';
import 'dart:io';

/// Reads a file from test/fixtures.
String fixture(String name) => File('test/fixtures/$name').readAsStringSync();

/// The interstitial fixture as a map, with top-level [overrides] applied.
Map<String, dynamic> interstitialJson(
    {Map<String, dynamic> overrides = const {}}) {
  final json = jsonDecode(fixture('interstitial.json')) as Map<String, dynamic>;
  return {...json, ...overrides};
}

/// The interstitial fixture with keys of its `content` object replaced; a null
/// value removes the key.
Map<String, dynamic> interstitialJsonWithContent(Map<String, dynamic> content) {
  final json = interstitialJson();
  final merged = {...json['content'] as Map<String, dynamic>, ...content}
    ..removeWhere((key, value) => value == null);
  return {...json, 'content': merged};
}
