import 'language_codes.dart';

bool languageMatchesPreferred(
  String? streamLanguage,
  String preferredNormalized,
  String preferredIso3,
) {
  final stream = normalizeLanguage(streamLanguage);
  if (stream.isEmpty || preferredNormalized.isEmpty) {
    return false;
  }
  if (stream == preferredNormalized) {
    return true;
  }

  final stream3 = toIso3Language(stream);
  return stream3.isNotEmpty && stream3 == preferredIso3;
}

String normalizeLanguage(String? language) {
  if (language == null) {
    return '';
  }
  final normalized = language.trim().toLowerCase();
  if (normalized.isEmpty) {
    return '';
  }
  return normalized.split(RegExp(r'[-_]')).first;
}

/// Canonicalizes to the ISO 639-2/B (bibliographic) code - the one real
/// media files and Emby/Jellyfin actually use - so a stored preference
/// (which keeps the /T code [kIso6391To6392] maps 2-letter codes to) still
/// matches a stream tagged with its /B equivalent. See
/// [kIso6392TerminologicalToBibliographic]'s own comment for the story.
String toIso3Language(String language) {
  final iso3 = language.length == 3
      ? language
      : (kIso6391To6392[language] ?? language);
  return kIso6392TerminologicalToBibliographic[iso3] ?? iso3;
}
