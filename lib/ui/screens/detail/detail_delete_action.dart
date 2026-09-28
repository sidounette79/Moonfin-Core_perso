import 'dart:async';

import 'package:flutter/material.dart';
import 'package:moonfin_design/moonfin_design.dart';

import '../../../data/models/aggregated_item.dart';
import '../../../data/viewmodels/item_detail_view_model.dart';
import '../../../l10n/app_localizations.dart';
import '../../navigation/app_router.dart';
import '../../navigation/destinations.dart';
import '../../navigation/home_refresh_bus.dart';
import '../../widgets/adaptive/adaptive_dialog.dart';
import '../../widgets/overlay_sheet.dart';

// 28.09, Sid: the classic detail screen (item_detail_screen.dart) already
// had this exact flow for albums/playlists - shared here so the Modern
// style (modern_detail_content.dart) can offer the same "Delete" button on
// movies/episodes without duplicating the confirmation dialog + background
// delete + snackbar logic across two already-huge files.

const _destructiveRed = Color(0xFFD32F2F);
const _destructiveRedDim = Color(0xFFB71C1C);

String _deleteFailureMessage(
  AppLocalizations l10n,
  DeleteItemFailure failure, {
  required bool isPlaylist,
}) {
  if (failure.statusCode == 401 || failure.statusCode == 403) {
    return l10n.requestErrorPermission;
  }
  final detail = failure.detail;
  if (detail == null || detail.isEmpty) {
    return isPlaylist ? l10n.failedToDeletePlaylist : l10n.failedToDeleteItem;
  }
  return l10n.failedToDeleteItemWithError(detail);
}

void _deleteItemInBackground(
  ItemDetailViewModel viewModel, {
  required bool isPlaylist,
}) {
  unawaited(
    viewModel.deleteItem().then((failure) {
      if (failure == null) {
        homeRefreshBus.requestNowOrAfterNavigation();
      }

      final activeContext =
          appRouter.routerDelegate.navigatorKey.currentContext;
      if (activeContext == null || !activeContext.mounted) return;
      final l10n = AppLocalizations.of(activeContext);

      ScaffoldMessenger.of(activeContext).showSnackBar(
        failure == null
            ? SnackBar(content: Text(l10n.itemDeleted))
            : SnackBar(
                content: Text(
                  _deleteFailureMessage(l10n, failure, isPlaylist: isPlaylist),
                ),
                backgroundColor: _destructiveRed,
              ),
      );
    }),
  );
}

Future<bool> _showDeleteConfirmationDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final confirmed = await showFocusRestoringDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog.adaptive(
      backgroundColor: const Color(0xFF171717),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      content: Text(message, style: const TextStyle(color: Colors.white70)),
      actions: [
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          focusRingColor: AppColorScheme.accent,
          child: Text(AppLocalizations.of(ctx).cancel),
        ),
        adaptiveDialogAction(
          onPressed: () => Navigator.pop(ctx, true),
          isDestructive: true,
          backgroundColor: _destructiveRedDim,
          focusedBackgroundColor: _destructiveRed,
          child: Text(
            AppLocalizations.of(ctx).delete,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}

/// Confirms, then deletes [item] from the server and navigates home.
/// [viewModel] is the item's own ItemDetailViewModel (used for both styles).
Future<void> confirmDeleteServerItem(
  BuildContext context,
  ItemDetailViewModel viewModel,
  AggregatedItem item,
) async {
  final l10n = AppLocalizations.of(context);
  final isPlaylist = item.type == 'Playlist';
  final confirmed = await _showDeleteConfirmationDialog(
    context,
    title: isPlaylist ? l10n.deletePlaylist : l10n.deleteItem,
    message: isPlaylist ? l10n.deletePlaylistMessage : l10n.deleteItemMessage,
  );
  if (!confirmed) return;

  appRouter.go(Destinations.home);
  _deleteItemInBackground(viewModel, isPlaylist: isPlaylist);
}
