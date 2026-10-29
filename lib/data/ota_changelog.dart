/// One entry in the hand-maintained OTA changelog shown in
/// Réglages > À propos > Patch OTA.
///
/// 27.10, Sid ("il faudrait un endroit ou je vois de quelle OTA il s'agit
/// avec un truc clair pour toi comme pour moi. Date et heure + modif
/// principale peut etre ?"): update this list every time a patch is pushed
/// to carba-tv-changes, newest entry first, so both of us can tell which
/// fix actually landed on a given install without guessing from a bare
/// patch number.
///
/// 28.10, Sid ("si on pouvait avoir l'heure en plus de la date et le
/// numéro du patch ça serait top") - date ALWAYS includes the time now
/// (`dd.mm HHhMM`), and patchNumber gets filled in once the commit's own
/// patch actually publishes (check the GitHub Actions run's "Published
/// Patch" log line - several commits pushed back to back never publish
/// their own patch, only the last one of a batch does, so those share that
/// batch's number once it lands).
class OtaChangelogEntry {
  final String date;
  final String title;

  /// 28.10, Sid ("si on pouvait avoir l'heure en plus de la date et le
  /// numéro du patch ça serait top") - null when the entry's own patch
  /// hasn't actually published yet (pushing another commit before a patch
  /// publishes cancels it - several of 28.10's commits never shipped their
  /// own patch, only the last one of a batch does, bundling everything
  /// since the previous published patch).
  ///
  /// This is the MOBILE flavor's number - build-android.sh always publishes
  /// mobile before androidTv in the same run, so TV's own number for the
  /// same patch is consistently this minus 1 (confirmed 28.10 22h: mobile
  /// 13 / TV 12). Not worth a second field for a number this derivable.
  final int? patchNumber;

  const OtaChangelogEntry({
    required this.date,
    required this.title,
    this.patchNumber,
  });
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
    date: '29.10',
    title: 'Accueil : grille "Mes bibliothèques" - chevauchement/espaces '
        'vides au dépliage/repliage corrigés (cache de hauteur pas '
        'resynchronisé), chevron désormais atteignable au D-pad TV depuis '
        'la première ligne de la grille.',
  ),
  OtaChangelogEntry(
    date: '29.10',
    title: 'Vignettes : une image qui échouait à charger (juste après la '
        'lecture par exemple) restait noire définitivement - un seul '
        'nouvel essai automatique après un court délai, avant de retomber '
        'sur l\'icône de remplacement.',
  ),
  OtaChangelogEntry(
    date: '29.10',
    title: 'Lecture : longue attente/blocage au lancement d\'un épisode en '
        'EAC3 multicanal sur enceinte Bluetooth - la sonde de capacités '
        'audio annonçait le passthrough EAC3/AC3/DTS/TrueHD disponible en '
        'Bluetooth (jamais vrai en pratique), la vraie tentative échouait '
        'et retentait plusieurs fois avant d\'abandonner en stéréo. '
        'Nécessite une réinstallation (code natif Android).',
  ),
  OtaChangelogEntry(
    date: '28.10 22h40',
    patchNumber: 13,
    title: 'Bibliothèque : le bouton tous/vu/non-vu perdait le focus après '
        'chaque bascule (fallait remonter au D-pad pour re-toggler).',
  ),
  OtaChangelogEntry(
    date: '28.10 22h34',
    patchNumber: 13,
    title: 'Accueil : chevron pour replier "Voir plus" des bibliothèques - '
        'le geste de retour natif ne le fermait pas, obligeant à sortir de '
        'l\'app.',
  ),
  OtaChangelogEntry(
    date: '28.10 22h22',
    patchNumber: 13,
    title: 'Fond d\'écran : ne restait plus noir au retour d\'une fiche '
        'série/détail quand la sélection n\'avait pas changé (accueil et '
        'grille de bibliothèque).',
  ),
  OtaChangelogEntry(
    date: '28.10 22h18',
    patchNumber: 13,
    title: 'Réglages bibliothèques/studios : bouton Enregistrer mis en '
        'avant (gros bouton), Tout sélectionner réduit en dessous.',
  ),
  OtaChangelogEntry(
    date: '28.10 22h14',
    patchNumber: 13,
    title: 'Réglages bibliothèques/studios : les cases à cocher ne '
        'répondaient plus au D-pad TV (fonctionnaient seulement au tactile).',
  ),
  OtaChangelogEntry(
    date: '28.10 22h10',
    patchNumber: 13,
    title: 'Accueil : grille "Mes bibliothèques" - espacement des tuiles au '
        'focus et saut D-pad BAS en diagonale corrigés.',
  ),
  OtaChangelogEntry(
    date: '28.10 21h59',
    patchNumber: 13,
    title: 'Diagnostics : "Send report to NAS" essaie maintenant l\'IP du '
        'réseau local en premier (marche depuis la TV, pas seulement le '
        'téléphone via Tailscale).',
  ),
  OtaChangelogEntry(
    date: '28.10 21h39',
    patchNumber: 13,
    title: 'Accueil : tuiles "Mes bibliothèques" rectangulaires, titre en '
        'dessous comme Continuer à regarder (au lieu du carré avec le nom '
        'par-dessus).',
  ),
  OtaChangelogEntry(
    date: '28.10 21h17',
    patchNumber: 13,
    title: 'Logo Moonfin au lancement et sur les écrans serveur remplacé '
        'par celui de CARBA TV (oublié lors du nettoyage de ce matin).',
  ),
  OtaChangelogEntry(
    date: '28.10 20h38',
    patchNumber: 13,
    title: 'Lecteur : chapitres affichés en bande de miniatures sous la '
        'barre (comme Emby), au lieu d\'une fenêtre flottante.',
  ),
  OtaChangelogEntry(
    date: '28.10 19h57',
    patchNumber: 13,
    title: 'Lecteur TV : restructuré pour mettre lecture/pause au-dessus '
        'de la barre de progression (comme sur mobile), au lieu de les '
        'mélanger avec les icônes de la rangée du dessous.',
  ),
  OtaChangelogEntry(
    date: '28.10 17h07',
    patchNumber: 13,
    title: 'Lecteur : la barre de contrôle restait parfois bloquée '
        'affichée au lieu de disparaître après quelques secondes.',
  ),
  OtaChangelogEntry(
    date: '28.10 15h07',
    patchNumber: 13,
    title:
        'Patch OTA : bouton "Redémarrer maintenant" après téléchargement '
        'd\'un patch - plus besoin de fermer/rouvrir l\'app à la main '
        '(redémarrage natif du processus). Nécessite cette réinstallation '
        'une fois (code natif ajouté), les patchs suivants redeviendront '
        'normaux.',
  ),
  OtaChangelogEntry(
    date: '28.10 13h07',
    patchNumber: 13,
    title:
        'Lecteur : lien "Apparence des sous-titres" dans le sélecteur de '
        'piste (comme Emby), ouvre l\'écran de personnalisation existant.',
  ),
  OtaChangelogEntry(
    date: '28.10 11h59',
    patchNumber: 13,
    title:
        'Lecteur : la barre ne garde plus que sous-titres/audio/chapitres '
        'directement visibles - tout le reste (vitesse, zoom, cast, info...) '
        'est maintenant regroupé dans le bouton réglages (comme Emby).',
  ),
  OtaChangelogEntry(
    date: '28.10 09h37',
    patchNumber: 13,
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
