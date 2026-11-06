import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import '../../preference/remote_control_preferences.dart';
import 'remote_control_shared.dart';

// 06.11, Sid ("un onglet purement telecommande, accessible depuis la page
// d'accueil avec 3 boutons pour les trois TV en haut"): the bottom-sheet
// dialog (remote_control_dialog.dart) lists every controllable session,
// which is the right tool from the account menu but too much friction for
// "I just want to point at TV1 and hit the D-pad" - this is a dedicated
// full screen instead, opened the same way Settings is (SettingsPanel.open,
// see home_screen.dart), with a fixed row of up to 3 chosen TVs instead of
// a scrollable session list. Reuses every actual control (D-pad, transport,
// volume) from RemoteControlSessionMixin - only the header/selector differs.
//
// The 3 targets are a one-time, user-picked choice (RemoteControlPreferences),
// not guessed from the client name - a plain "is this a TV" heuristic
// doesn't hold here: one of her 3 picks ("TV BOX BOUBOU") still runs the
// stock Emby Android client, CarbaTV not installed on it yet.
class RemoteControlScreen extends StatefulWidget {
  const RemoteControlScreen({super.key});

  @override
  State<RemoteControlScreen> createState() => _RemoteControlScreenState();
}

class _RemoteControlScreenState extends State<RemoteControlScreen>
    with RemoteControlSessionMixin {
  late final RemoteControlPreferences _prefs;
  List<RemoteControlTarget> _targets = const [];
  bool _configuring = false;
  final Set<String> _pendingSelection = {};

  @override
  void initState() {
    super.initState();
    _prefs = GetIt.instance<RemoteControlPreferences>();
    _targets = _prefs.targets;
    _configuring = _targets.isEmpty;
    initRemoteControlSession();
  }

  @override
  void dispose() {
    disposeRemoteControlSession();
    super.dispose();
  }

  void _startConfiguring() {
    setState(() {
      _configuring = true;
      _pendingSelection
        ..clear()
        ..addAll(_targets.map((t) => t.deviceId));
    });
  }

  void _toggleCandidate(Map<String, dynamic> session) {
    final id = session['DeviceId']?.toString();
    if (id == null || id.isEmpty) return;
    setState(() {
      if (_pendingSelection.contains(id)) {
        _pendingSelection.remove(id);
      } else if (_pendingSelection.length < RemoteControlPreferences.maxTargets) {
        _pendingSelection.add(id);
      }
    });
  }

  Future<void> _saveSelection() async {
    final chosen = <RemoteControlTarget>[];
    for (final id in _pendingSelection) {
      final session = sessions.firstWhere(
        (s) => s['DeviceId']?.toString() == id,
        orElse: () => const {},
      );
      final name = session['DeviceName'] as String? ?? id;
      chosen.add(RemoteControlTarget(deviceId: id, deviceName: name));
    }
    await _prefs.setTargets(chosen);
    if (!mounted) return;
    setState(() {
      _targets = chosen;
      _configuring = false;
      selectSession(null);
    });
  }

  /// Each target's live session, when that TV currently has one - null means
  /// it's off/CarbaTV not running there, not that the pick was wrong.
  Map<String, dynamic>? _liveSessionFor(RemoteControlTarget target) {
    for (final s in sessions) {
      if (s['DeviceId']?.toString() == target.deviceId) return s;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        title: Text(l10n.remoteControlTitle),
        actions: [
          if (busy)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (!_configuring && _targets.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.edit_rounded),
              tooltip: l10n.remoteEditTvs,
              onPressed: _startConfiguring,
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    l10n.remoteFailedToLoadSessions,
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  TextButton(onPressed: loadSessions, child: Text(l10n.retry)),
                ],
              ),
            )
          : _configuring
          ? _buildConfiguration(theme, l10n)
          : _buildQuickControl(theme, l10n),
    );
  }

  Widget _buildConfiguration(ThemeData theme, AppLocalizations l10n) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            l10n.remoteChooseTvs(RemoteControlPreferences.maxTargets),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ),
        Expanded(
          child: sessions.isEmpty
              ? Center(
                  child: Text(
                    l10n.remoteNoSessions,
                    style: theme.textTheme.bodyMedium,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  children: sessions.map((s) {
                    final id = s['DeviceId']?.toString();
                    final checked = id != null && _pendingSelection.contains(id);
                    final name = s['DeviceName'] as String? ?? '?';
                    final client = s['Client'] as String? ?? '';
                    final disabled = !checked &&
                        _pendingSelection.length >= RemoteControlPreferences.maxTargets;
                    return CheckboxListTile(
                      value: checked,
                      onChanged: disabled || id == null
                          ? null
                          : (_) => _toggleCandidate(s),
                      title: Text(name),
                      subtitle: Text(client, style: theme.textTheme.bodySmall),
                      secondary: platformIcon(client, theme),
                    );
                  }).toList(),
                ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _pendingSelection.isEmpty ? null : _saveSelection,
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickControl(ThemeData theme, AppLocalizations l10n) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        Row(
          children: [
            for (final target in _targets) ...[
              Expanded(child: _buildTvButton(theme, target)),
              if (target != _targets.last) const SizedBox(width: 10),
            ],
          ],
        ),
        const SizedBox(height: 24),
        if (selectedSession != null)
          ...buildRemoteControls(theme)
        else
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Text(
                l10n.remoteSelectATv,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTvButton(ThemeData theme, RemoteControlTarget target) {
    final live = _liveSessionFor(target);
    final isOnline = live != null;
    final isSelected = isOnline && selectedSession?['Id'] == live['Id'];
    final nowPlaying = live?['NowPlayingItem'] as Map<String, dynamic>?;

    return Material(
      color: isSelected
          ? theme.colorScheme.primaryContainer
          : theme.colorScheme.surfaceContainerHighest.withValues(
              alpha: isOnline ? 0.4 : 0.2,
            ),
      borderRadius: AppRadius.circular(16),
      child: InkWell(
        borderRadius: AppRadius.circular(16),
        onTap: isOnline
            ? () => selectSession(isSelected ? null : live)
            : null,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: AppRadius.circular(16),
            border: Border.all(
              color: isSelected
                  ? theme.colorScheme.primary.withValues(alpha: 0.6)
                  : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.tv_rounded,
                color: isSelected
                    ? theme.colorScheme.onPrimaryContainer
                    : isOnline
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.outline,
                size: 24,
              ),
              const SizedBox(height: 6),
              Text(
                target.deviceName,
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: isSelected
                      ? theme.colorScheme.onPrimaryContainer
                      : isOnline
                      ? theme.colorScheme.onSurfaceVariant
                      : theme.colorScheme.outline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              if (!isOnline)
                Text(
                  AppLocalizations.of(context).remoteOffline,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.outline,
                  ),
                )
              else if (nowPlaying != null)
                Icon(Icons.circle, size: 6, color: theme.colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
