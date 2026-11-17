import 'package:json_annotation/json_annotation.dart';

part 'seerr_models.g.dart';

class MoonfinProxyConfig {
  final String jellyfinBaseUrl;
  final String jellyfinToken;

  /// 17.11, Sid : « si tu arrives à me faire fonctionner patounetv en tant que
  /// seerr, je prends », puis « on avait déjà modifié pas mal de choses pour
  /// lier Patoune TV à la place de Seerr ».
  ///
  /// Vérifié : tout le travail avait été fait CÔTÉ SERVEUR. Patoune TV expose
  /// déjà une API compatible Jellyseerr complète sur
  /// `/api/jellyseerr/api/v1/` (status, auth/local, auth/jellyfin, request,
  /// request-options, search, discover/*, movie/:id, Radarr, Sonarr, quotas),
  /// et son propre commentaire du 28.09 cite des logs Emby de Moonbase : le
  /// branchement avait déjà été tenté depuis ce côté-là.
  ///
  /// Ce qui manquait était ici : l'adresse était fabriquée en dur à partir du
  /// serveur média (`<serveur>/Moonfin/Seerr/Api/...`), ce qui suppose le
  /// plugin Moonfin — un plugin Jellyfin, alors qu'elle est sur Emby. L'app
  /// tapait donc dans le vide, et aucun réglage ne pouvait y remédier.
  ///
  /// Renseigné, ce champ est l'adresse complète de l'API, utilisée telle
  /// quelle. Vide, rien ne change : on retombe exactement sur le chemin
  /// Moonfin d'origine.
  final String? directApiBaseUrl;

  const MoonfinProxyConfig({
    required this.jellyfinBaseUrl,
    required this.jellyfinToken,
    this.directApiBaseUrl,
  });

  bool get isDirect =>
      directApiBaseUrl != null && directApiBaseUrl!.trim().isNotEmpty;
}

/// Outcome of the password-less Quick Connect sign in. Parsed by hand from any
/// status code so the caller can read the plugin's errorCode, since an old
/// plugin answers the attempt with a generic 401 body.
class MoonfinQuickConnectResult {
  final bool success;
  final String? errorCode;
  final int? seerrUserId;
  final String? displayName;

  const MoonfinQuickConnectResult({
    this.success = false,
    this.errorCode,
    this.seerrUserId,
    this.displayName,
  });
}

@JsonSerializable()
class MoonfinStatusResponse {
  final bool enabled;
  final bool authenticated;
  final String? url;
  final int? seerrUserId;
  final String? displayName;
  final String? avatar;
  final int permissions;
  final int? sessionCreated;
  final int? lastValidated;

  const MoonfinStatusResponse({
    this.enabled = false,
    this.authenticated = false,
    this.url,
    this.seerrUserId,
    this.displayName,
    this.avatar,
    this.permissions = 0,
    this.sessionCreated,
    this.lastValidated,
  });

  factory MoonfinStatusResponse.fromJson(Map<String, dynamic> json) =>
      _$MoonfinStatusResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinStatusResponseToJson(this);
}

@JsonSerializable()
class MoonfinLoginRequest {
  final String username;
  final String password;
  final String authType;

  const MoonfinLoginRequest({
    required this.username,
    required this.password,
    this.authType = 'jellyfin',
  });

  factory MoonfinLoginRequest.fromJson(Map<String, dynamic> json) =>
      _$MoonfinLoginRequestFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinLoginRequestToJson(this);
}

@JsonSerializable()
class MoonfinLoginResponse {
  final bool success;
  final String? error;
  final int? seerrUserId;
  final String? displayName;
  final String? avatar;
  final int permissions;

  const MoonfinLoginResponse({
    this.success = false,
    this.error,
    this.seerrUserId,
    this.displayName,
    this.avatar,
    this.permissions = 0,
  });

  factory MoonfinLoginResponse.fromJson(Map<String, dynamic> json) =>
      _$MoonfinLoginResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinLoginResponseToJson(this);
}

@JsonSerializable()
class MoonfinValidateResponse {
  final bool valid;
  final int? lastValidated;

  const MoonfinValidateResponse({
    this.valid = false,
    this.lastValidated,
  });

  factory MoonfinValidateResponse.fromJson(Map<String, dynamic> json) =>
      _$MoonfinValidateResponseFromJson(json);

  Map<String, dynamic> toJson() => _$MoonfinValidateResponseToJson(this);
}

@JsonSerializable()
class SeerrMainSettings {
  final String apiKey;

  const SeerrMainSettings({required this.apiKey});

  factory SeerrMainSettings.fromJson(Map<String, dynamic> json) =>
      _$SeerrMainSettingsFromJson(json);

  Map<String, dynamic> toJson() => _$SeerrMainSettingsToJson(this);
}

@JsonSerializable()
class SeerrStatus {
  final String? version;
  final int? commitTag;
  final int? updateAvailable;
  final int? commitsBehind;

  const SeerrStatus({
    this.version,
    this.commitTag,
    this.updateAvailable,
    this.commitsBehind,
  });

  factory SeerrStatus.fromJson(Map<String, dynamic> json) =>
      _$SeerrStatusFromJson(json);

  Map<String, dynamic> toJson() => _$SeerrStatusToJson(this);
}

/// Title and poster for a request or issue card. The request and issue list
/// media objects only carry ids, so these come from the details endpoints.
class SeerrMediaSummary {
  final String? title;
  final String? posterPath;

  const SeerrMediaSummary({this.title, this.posterPath});
}
