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

/// Everything here is on top of the release tagged "2.6.3" (27.10 07h52 -
/// needed one reinstall, the current OTA base). 28.10: that tag name was
/// actually wrong - pubspec.yaml at that commit still said `version:
/// 2.6.2`, confirmed by the built APK's own manifest (`carba24.apk`,
/// byte-identical to the server build). The real version is 2.6.2, not
/// 2.6.3 - keep that in mind if comparing against an installed app's
/// displayed version.
///
/// 28.10, tag "2.6.4": a real release, not a patch - restart_app ships
/// native Android code, which Shorebird's Dart-only patches can't add to
/// an already-installed APK. Needs the one-time reinstall like 2.6.3 did;
/// this becomes the new OTA base going forward. Verified this tag name
/// actually matches `version:` in pubspec.yaml before pushing it, unlike
/// last time.
const otaChangelog = [
  OtaChangelogEntry(
    date: '28.10',
    title:
        'Patch OTA : bouton "Redémarrer maintenant" après téléchargement '
        'd\'un patch - plus besoin de fermer/rouvrir l\'app à la main '
        '(redémarrage natif du processus). Nécessite cette réinstallation '
        'une fois (code natif ajouté), les patchs suivants redeviendront '
        'normaux.',
  ),
  OtaChangelogEntry(
    date: '28.10',
    title:
        'Lecteur : lien "Apparence des sous-titres" dans le sélecteur de '
        'piste (comme Emby), ouvre l\'écran de personnalisation existant.',
  ),
  OtaChangelogEntry(
    date: '28.10',
    title:
        'Lecteur : la barre ne garde plus que sous-titres/audio/chapitres '
        'directement visibles - tout le reste (vitesse, zoom, cast, info...) '
        'est maintenant regroupé dans le bouton réglages (comme Emby).',
  ),
  OtaChangelogEntry(
    date: '28.10',
    title: 'Diagnostics : nouveau bouton "Send report to NAS", envoi direct '
        'via Tailscale, en plus de l\'envoi serveur existant.',
  ),
  OtaChangelogEntry(
    date: '28.10 07h10',
    title:
        'Réglages > À propos nettoyé : retiré tout ce qui pointait vers le '
        'projet Moonfin amont (vérif de mise à jour GitHub, lien code '
        'source, signaler un problème, Discord, soutenir Moonfin, licences, '
        'politique de confidentialité, bandeau de mise à jour flottant) + '
        'logo remplacé par celui de CARBA TV.',
  ),
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
