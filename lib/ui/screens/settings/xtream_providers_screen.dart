import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/xtream_models.dart';
import '../../../data/repositories/xtream_repository.dart';
import '../../../preference/user_preferences.dart';
import '../../navigation/destinations.dart';

/// 30.09, Sid: direct IPTV (Xtream Codes), bypassing Emby's own Live TV
/// entirely - "TiviMate-style". Hardcoded French strings rather than proper
/// l10n entries for now (brand new screen, personal fork, French-speaking
/// household) - can be localized later if this becomes a lasting feature.
class XtreamProvidersScreen extends StatefulWidget {
  const XtreamProvidersScreen({super.key});

  @override
  State<XtreamProvidersScreen> createState() => _XtreamProvidersScreenState();
}

class _XtreamProvidersScreenState extends State<XtreamProvidersScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  late List<XtreamProvider> _providers;

  @override
  void initState() {
    super.initState();
    _providers = _prefs.getXtreamProviders();
  }

  Future<void> _reload() async {
    setState(() => _providers = _prefs.getXtreamProviders());
  }

  Future<void> _openEditor({XtreamProvider? existing}) async {
    final result = await showDialog<XtreamProvider>(
      context: context,
      builder: (_) => _ProviderEditorDialog(existing: existing),
    );
    if (result == null) return;
    await _prefs.addOrUpdateXtreamProvider(result);
    await _reload();
  }

  Future<void> _delete(XtreamProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce fournisseur ?'),
        content: Text(
          '${provider.name} sera retiré, avec les catégories choisies pour lui.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _prefs.removeXtreamProvider(provider.id);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fournisseurs IPTV'),
        actions: [
          IconButton(
            icon: const Icon(Icons.live_tv),
            tooltip: 'Voir les chaînes',
            onPressed: () => context.push(Destinations.xtreamChannels),
          ),
        ],
      ),
      body: _providers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aucun fournisseur IPTV configuré.\nAjoute-en un pour commencer.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _providers.length,
              itemBuilder: (context, index) {
                final provider = _providers[index];
                return ListTile(
                  title: Text(provider.name),
                  subtitle: Text(provider.baseUrl),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          XtreamCategoryPickerScreen(provider: provider),
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _openEditor(existing: provider),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(provider),
                      ),
                    ],
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: const Text('Ajouter'),
      ),
    );
  }
}

class _ProviderEditorDialog extends StatefulWidget {
  final XtreamProvider? existing;

  const _ProviderEditorDialog({this.existing});

  @override
  State<_ProviderEditorDialog> createState() => _ProviderEditorDialogState();
}

class _ProviderEditorDialogState extends State<_ProviderEditorDialog> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _urlController = TextEditingController(
    text: widget.existing?.baseUrl ?? '',
  );
  late final _userController = TextEditingController(
    text: widget.existing?.username ?? '',
  );
  late final _passController = TextEditingController(
    text: widget.existing?.password ?? '',
  );
  bool _obscurePassword = true;
  bool _testing = false;
  String? _testResult;

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  XtreamProvider _buildProvider() => XtreamProvider(
    id: widget.existing?.id ?? const Uuid().v4(),
    name: _nameController.text.trim(),
    baseUrl: _urlController.text.trim(),
    username: _userController.text.trim(),
    password: _passController.text,
  );

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final info = await XtreamRepository().getAccountInfo(_buildProvider());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testResult = info == null
          ? 'Échec - vérifie l\'adresse et les identifiants'
          : 'OK - statut: ${info.status}, ${info.activeConnections}/${info.maxConnections} connexion(s) active(s)'
                '${info.expiresAt != null ? ', expire le ${info.expiresAt!.day}.${info.expiresAt!.month}.${info.expiresAt!.year}' : ''}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null
          ? 'Ajouter un fournisseur'
          : 'Modifier le fournisseur'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nom (libre)'),
            ),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                labelText: 'Adresse du serveur',
                hintText: 'http://exemple.com',
              ),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: _userController,
              decoration: const InputDecoration(labelText: 'Utilisateur'),
            ),
            TextField(
              controller: _passController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Mot de passe',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_testResult != null)
              Text(
                _testResult!,
                style: TextStyle(
                  color: _testResult!.startsWith('OK')
                      ? Colors.green
                      : Colors.red,
                ),
              ),
            TextButton.icon(
              onPressed: _testing ? null : _test,
              icon: _testing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.wifi_tethering),
              label: const Text('Tester la connexion'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annuler'),
        ),
        TextButton(
          onPressed: () {
            if (_nameController.text.trim().isEmpty ||
                _urlController.text.trim().isEmpty ||
                _userController.text.trim().isEmpty ||
                _passController.text.isEmpty) {
              return;
            }
            Navigator.of(context).pop(_buildProvider());
          },
          child: const Text('Enregistrer'),
        ),
      ],
    );
  }
}

class XtreamCategoryPickerScreen extends StatefulWidget {
  final XtreamProvider provider;

  const XtreamCategoryPickerScreen({super.key, required this.provider});

  @override
  State<XtreamCategoryPickerScreen> createState() =>
      _XtreamCategoryPickerScreenState();
}

class _XtreamCategoryPickerScreenState
    extends State<XtreamCategoryPickerScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  final _repo = GetIt.instance<XtreamRepository>();
  List<XtreamCategory>? _categories;
  late Set<String> _selected;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _selected = _prefs
        .getXtreamSelectedCategoryIds()[widget.provider.id]
        ?.toSet() ??
        {};
    _load();
  }

  Future<void> _load() async {
    final categories = await _repo.getLiveCategories(widget.provider);
    if (!mounted) return;
    setState(() => _categories = categories);
  }

  Future<void> _toggle(String categoryId, bool value) async {
    setState(() {
      if (value) {
        _selected.add(categoryId);
      } else {
        _selected.remove(categoryId);
      }
    });
    await _prefs.setXtreamCategorySelected(
      widget.provider.id,
      categoryId,
      value,
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    final filtered = categories == null
        ? const <XtreamCategory>[]
        : categories
            .where((c) =>
                _filter.isEmpty ||
                c.name.toLowerCase().contains(_filter.toLowerCase()))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text('Catégories - ${widget.provider.name}'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filtrer (ex: FR, sport...)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
      ),
      body: categories == null
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final category = filtered[index];
                return CheckboxListTile(
                  title: Text(category.name),
                  value: _selected.contains(category.id),
                  onChanged: (v) => _toggle(category.id, v ?? false),
                );
              },
            ),
    );
  }
}
