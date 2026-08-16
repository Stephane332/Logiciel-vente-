/// Quand rappeler au commerçant de sortir son carnet du téléphone.
///
/// C'est la seule panne dont on ne se relève pas. Un téléphone se vole, se
/// casse, se reformate — et les dettes de ses clients partent avec lui. Rien
/// dans l'application ne le lui demandait jamais.
///
/// Deux façons de rater ce rappel, aussi mauvaises l'une que l'autre :
/// ne rien dire, et le dire tout le temps. Un bandeau qui revient à chaque
/// ouverture devient un décor qu'on ne lit plus, et le jour où il compte, il
/// ne compte plus. Les règles ci-dessous existent pour ça.
library;

/// Décide s'il faut rappeler, et depuis combien de temps le carnet n'est pas
/// sorti du téléphone.
class RappelSauvegarde {
  /// Au-delà, une sauvegarde est trop vieille pour rassurer : une semaine de
  /// ventes et de dettes ne se retrouve pas de mémoire.
  static const apresJours = 7;

  /// Ce qu'il faut avoir accumulé avant le tout premier rappel.
  ///
  /// Un carnet de trois ventes ne vaut pas qu'on interrompe quelqu'un. Une
  /// quinzaine d'écritures, c'est une matinée de travail — assez pour que la
  /// perte se sente, assez tôt pour que le geste devienne une habitude avant
  /// que le carnet ne devienne précieux.
  static const avantLePremier = 15;

  /// Nombre d'écritures faites depuis la dernière sauvegarde. Zéro veut dire
  /// qu'il n'y a rien à perdre qui ne soit déjà sauvegardé.
  final int nouveautes;

  /// Quand le carnet est sorti du téléphone pour la dernière fois. Nul quand
  /// ça n'est jamais arrivé.
  final DateTime? derniere;

  final DateTime maintenant;

  const RappelSauvegarde({
    required this.nouveautes,
    required this.maintenant,
    this.derniere,
  });

  /// Vrai quand il y a quelque chose à perdre, et que ça dure.
  bool get faut {
    if (nouveautes <= 0) return false;
    if (derniere == null) return nouveautes >= avantLePremier;
    return jours! >= apresJours;
  }

  /// Jours écoulés depuis la dernière sauvegarde. Nul quand il n'y en a
  /// jamais eu — il n'y a pas de durée à compter depuis rien.
  int? get jours {
    final quand = derniere;
    if (quand == null) return null;
    // Sur des jours entiers : « il y a 7 jours » se comprend, « il y a 6 jours
    // et 23 heures » ne veut rien dire pour personne.
    final ecart = _jour(maintenant).difference(_jour(quand)).inDays;
    return ecart < 0 ? 0 : ecart;
  }

  /// Ce que le bandeau dit. Court : il est lu debout, entre deux clients.
  String get message {
    if (derniere == null) {
      return "Ton carnet n'est jamais sorti de ce téléphone. "
          "S'il se perd, tout se perd avec lui.";
    }
    final n = jours!;
    final depuis = n <= 1 ? 'hier' : 'il y a $n jours';
    return 'Ta dernière sauvegarde date de $depuis, et tu as travaillé '
        'depuis. Envoie-la ailleurs que sur ce téléphone.';
  }

  static DateTime _jour(DateTime d) => DateTime(d.year, d.month, d.day);
}
