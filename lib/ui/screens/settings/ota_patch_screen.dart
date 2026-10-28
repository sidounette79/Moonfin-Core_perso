import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';
import 'package:restart_app/restart_app.dart';

import '../../../data/ota_changelog.dart';
import '../../../data/services/shorebird_update_service.dart';
import '../../../l10n/app_localizations.dart';
import '../../widgets/focus/request_initial_focus.dart';
import '../../widgets/settings/clean_settings_typography.dart';
import 'settings_app_bar.dart';

/// 27.10, Sid: manual OTA check/apply button (the existing "check for
/// updates" tile only compares against upstream GitHub releases, nothing to
/// do with this fork's Shorebird patches) plus a hand-maintained changelog
/// so a given install's patch state is never a guessing game for either of
/// us.
class OtaPatchScreen extends StatefulWidget {
  const OtaPatchScreen({super.key});

  @override
  State<OtaPatchScreen> createState() => _OtaPatchScreenState();
}

class _OtaPatchScreenState extends State<OtaPatchScreen> {
  ShorebirdUpdateService get _service =>
      GetIt.instance<ShorebirdUpdateService>();

  int? _currentPatch;
  bool _loadingPatch = true;
  bool _checking = false;
  bool _restartNeeded = false;
  bool _restarting = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentPatch();
  }

  Future<void> _loadCurrentPatch() async {
    final patch = await _service.currentPatchNumber();
    if (!mounted) return;
    setState(() {
      _currentPatch = patch;
      _loadingPatch = false;
    });
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final result = await _service.checkAndDownload();
    if (!mounted) return;
    final needsRestart = result == ShorebirdCheckResult.patchDownloaded ||
        result == ShorebirdCheckResult.restartRequired;
    setState(() {
      _checking = false;
      _restartNeeded = _restartNeeded || needsRestart;
    });

    final l10n = AppLocalizations.of(context);
    final message = switch (result) {
      ShorebirdCheckResult.unavailable => l10n.otaPatchUnavailable,
      ShorebirdCheckResult.upToDate =>
        l10n.otaPatchUpToDate(_currentPatch ?? 0),
      ShorebirdCheckResult.patchDownloaded => l10n.otaPatchDownloaded,
      ShorebirdCheckResult.restartRequired => l10n.otaPatchRestartRequired,
      ShorebirdCheckResult.failed => l10n.otaPatchCheckFailed,
    };
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));

    // A fresh download bumps readCurrentPatch() only after restart, but
    // readNextPatch() via currentPatchNumber() still reflects what's running
    // now - re-read anyway in case a restart happened between checks.
    await _loadCurrentPatch();
  }

  Future<void> _restartNow() async {
    setState(() => _restarting = true);
    final result = await Restart.restartApp(
      mode: RestartMode.process,
      forceKill: true,
    );
    if (!mounted) return;
    if (!result.success) {
      // A true process restart failing is rare but not impossible (OEM
      // quirks, etc.) - surface it instead of silently doing nothing, Sid
      // still has the "close and reopen by hand" fallback either way.
      setState(() => _restarting = false);
      final l10n = AppLocalizations.of(context);
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(content: Text(result.message ?? l10n.otaPatchCheckFailed)),
        );
    }
    // On success the process is being torn down right now - nothing left to
    // update in this widget.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return RequestInitialFocus(
      child: withCleanSettingsTypography(
        context,
        Scaffold(
          appBar: buildSettingsAppBar(context, Text(l10n.settingsCheckForOtaPatch)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _loadingPatch
                            ? '…'
                            : _currentPatch != null
                                ? l10n.settingsCheckForOtaPatchSubtitleWithPatch(
                                    _currentPatch!,
                                  )
                                : l10n.settingsCheckForOtaPatchSubtitleNoPatch,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: _checking ? null : _check,
                        icon: _checking
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.system_update_alt),
                        label: Text(l10n.settingsCheckForOtaPatch),
                      ),
                      if (_restartNeeded) ...[
                        const SizedBox(height: 8),
                        FilledButton.tonalIcon(
                          onPressed: _restarting ? null : _restartNow,
                          icon: _restarting
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.restart_alt),
                          label: Text(l10n.otaPatchRestartNow),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  'Historique',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const SizedBox(height: 8),
              for (final entry in otaChangelog)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(entry.title),
                    subtitle: Text(entry.date),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
