// Runs every call of the gantry package against a Gantry server.
//
// With a local Gantry (bin/rails db:seed && bin/dev):
//   iOS simulator:     flutter run
//   Android emulator:  flutter run --dart-define=GANTRY_BASE_URL=http://10.0.2.2:3000
//
// Against another server:
//   flutter run --dart-define=GANTRY_BASE_URL=https://app.gantryhq.net \
//               --dart-define=GANTRY_API_KEY=gk_dev_...

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:gantry/gantry.dart';

const _baseUrl = String.fromEnvironment(
  'GANTRY_BASE_URL',
  defaultValue: 'http://localhost:3000',
);
const _apiKey = String.fromEnvironment(
  'GANTRY_API_KEY',
  defaultValue: 'gk_dev_seedseedseedseedseedseedseedseed',
);

void main() =>
    runApp(const MaterialApp(title: 'Gantry example', home: ExampleScreen()));

/// Exercises every call of the SDK against a Gantry server.
class ExampleScreen extends StatefulWidget {
  const ExampleScreen({super.key});

  @override
  State<ExampleScreen> createState() => _ExampleScreenState();
}

class _ExampleScreenState extends State<ExampleScreen> {
  final _customerId = TextEditingController(text: 'cust-1001');
  final _log = <String>[];
  late final Gantry _gantry;

  // Stands in for Firebase Remote Config. A real app passes
  // (key) => FirebaseRemoteConfig.instance.getString(key) instead.
  bool _targetedFlag = false;
  String _frequency = 'everyLaunch';

  List<ContentCard> _cards = const [];
  ContentPage? _page;

  @override
  void initState() {
    super.initState();
    _gantry = Gantry(
      apiKey: _apiKey,
      appVersion: '2.3.1',
      baseUrl: Uri.parse(_baseUrl),
      remoteConfig: _readRemoteConfig,
      onLog: (event) => _say(event.toString()),
    );
  }

  @override
  void dispose() {
    _gantry.close();
    _customerId.dispose();
    super.dispose();
  }

  String? _readRemoteConfig(String key) {
    return switch (key) {
      'bo_interstitial_targeted' => '$_targetedFlag',
      'bo_interstitial' => jsonEncode({
        'id': 'coaching-lead',
        'schemaVersion': 1,
        'enabled': true,
        'startAt': '2026-01-01T00:00:00.000Z',
        'endAt': '2030-01-01T00:00:00.000Z',
        'platform': ['all'],
        'minAppVersion': '1.0.0',
        'frequency': {'type': _frequency},
        'audience': {'type': 'all'},
        'priority': 100,
        'content': {
          'title': {
            'tr': 'Sağlık koçunuzla tanışın',
            'en': 'Meet your health coach',
          },
          'description': {
            'tr': 'Sizi arayalım, birlikte planlayalım.',
            'en': 'Let us call you and plan together.',
          },
          'imageUrl': 'https://picsum.photos/seed/gantry/600/400',
          'a11yLabel': {'tr': 'Kampanya görseli', 'en': 'Campaign image'},
          'primaryButtonLabel': {'tr': 'Beni arayın', 'en': 'Call me'},
          'primaryAction': {
            'type': 'lead',
            'trackingEvent': 'coaching_lead_click',
          },
          'secondaryButtonLabel': {'tr': 'Kapat', 'en': 'Close'},
          'secondaryAction': {'type': 'dismiss'},
        },
      }),
      _ => null,
    };
  }

  void _say(String message) {
    if (!mounted) return;
    setState(() => _log.insert(0, message));
  }

  void _identify() {
    try {
      _gantry.identify(_customerId.text.trim());
      _say('Identified as ${_customerId.text.trim()}');
    } on ArgumentError catch (error) {
      _say('Invalid customer id: ${error.message}');
    }
  }

  void _reset() {
    _gantry.reset();
    _say('Signed out');
  }

  Future<void> _showInterstitial() async {
    final interstitial = await _gantry.interstitials.next();
    if (!mounted) return;
    if (interstitial == null) {
      _say('No interstitial to show');
      return;
    }

    await _gantry.interstitials.markShown(interstitial);
    if (!mounted) return;
    final secondaryLabel = interstitial.secondaryButtonLabel;
    final secondaryAction = interstitial.secondaryAction;
    final chosen = await showDialog<GantryAction>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(interstitial.title.resolve('en')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.network(
              interstitial.imageUrl.toString(),
              semanticLabel: interstitial.a11yLabel.resolve('en'),
              errorBuilder: (context, error, stack) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            Text(interstitial.description.resolve('en')),
            const SizedBox(height: 12),
            Text(
              '${interstitial.id} · ${interstitial.audience.name} · ${interstitial.frequency.name}',
            ),
          ],
        ),
        actions: [
          if (secondaryLabel != null && secondaryAction != null)
            TextButton(
              onPressed: () => Navigator.pop(context, secondaryAction),
              child: Text(secondaryLabel.resolve('en')),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(context, interstitial.primaryAction),
            child: Text(interstitial.primaryButtonLabel.resolve('en')),
          ),
        ],
      ),
    );
    if (chosen != null) await _run(chosen, interstitial);
  }

  Future<void> _run(GantryAction action, Interstitial interstitial) async {
    switch (action) {
      case GantryRedirectAction(:final deeplink):
        _say('Would open the deeplink $deeplink');
      case GantryWebPageAction(:final url):
        _say('Would open the web page $url');
      case GantryDismissAction():
        _say('Dismissed');
      case GantryLeadAction():
        try {
          await _gantry.leads.submit(campaignId: interstitial.id);
          _say('Lead sent for ${interstitial.id}');
        } on GantryNotIdentifiedException {
          _say('Sign in before sending a lead');
        } on GantryException catch (error) {
          _say('Lead failed: $error');
        }
    }
  }

  Future<void> _loadCards() async {
    try {
      final cards = await _gantry.contents.list();
      if (!mounted) return;
      setState(() => _cards = cards);
      _say('Loaded ${cards.length} card(s)');
    } on GantryException catch (error) {
      _say('Cards failed: $error');
    }
  }

  Future<void> _loadPage() async {
    try {
      final page = await _gantry.pages.get('kvkk');
      if (!mounted) return;
      setState(() => _page = page);
      _say(
        page == null
            ? 'The page kvkk is not published'
            : 'Loaded the page kvkk',
      );
    } on GantryException catch (error) {
      _say('Page failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = _page;
    return Scaffold(
      appBar: AppBar(title: const Text('Gantry example')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Server: $_baseUrl',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customerId,
            decoration: const InputDecoration(
              labelText: 'Customer id',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton(onPressed: _identify, child: const Text('Sign in')),
              OutlinedButton(onPressed: _reset, child: const Text('Sign out')),
              Text(_gantry.isIdentified ? 'Signed in' : 'Signed out'),
            ],
          ),
          const Divider(height: 32),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('bo_interstitial_targeted'),
            subtitle: const Text(
              'Remote Config flag: ask the API for a targeted campaign',
            ),
            value: _targetedFlag,
            onChanged: (value) => setState(() => _targetedFlag = value),
          ),
          Row(
            children: [
              const Text('Frequency of the general campaign'),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _frequency,
                items: const [
                  DropdownMenuItem(
                    value: 'everyLaunch',
                    child: Text('everyLaunch'),
                  ),
                  DropdownMenuItem(value: 'daily', child: Text('daily')),
                  DropdownMenuItem(value: 'once', child: Text('once')),
                ],
                onChanged: (value) =>
                    setState(() => _frequency = value ?? _frequency),
              ),
            ],
          ),
          FilledButton(
            onPressed: _showInterstitial,
            child: const Text('Show the next interstitial'),
          ),
          const Divider(height: 32),
          Wrap(
            spacing: 8,
            children: [
              FilledButton.tonal(
                onPressed: _loadCards,
                child: const Text('Load cards'),
              ),
              FilledButton.tonal(
                onPressed: _loadPage,
                child: const Text('Load page kvkk'),
              ),
            ],
          ),
          for (final card in _cards)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(card.title.resolve('en')),
              subtitle: Text(
                '${card.category} · ${card.summary?.resolve('en') ?? 'no summary'}',
              ),
            ),
          if (page != null) ...[
            const SizedBox(height: 8),
            Text(
              page.title.resolve('en'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(page.body.markdown.resolve('en')),
          ],
          const Divider(height: 32),
          Text('Log', style: Theme.of(context).textTheme.titleMedium),
          for (final line in _log)
            Text(line, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}
