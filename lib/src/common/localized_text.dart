/// A text in Turkish and, optionally, English.
class LocalizedText {
  /// Creates a text; [tr] is always present.
  const LocalizedText({required this.tr, this.en});

  /// The Turkish text.
  final String tr;

  /// The English text, when one was entered in Gantry.
  final String? en;

  /// Returns the text for [languageCode] (`en`, `en-US`, `tr`, ...).
  ///
  /// Falls back to Turkish when the language is not English or no English text
  /// was entered.
  String resolve(String languageCode) {
    final language = languageCode.split(RegExp('[-_]')).first.toLowerCase();
    final english = en;
    return language == 'en' && english != null && english.isNotEmpty
        ? english
        : tr;
  }

  /// Reads `{ "tr": "...", "en": "..." }`; returns null without a `tr` text.
  /// An empty `en` reads as missing.
  static LocalizedText? fromJson(Object? json) {
    if (json is! Map) return null;
    final tr = json['tr'];
    final en = json['en'];
    if (tr is! String) return null;
    return LocalizedText(tr: tr, en: en is String && en.isNotEmpty ? en : null);
  }

  @override
  bool operator ==(Object other) =>
      other is LocalizedText && other.tr == tr && other.en == en;

  @override
  int get hashCode => Object.hash(tr, en);

  @override
  String toString() => 'LocalizedText(tr: $tr, en: $en)';
}
