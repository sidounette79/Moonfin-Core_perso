import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import '../../../data/services/bazarr_service.dart';
import '../../../preference/bazarr_preferences.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import 'settings_app_bar.dart';

/// Direct Bazarr connection settings (URL + API key), separate from
/// Emby's own subtitle search. Sid: "le mien c'est lien direct vers
/// bazarr" - deliberately simple compared to seerr_config_screen.dart
/// (no rows, profiles, root folders - just enough to reach one Bazarr
/// instance and let the subtitle search action below use it when
/// configured).
class BazarrConfigScreen extends StatefulWidget {
  const BazarrConfigScreen({super.key});

  @override
  State<BazarrConfigScreen> createState() => _BazarrConfigScreenState();
}

class _BazarrConfigScreenState extends State<BazarrConfigScreen> {
  late final BazarrPreferences _prefs = GetIt.instance<BazarrPreferences>();
  late final BazarrService _service = GetIt.instance<BazarrService>();

  late final TextEditingController _urlController = TextEditingController(
    text: _prefs.serverUrl,
  );
  late final TextEditingController _apiKeyController = TextEditingController(
    text: _prefs.apiKey,
  );
  late bool _enabled = _prefs.enabled;
  bool _obscureApiKey = true;
  bool _testing = false;
  String? _testResult;
  bool _testSucceeded = false;

  @override
  void dispose() {
    _urlController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await _prefs.setServerUrl(_urlController.text.trim());
    await _prefs.setApiKey(_apiKeyController.text.trim());
    await _prefs.setEnabled(_enabled);
  }

  Future<void> _test() async {
    await _save();
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final ok = await _service.testConnection();
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testSucceeded = ok;
      _testResult = ok
          ? 'Connexion réussie.'
          : 'Échec - vérifie l\'adresse et la clé API.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return withCleanSettingsTypography(
      context,
      Scaffold(
        appBar: buildSettingsAppBar(context, const Text('Bazarr')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Recherche directe des sous-titres via Bazarr plutôt que via '
              'Emby - télécharge français et anglais automatiquement, sans '
              'liste à choisir (Bazarr sélectionne lui-même le meilleur '
              'résultat).',
              style: TextStyle(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Activer Bazarr'),
              value: _enabled,
              onChanged: (v) {
                setState(() => _enabled = v);
                unawaited(_save());
              },
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Adresse du serveur',
                hintText: 'https://bazarr.sidounette.ch',
              ),
              keyboardType: TextInputType.url,
              onEditingComplete: () => unawaited(_save()),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyController,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'Clé API',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureApiKey
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscureApiKey = !_obscureApiKey),
                ),
              ),
              onEditingComplete: () => unawaited(_save()),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _testing ? null : _test,
              child: _testing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Tester la connexion'),
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testSucceeded ? Colors.green : Colors.red,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
