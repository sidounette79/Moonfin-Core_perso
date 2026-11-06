import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../l10n/app_localizations.dart';
import 'overlay_sheet.dart';
import 'remote_control_shared.dart';

void showRemoteControlDialog(BuildContext context) {
  showFocusRestoringModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _RemoteControlSheet(),
  );
}

class _RemoteControlSheet extends StatefulWidget {
  const _RemoteControlSheet();

  @override
  State<_RemoteControlSheet> createState() => _RemoteControlSheetState();
}

class _RemoteControlSheetState extends State<_RemoteControlSheet>
    with RemoteControlSessionMixin {
  @override
  void initState() {
    super.initState();
    initRemoteControlSession();
  }

  @override
  void dispose() {
    disposeRemoteControlSession();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 10),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: AppRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Icon(
                    Icons.settings_remote_rounded,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l10n.remoteControlTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  if (busy)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: loading
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
                          TextButton(
                            onPressed: loadSessions,
                            child: Text(l10n.retry),
                          ),
                        ],
                      ),
                    )
                  : sessions.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.devices_other,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            l10n.remoteNoSessions,
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            l10n.remoteStartPlayback,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      children: [
                        ...sessions.map(_buildSessionTile),
                        if (selectedSession != null) ...[
                          const SizedBox(height: 16),
                          ...buildRemoteControls(theme),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionTile(Map<String, dynamic> session) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final sessionId = session['Id']?.toString();
    final isSelected = selectedSession?['Id'] == sessionId;
    final userName = session['UserName'] as String? ?? l10n.unknownUser;
    final client = session['Client'] as String? ?? '';
    final device = session['DeviceName'] as String? ?? '';
    final nowPlaying = session['NowPlayingItem'] as Map<String, dynamic>?;
    final playState = session['PlayState'] as Map<String, dynamic>?;
    final isPaused = playState?['IsPaused'] as bool? ?? false;
    final runTimeTicks = (nowPlaying?['RunTimeTicks'] as num?)?.toDouble() ?? 0;
    final positionTicks =
        (playState?['PositionTicks'] as num?)?.toDouble() ?? 0;
    final progress = (nowPlaying != null && runTimeTicks > 0)
        ? (positionTicks / runTimeTicks).clamp(0.0, 1.0)
        : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.35)
            : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: AppRadius.circular(14),
        child: InkWell(
          borderRadius: AppRadius.circular(14),
          onTap: () => selectSession(isSelected ? null : session),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: AppRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? theme.colorScheme.primary.withValues(alpha: 0.6)
                    : theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: isSelected ? 1.5 : 1,
              ),
            ),
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: theme.colorScheme.primaryContainer,
                      child: Text(
                        userName.isNotEmpty ? userName[0].toUpperCase() : '?',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  userName,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              platformIcon(client, theme),
                            ],
                          ),
                          Text(
                            nowPlaying != null
                                ? (nowPlaying['Name'] as String? ??
                                      l10n.unknownItem)
                                : '$client · $device',
                            style: theme.textTheme.bodySmall,
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ],
                      ),
                    ),
                    if (nowPlaying != null)
                      Icon(
                        isPaused
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        size: 20,
                        color: isPaused
                            ? theme.colorScheme.outline
                            : theme.colorScheme.primary,
                      ),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: Icon(
                          Icons.check_circle,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                  ],
                ),
                if (progress != null) ...[
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.only(left: 42),
                    child: ClipRRect(
                      borderRadius: AppRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 3,
                        backgroundColor:
                            theme.colorScheme.surfaceContainerHighest,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
