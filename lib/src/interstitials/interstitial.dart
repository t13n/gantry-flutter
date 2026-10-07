import 'dart:convert';

import '../common/app_version.dart';
import '../common/gantry_action.dart';
import '../common/localized_text.dart';

/// How often one campaign may be shown on a device.
enum InterstitialFrequency {
  /// Once per device.
  once,

  /// Once per local calendar day.
  daily,

  /// Once every time the app is launched.
  everyLaunch,
}

/// Who a campaign is published to.
enum InterstitialAudience {
  /// Everyone; delivered through Remote Config.
  all,

  /// A list of customers; delivered through the Gantry API.
  customers,
}

/// A full-screen campaign to show when the app opens.
class Interstitial {
  /// Creates an interstitial. Apps normally get one from `Interstitials.next`.
  const Interstitial({
    required this.id,
    required this.enabled,
    required this.startAt,
    required this.endAt,
    required this.platforms,
    required this.minAppVersion,
    required this.frequency,
    required this.audience,
    required this.priority,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.a11yLabel,
    required this.primaryButtonLabel,
    required this.primaryAction,
    this.secondaryButtonLabel,
    this.secondaryAction,
  });

  /// Campaign id; pass it to `Leads.submit` as `campaignId`.
  final String id;

  /// Whether the campaign is switched on.
  final bool enabled;

  /// First moment the campaign may be shown.
  final DateTime startAt;

  /// Moment the campaign stops being shown.
  final DateTime endAt;

  /// Target platforms: `all`, `ios`, `android`.
  final Set<String> platforms;

  /// Lowest app version the campaign is meant for.
  final String minAppVersion;

  /// How often the campaign may be shown.
  final InterstitialFrequency frequency;

  /// Who the campaign is published to.
  final InterstitialAudience audience;

  /// Priority set in Gantry; higher wins on the server.
  final int priority;

  /// Headline.
  final LocalizedText title;

  /// Body text.
  final LocalizedText description;

  /// Address of the campaign image.
  final Uri imageUrl;

  /// Accessibility label for the image.
  final LocalizedText a11yLabel;

  /// Label of the main button.
  final LocalizedText primaryButtonLabel;

  /// What the main button does.
  final GantryAction primaryAction;

  /// Label of the second button, when there is one.
  final LocalizedText? secondaryButtonLabel;

  /// What the second button does, when there is one.
  final GantryAction? secondaryAction;

  /// Reads the JSON text of a campaign.
  ///
  /// Returns null for an empty value, `{}`, malformed JSON or a campaign this
  /// SDK version cannot read.
  static Interstitial? tryParse(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  /// Reads a decoded campaign object; returns null when it cannot be read.
  static Interstitial? fromJson(Object? json) {
    if (json is! Map || json['schemaVersion'] != 1) return null;
    final content = json['content'];
    if (content is! Map) return null;

    final id = json['id'];
    final enabled = json['enabled'];
    final startAt = _date(json['startAt']);
    final endAt = _date(json['endAt']);
    final platforms = _platforms(json['platform']);
    final minAppVersion = json['minAppVersion'];
    final frequency = _typed(InterstitialFrequency.values, json['frequency']);
    final audience = _typed(InterstitialAudience.values, json['audience']);
    final priority = json['priority'];
    final title = LocalizedText.fromJson(content['title']);
    final description = LocalizedText.fromJson(content['description']);
    final imageUrl = _httpUrl(content['imageUrl']);
    final a11yLabel = LocalizedText.fromJson(content['a11yLabel']);
    final primaryButtonLabel =
        LocalizedText.fromJson(content['primaryButtonLabel']);
    final primaryAction = GantryAction.fromJson(content['primaryAction']);

    if (id is! String ||
        id.isEmpty ||
        enabled is! bool ||
        startAt == null ||
        endAt == null ||
        platforms == null ||
        minAppVersion is! String ||
        AppVersion.tryParse(minAppVersion) == null ||
        frequency == null ||
        audience == null ||
        priority is! int ||
        title == null ||
        description == null ||
        imageUrl == null ||
        a11yLabel == null ||
        primaryButtonLabel == null ||
        primaryAction == null) {
      return null;
    }

    final hasSecondary = content['secondaryButtonLabel'] != null ||
        content['secondaryAction'] != null;
    final secondaryButtonLabel =
        LocalizedText.fromJson(content['secondaryButtonLabel']);
    final secondaryAction = GantryAction.fromJson(content['secondaryAction']);
    if (hasSecondary &&
        (secondaryButtonLabel == null || secondaryAction == null)) {
      return null;
    }

    return Interstitial(
      id: id,
      enabled: enabled,
      startAt: startAt,
      endAt: endAt,
      platforms: platforms,
      minAppVersion: minAppVersion,
      frequency: frequency,
      audience: audience,
      priority: priority,
      title: title,
      description: description,
      imageUrl: imageUrl,
      a11yLabel: a11yLabel,
      primaryButtonLabel: primaryButtonLabel,
      primaryAction: primaryAction,
      secondaryButtonLabel: secondaryButtonLabel,
      secondaryAction: secondaryAction,
    );
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static Set<String>? _platforms(Object? value) {
    if (value is! List || value.isEmpty) return null;
    final platforms = value.whereType<String>().toSet();
    return platforms.length == value.length ? platforms : null;
  }

  static Uri? _httpUrl(Object? value) {
    final url = value is String ? Uri.tryParse(value) : null;
    if (url == null || url.host.isEmpty) return null;
    return url.scheme == 'https' || url.scheme == 'http' ? url : null;
  }

  static T? _typed<T extends Enum>(List<T> values, Object? json) {
    if (json is! Map) return null;
    final type = json['type'];
    for (final value in values) {
      if (value.name == type) return value;
    }
    return null;
  }
}
