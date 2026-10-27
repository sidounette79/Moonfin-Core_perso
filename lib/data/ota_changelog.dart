/// One entry in the hand-maintained OTA changelog shown in
/// Réglages > À propos > Patch OTA.
///
/// 27.10, Sid ("il faudrait un endroit ou je vois de quelle OTA il s'agit
/// avec un truc clair pour toi comme pour moi. Date et heure + modif
/// principale peut etre ?"): update this list every time a patch is pushed
/// to carba-tv-changes, newest entry first, so both of us can tell which
/// fix actually landed on a given install without guessing from a bare
/// patch number.
class OtaChangelogEntry {
  final String date;
  final String title;

  const OtaChangelogEntry({required this.date, required this.title});
}

/// Everything here is on top of the 2.6.3 release (real release, tag
/// pushed 27.10 07h52 - needed one reinstall, the current OTA base).
const otaChangelog = [
  OtaChangelogEntry(
    date: '27.10 15h32',
    title:
        'Sous-titres : le mode "Langue étrangère" active enfin les pistes '
        'forcées quand l\'audio est déjà dans la langue préférée (ex: passage '
        'en langue étrangère au milieu d\'un film).',
  ),
  OtaChangelogEntry(
    date: '27.10 09h56',
    title:
        'Fiche série : saison correctement affichée + rangée de boutons '
        'accessible sans scroll sur mobile.',
  ),
  OtaChangelogEntry(
    date: '27.10 07h52',
    title: 'Base de la version 2.6.3 (vraie release, réinstallation faite).',
  ),
];
