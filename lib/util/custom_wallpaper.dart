import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';

import '../preference/user_preferences.dart';

/// 30.10, Sid ("comme dans Meelo, le choix de wallpaper perso... pour
/// remplacer quand j'ai le fond tout noir") - a single local, device-only
/// wallpaper (no server sync, same as Meelo's own version), shown by
/// FullscreenBackdropSwitcher only as a fallback wherever a screen has no
/// real backdrop of its own ("il se fait recouvrir quand y a une vraie
/// affiche" - confirmed that's the wanted behavior).
///
/// Every pick gets its own timestamped filename rather than overwriting a
/// fixed one - Meelo hit exactly this bug once already (its own
/// wallpaper-preferences.ts, 15.09 comment): image caches are keyed by
/// URI, so overwriting a fixed filename in place kept showing the OLD
/// bitmap until the cache was cleared by hand. The previous file is
/// deleted once the new one is safely in place.
class CustomWallpaper {
  CustomWallpaper._();

  static Future<Directory> _directory() async {
    final supportDir = await getApplicationSupportDirectory();
    final wallpaperDir = Directory('${supportDir.path}/custom_wallpaper');
    if (!await wallpaperDir.exists()) {
      await wallpaperDir.create(recursive: true);
    }
    return wallpaperDir;
  }

  /// Opens the native file picker, copies the chosen image into app
  /// storage and updates the preference. Returns the new path, or null if
  /// the user cancelled or picked something unreadable.
  static Future<String?> pickAndStore() async {
    // FileType.custom + allowedExtensions, not FileType.image - matches
    // the already-proven pattern in admin_branding_screen.dart rather than
    // assuming a shortcut enum value exists in this file_picker version.
    final result = await FilePicker.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'],
      withData: false,
    );

    final pickedPath = result?.files.singleOrNull?.path;

    if (pickedPath == null) {
      return null;
    }

    final sourceFile = File(pickedPath);

    if (!await sourceFile.exists()) {
      return null;
    }

    final extension = pickedPath.contains('.')
        ? pickedPath.substring(pickedPath.lastIndexOf('.'))
        : '.jpg';

    final dir = await _directory();
    final destPath =
        '${dir.path}/wallpaper-${DateTime.now().millisecondsSinceEpoch}$extension';

    await sourceFile.copy(destPath);

    final prefs = GetIt.instance<UserPreferences>();
    final previousPath = prefs.get(UserPreferences.customWallpaperPath);

    await prefs.set(UserPreferences.customWallpaperPath, destPath);

    if (previousPath.isNotEmpty && previousPath != destPath) {
      final previousFile = File(previousPath);
      if (await previousFile.exists()) {
        unawaited(previousFile.delete());
      }
    }

    return destPath;
  }

  /// Clears the preference and deletes the stored file, if any.
  static Future<void> clear() async {
    final prefs = GetIt.instance<UserPreferences>();
    final path = prefs.get(UserPreferences.customWallpaperPath);

    await prefs.set(UserPreferences.customWallpaperPath, '');

    if (path.isEmpty) {
      return;
    }

    final file = File(path);
    if (await file.exists()) {
      unawaited(file.delete());
    }
  }

  /// The currently stored wallpaper path, or null if none is set or the
  /// file has gone missing since (moved/cleared storage).
  static String? currentPath() {
    final prefs = GetIt.instance<UserPreferences>();
    final path = prefs.get(UserPreferences.customWallpaperPath);

    if (path.isEmpty || !File(path).existsSync()) {
      return null;
    }

    return path;
  }
}
