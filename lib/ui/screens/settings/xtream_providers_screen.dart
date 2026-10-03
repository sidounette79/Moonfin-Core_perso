import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/m3u_provider.dart';
import '../../../data/models/xtream_models.dart';
import '../../../data/repositories/xtream_repository.dart';
import '../../../preference/user_preferences.dart';
import '../../../util/platform_detection.dart';
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

enum _ProviderAction { edit, delete }

class _XtreamProvidersScreenState extends State<XtreamProvidersScreen> {
  final _prefs = GetIt.instance<UserPreferences>();
  late List<XtreamProvider> _providers;
  late List<M3uProvider> _m3uProviders;

  @override
  void initState() {
    super.initState();
    _providers = _prefs.getXtreamProviders();
    _m3uProviders = _prefs.getM3uProviders();
  }

  Future<void> _reload() async {
    setState(() {
      _providers = _prefs.getXtreamProviders();
      _m3uProviders = _prefs.getM3uProviders();
    });
  }

  Future<void> _openM3uEditor({M3uProvider? existing}) async {
    final result = await showDialog<M3uProvider>(
      context: context,
      builder: (_) => _M3uProviderEditorDialog(existing: existing),
    );
    if (result == null) return;
    await _prefs.addOrUpdateM3uProvider(result);
    await _reload();
  }

  Future<void> _deleteM3u(M3uProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer ce fournisseur M3U ?'),
        content: Text('${provider.name} sera retiré.'),
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
    await _prefs.removeM3uProvider(provider.id);
    await _reload();
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

  // 03.10, Sid: "le d-pad ne me permet pas d'aller sur l'icône pour
  // modifier un fournisseur" - les IconButton bruts dans trailing ne sont
  // jamais atteints par le D-pad télécommande/clavier (l'appui "select"
  // sur la ligne va toujours au onTap du ListTile, qui ouvre la liste des
  // chaînes). Même convention que le reste de l'appli pour les actions
  // secondaires d'une ligne (ex. showContextMenu sur les cartes média) :
  // un appui long, pas un bouton séparé à atteindre au D-pad.
  Future<void> _showProviderActions(XtreamProvider provider) async {
    final choice = await showDialog<_ProviderAction>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(provider.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ProviderAction.edit),
            child: const Text('Modifier'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ProviderAction.delete),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _ProviderAction.edit:
        await _openEditor(existing: provider);
      case _ProviderAction.delete:
        await _delete(provider);
    }
  }

  Future<void> _showM3uProviderActions(M3uProvider provider) async {
    final choice = await showDialog<_ProviderAction>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(provider.name),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ProviderAction.edit),
            child: const Text('Modifier'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(_ProviderAction.delete),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case _ProviderAction.edit:
        await _openM3uEditor(existing: provider);
      case _ProviderAction.delete:
        await _deleteM3u(provider);
    }
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

  // 30.09, Sid: "as-tu un moyen de faire un backup de cette partie avant le
  // futur build?" right after selecting every channel by hand on her
  // phone - a safety net independent of the server sync (which she'd just
  // found broken). First tried clipboard copy/paste, but "le copier coller
  // texte depuis un mobile est super chiant" - a real file instead, saved
  // to wherever she picks (including a NAS share her boxes already mount),
  // reused the same FilePicker.saveFile pattern already proven for the
  // admin log viewer's export. Raw JSON preference strings, not the typed
  // models - a straight round trip, nothing to keep in sync if the models
  // change later.
  Future<void> _saveConfigToFile() async {
    final export = jsonEncode({
      'xtreamProviders': _prefs.get(UserPreferences.xtreamProviders),
      'xtreamSelectedCategoryIds': _prefs.get(
        UserPreferences.xtreamSelectedCategoryIds,
      ),
      'xtreamExcludedChannelIds': _prefs.get(
        UserPreferences.xtreamExcludedChannelIds,
      ),
      'm3uProviders': _prefs.get(UserPreferences.m3uProviders),
    });
    try {
      final path = await FilePicker.saveFile(
        dialogTitle: 'Enregistrer la configuration IPTV',
        fileName: 'moonfin_iptv_config.json',
        bytes: Uint8List.fromList(utf8.encode(export)),
      );
      if (!mounted) return;
      // Web hands the blob to the browser and always answers null, so null
      // only means cancelled everywhere else.
      if (path == null && !PlatformDetection.isWeb) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration IPTV enregistrée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Échec de l\'enregistrement: $e')),
      );
    }
  }

  Future<void> _loadConfigFromFile() async {
    try {
      final result = await FilePicker.pickFiles(
        dialogTitle: 'Charger une configuration IPTV',
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes == null) return;
      final decoded = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
      final xtreamProviders = decoded['xtreamProviders'];
      final xtreamSelectedCategoryIds = decoded['xtreamSelectedCategoryIds'];
      final xtreamExcludedChannelIds = decoded['xtreamExcludedChannelIds'];
      final m3uProviders = decoded['m3uProviders'];
      if (xtreamProviders is! String ||
          xtreamSelectedCategoryIds is! String ||
          xtreamExcludedChannelIds is! String ||
          m3uProviders is! String) {
        throw const FormatException('missing field');
      }
      await _prefs.set(UserPreferences.xtreamProviders, xtreamProviders);
      await _prefs.set(
        UserPreferences.xtreamSelectedCategoryIds,
        xtreamSelectedCategoryIds,
      );
      await _prefs.set(
        UserPreferences.xtreamExcludedChannelIds,
        xtreamExcludedChannelIds,
      );
      await _prefs.set(UserPreferences.m3uProviders, m3uProviders);
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration IPTV restaurée')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ce fichier ne contient pas une configuration IPTV valide: $e',
          ),
        ),
      );
    }
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
          IconButton(
            icon: const Icon(Icons.save_alt),
            tooltip: 'Enregistrer la configuration dans un fichier',
            onPressed: _saveConfigToFile,
          ),
          IconButton(
            icon: const Icon(Icons.file_open),
            tooltip: 'Charger une configuration depuis un fichier',
            onPressed: _loadConfigFromFile,
          ),
        ],
      ),
      body: _providers.isEmpty && _m3uProviders.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Aucun fournisseur IPTV configuré.\nAjoute-en un pour commencer.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text(
                    'Xtream Codes',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final provider in _providers)
                  ListTile(
                    title: Text(provider.name),
                    subtitle: Text(provider.baseUrl),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            XtreamCategoryPickerScreen(provider: provider),
                      ),
                    ),
                    onLongPress: () => _showProviderActions(provider),
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
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Ajouter un fournisseur Xtream'),
                  onTap: () => _openEditor(),
                ),
                const Divider(height: 32),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
                  child: Text(
                    'Listes M3U',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                for (final provider in _m3uProviders)
                  ListTile(
                    title: Text(provider.name),
                    subtitle: Text(
                      provider.epgUrl != null && provider.epgUrl!.isNotEmpty
                          ? '${provider.url}\nGuide EPG configuré'
                          : provider.url,
                    ),
                    isThreeLine:
                        provider.epgUrl != null && provider.epgUrl!.isNotEmpty,
                    onLongPress: () => _showM3uProviderActions(provider),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () =>
                              _openM3uEditor(existing: provider),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _deleteM3u(provider),
                        ),
                      ],
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: const Text('Ajouter une liste M3U'),
                  onTap: () => _openM3uEditor(),
                ),
              ],
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

/// 30.09, Sid: "un vrai lecteur iptv sera mieux que celui de moon basé sur
/// emby" - adding an M3U provider had no UI at all before this (the
/// preference storage and M3uRepository parser already existed, nothing
/// ever called addOrUpdateM3uProvider). The optional EPG guide URL is what
/// lets XtreamChannelsScreen match this provider's channels against a real
/// XMLTV feed instead of showing no programme info at all (see
/// EpgChannelMatcher) - most public M3U playlists ship without one, so it's
/// deliberately not required.
class _M3uProviderEditorDialog extends StatefulWidget {
  final M3uProvider? existing;

  const _M3uProviderEditorDialog({this.existing});

  @override
  State<_M3uProviderEditorDialog> createState() =>
      _M3uProviderEditorDialogState();
}

class _M3uProviderEditorDialogState extends State<_M3uProviderEditorDialog> {
  late final _nameController = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late final _urlController = TextEditingController(
    text: widget.existing?.url ?? '',
  );
  late final _epgUrlController = TextEditingController(
    text: widget.existing?.epgUrl ?? '',
  );

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    _epgUrlController.dispose();
    super.dispose();
  }

  M3uProvider _buildProvider() {
    final epgUrl = _epgUrlController.text.trim();
    return M3uProvider(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      url: _urlController.text.trim(),
      epgUrl: epgUrl.isEmpty ? null : epgUrl,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'Ajouter une liste M3U'
            : 'Modifier la liste M3U',
      ),
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
                labelText: 'URL de la playlist M3U',
                hintText: 'http://exemple.com/playlist.m3u',
              ),
              keyboardType: TextInputType.url,
            ),
            TextField(
              controller: _epgUrlController,
              decoration: const InputDecoration(
                labelText: 'URL du guide XMLTV (optionnel)',
                hintText: 'http://exemple.com/epg.xml',
              ),
              keyboardType: TextInputType.url,
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
                _urlController.text.trim().isEmpty) {
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
  // 30.09, Sid: "une fois les groupes choisis... un moyen de choisir les
  // chaînes aussi, qui se dérouleraient en dessous des groupes" - stored as
  // an exclusion set (see setXtreamChannelExcluded's own comment): a
  // channel not in here stays included, so ticking a category still means
  // "everything in it" until she hides a specific one.
  late Set<String> _excludedChannelIds;
  final Map<String, List<XtreamChannel>> _channelsByCategory = {};
  final Set<String> _loadingCategoryChannels = {};
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _selected = _prefs
        .getXtreamSelectedCategoryIds()[widget.provider.id]
        ?.toSet() ??
        {};
    _excludedChannelIds = _prefs
        .getXtreamExcludedChannelIds()[widget.provider.id]
        ?.toSet() ??
        {};
    _load();
  }

  Future<void> _load() async {
    final categories = await _repo.getLiveCategories(widget.provider);
    if (!mounted) return;
    setState(() => _categories = categories);
    for (final categoryId in _selected) {
      unawaited(_loadChannelsForCategory(categoryId));
    }
  }

  Future<void> _loadChannelsForCategory(String categoryId) async {
    if (_channelsByCategory.containsKey(categoryId) ||
        _loadingCategoryChannels.contains(categoryId)) {
      return;
    }
    setState(() => _loadingCategoryChannels.add(categoryId));
    final channels = await _repo.getLiveStreams(
      widget.provider,
      categoryId: categoryId,
    );
    if (!mounted) return;
    setState(() {
      _channelsByCategory[categoryId] = channels;
      _loadingCategoryChannels.remove(categoryId);
    });
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
    if (value) {
      unawaited(_loadChannelsForCategory(categoryId));
    }
  }

  Future<void> _toggleChannel(String streamId, bool included) async {
    setState(() {
      if (included) {
        _excludedChannelIds.remove(streamId);
      } else {
        _excludedChannelIds.add(streamId);
      }
    });
    await _prefs.setXtreamChannelExcluded(
      widget.provider.id,
      streamId,
      !included,
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
                final isSelected = _selected.contains(category.id);
                final channels = _channelsByCategory[category.id];
                final loadingChannels =
                    _loadingCategoryChannels.contains(category.id);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CheckboxListTile(
                      title: Text(category.name),
                      value: isSelected,
                      onChanged: (v) => _toggle(category.id, v ?? false),
                    ),
                    if (isSelected && loadingChannels)
                      const Padding(
                        padding: EdgeInsets.only(left: 32, bottom: 8),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    if (isSelected && !loadingChannels && channels != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: Column(
                          children: [
                            for (final channel in channels)
                              CheckboxListTile(
                                dense: true,
                                title: Text(channel.name),
                                value: !_excludedChannelIds
                                    .contains(channel.streamId.toString()),
                                onChanged: (v) => _toggleChannel(
                                  channel.streamId.toString(),
                                  v ?? true,
                                ),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
