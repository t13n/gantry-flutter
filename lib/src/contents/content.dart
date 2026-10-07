import '../common/gantry_action.dart';
import '../common/localized_text.dart';

/// A long text in two forms: the Markdown written in Gantry and the cleaned
/// HTML made from it. Render whichever suits the app.
class ContentBody {
  /// Creates a body.
  const ContentBody({required this.markdown, required this.html});

  /// The text as Markdown.
  final LocalizedText markdown;

  /// The same text as sanitized HTML: headings, paragraphs, lists, emphasis,
  /// https links and images, quotes, code and tables.
  final LocalizedText html;

  /// Reads `{ "markdown": {...}, "html": {...} }`; returns null when either
  /// form is missing.
  static ContentBody? fromJson(Object? json) {
    if (json is! Map) return null;
    final markdown = LocalizedText.fromJson(json['markdown']);
    final html = LocalizedText.fromJson(json['html']);
    if (markdown == null || html == null) return null;
    return ContentBody(markdown: markdown, html: html);
  }
}

/// A card listed in the app: an announcement, a campaign, a banner.
class ContentCard {
  /// Creates a card. Apps normally get cards from `Contents.list`.
  const ContentCard({
    required this.key,
    required this.category,
    required this.title,
    required this.publishedAt,
    this.summary,
    this.body,
    this.imageUrl,
    this.action,
    this.startAt,
    this.endAt,
  });

  /// Stable id of the card within the app.
  final String key;

  /// Category label given in Gantry.
  final String category;

  /// Title.
  final LocalizedText title;

  /// Short text, if any.
  final LocalizedText? summary;

  /// Long text, if any.
  final ContentBody? body;

  /// Address of the card image, if any.
  final Uri? imageUrl;

  /// What tapping the card does, if anything: a [GantryRedirectAction] or a
  /// [GantryWebPageAction].
  final GantryAction? action;

  /// When the card started being listed, if scheduled. For information only;
  /// the server already returns just the cards to show now.
  final DateTime? startAt;

  /// When the card stops being listed, if scheduled. For information only.
  final DateTime? endAt;

  /// When the card was published.
  final DateTime publishedAt;

  /// Reads a card object; returns null when it cannot be read.
  static ContentCard? fromJson(Object? json) {
    if (json is! Map || json['schemaVersion'] != 1) return null;
    final key = json['key'];
    final category = json['category'];
    final title = LocalizedText.fromJson(json['title']);
    final publishedAt = _date(json['publishedAt']);
    if (key is! String ||
        category is! String ||
        title == null ||
        publishedAt == null) {
      return null;
    }

    final action = GantryAction.fromJson(json['action']);
    if (json['action'] != null && action == null) return null;

    return ContentCard(
      key: key,
      category: category,
      title: title,
      publishedAt: publishedAt,
      summary: LocalizedText.fromJson(json['summary']),
      body: ContentBody.fromJson(json['body']),
      imageUrl: _httpUrl(json['imageUrl']),
      action: action,
      startAt: _date(json['startAt']),
      endAt: _date(json['endAt']),
    );
  }
}

/// A static page such as an FAQ or a privacy notice.
class ContentPage {
  /// Creates a page. Apps normally get pages from `Pages.get`.
  const ContentPage(
      {required this.key,
      required this.title,
      required this.body,
      required this.publishedAt});

  /// Stable id of the page within the app.
  final String key;

  /// Title.
  final LocalizedText title;

  /// The page text.
  final ContentBody body;

  /// When the page was published.
  final DateTime publishedAt;

  /// Reads a page object; returns null when it cannot be read.
  static ContentPage? fromJson(Object? json) {
    if (json is! Map || json['schemaVersion'] != 1) return null;
    final key = json['key'];
    final title = LocalizedText.fromJson(json['title']);
    final body = ContentBody.fromJson(json['body']);
    final publishedAt = _date(json['publishedAt']);
    if (key is! String ||
        title == null ||
        body == null ||
        publishedAt == null) {
      return null;
    }
    return ContentPage(
        key: key, title: title, body: body, publishedAt: publishedAt);
  }
}

DateTime? _date(Object? value) =>
    value is String ? DateTime.tryParse(value) : null;

Uri? _httpUrl(Object? value) {
  final url = value is String ? Uri.tryParse(value) : null;
  if (url == null || url.host.isEmpty) return null;
  return url.scheme == 'https' || url.scheme == 'http' ? url : null;
}
