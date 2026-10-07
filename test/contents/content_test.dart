import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gantry/src/common/gantry_action.dart';
import 'package:gantry/src/contents/content.dart';

import '../support/fixtures.dart';

void main() {
  List<Map<String, dynamic>> items() {
    final json = jsonDecode(fixture('contents.json')) as Map<String, dynamic>;
    return (json['items'] as List).cast<Map<String, dynamic>>();
  }

  Map<String, dynamic> page() =>
      jsonDecode(fixture('page.json')) as Map<String, dynamic>;

  group('ContentCard', () {
    test('reads a full card', () {
      final card = ContentCard.fromJson(items().first)!;

      expect(card.key, 'yaz-kampanyasi');
      expect(card.category, 'kampanya');
      expect(card.title.en, 'Summer deal');
      expect(card.summary!.tr, 'Yaz boyunca indirim');
      expect(card.body!.markdown.tr, '**Yaz** boyunca…');
      expect(card.body!.html.tr, '<p><strong>Yaz</strong> boyunca…</p>');
      expect(card.body!.html.en, isNull);
      expect(card.imageUrl, Uri.parse('https://cdn.example.com/summer.png'));
      expect(card.action, isA<GantryWebPageAction>());
      expect(card.action!.trackingEvent, 'summer_tap');
      expect(card.startAt, DateTime.utc(2026, 10, 10));
      expect(card.endAt, isNull);
      expect(card.publishedAt, DateTime.utc(2026, 10, 8, 9, 12));
    });

    test('reads a card whose optional fields are null', () {
      final card = ContentCard.fromJson(items().last)!;

      expect(card.key, 'bakim-duyurusu');
      expect(card.title.resolve('en'), 'Planlı bakım');
      expect(card.summary, isNull);
      expect(card.body, isNull);
      expect(card.imageUrl, isNull);
      expect(card.action, isNull);
      expect(card.startAt, isNull);
    });

    test('ignores fields it does not know', () {
      expect(
          ContentCard.fromJson({...items().first, 'badge': 'new'}), isNotNull);
    });

    test('skips a card it cannot read', () {
      final card = items().first;
      final broken = <Object?>[
        null,
        'card',
        {...card, 'schemaVersion': 2},
        {...card, 'key': null},
        {...card, 'category': null},
        {
          ...card,
          'title': {'en': 'Summer deal'}
        },
        {...card, 'publishedAt': 'yesterday'},
        {
          ...card,
          'action': {'type': 'share'}
        },
      ];
      for (final json in broken) {
        expect(ContentCard.fromJson(json), isNull, reason: jsonEncode(json));
      }
    });

    test('drops an image address that is not http or https', () {
      final card = ContentCard.fromJson(
          {...items().first, 'imageUrl': 'file:///etc/hosts'})!;
      expect(card.imageUrl, isNull);
    });
  });

  group('ContentPage', () {
    test('reads a page', () {
      final content = ContentPage.fromJson(page())!;

      expect(content.key, 'kvkk');
      expect(content.title.tr, 'KVKK Aydınlatma Metni');
      expect(content.body.markdown.tr, startsWith('## Amaç'));
      expect(content.body.html.tr, startsWith('<h2>Amaç</h2>'));
      expect(content.publishedAt, DateTime.utc(2026, 10, 8, 9, 12));
    });

    test('skips a page it cannot read', () {
      final broken = <Object?>[
        null,
        {...page(), 'schemaVersion': 2},
        {...page(), 'key': 7},
        {...page(), 'title': null},
        {...page(), 'body': null},
        {
          ...page(),
          'body': {
            'markdown': {'tr': 'x'}
          }
        },
        {...page(), 'publishedAt': null},
      ];
      for (final json in broken) {
        expect(ContentPage.fromJson(json), isNull, reason: jsonEncode(json));
      }
    });
  });
}
