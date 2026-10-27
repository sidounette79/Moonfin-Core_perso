import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Result of a manual Shorebird patch check/apply, for the UI to render.
enum ShorebirdCheckResult {
  /// Not a Shorebird-built release (e.g. local debug run) - the updater
  /// itself is unavailable, nothing to check.
  unavailable,

  /// Already on the latest patch, nothing downloaded.
  upToDate,

  /// A new patch was found and downloaded. A restart is required to apply
  /// it - this package has no in-process restart, unlike the older
  /// ShorebirdCodePush v1 API.
  patchDownloaded,

  /// A patch was already downloaded on a previous check and is waiting for
  /// a restart (no new network check needed to see that).
  restartRequired,

  /// The check or download failed (network error, etc).
  failed,
}

/// Thin wrapper around [ShorebirdUpdater] so the UI/tests don't depend on
/// the package's API shape directly. 27.10, Sid ("on doit créer le bouton
/// pour pouvoir manuellement lancer la màj OTA"): the existing "check for
/// updates" tile only talks to the upstream Moonfin-Client GitHub releases,
/// which has nothing to do with this fork's Shorebird patches.
class ShorebirdUpdateService {
  ShorebirdUpdateService([ShorebirdUpdater? updater])
      : _updater = updater ?? ShorebirdUpdater();

  final ShorebirdUpdater _updater;

  bool get isAvailable => _updater.isAvailable;

  /// Patch number currently running, or null if unavailable/none installed.
  Future<int?> currentPatchNumber() async {
    if (!_updater.isAvailable) return null;
    try {
      return (await _updater.readCurrentPatch())?.number;
    } catch (_) {
      return null;
    }
  }

  /// Checks for a new patch and downloads it if one is available.
  Future<ShorebirdCheckResult> checkAndDownload() async {
    if (!_updater.isAvailable) return ShorebirdCheckResult.unavailable;

    try {
      final status = await _updater.checkForUpdate();
      switch (status) {
        case UpdateStatus.unavailable:
          return ShorebirdCheckResult.unavailable;
        case UpdateStatus.upToDate:
          return ShorebirdCheckResult.upToDate;
        case UpdateStatus.restartRequired:
          return ShorebirdCheckResult.restartRequired;
        case UpdateStatus.outdated:
          await _updater.update();
          return ShorebirdCheckResult.patchDownloaded;
      }
    } catch (_) {
      return ShorebirdCheckResult.failed;
    }
  }
}
