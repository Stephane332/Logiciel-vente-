/// Normalisation des numéros de téléphone burkinabè.
///
/// Le numéro est la seule identité stable d'une personne ici : peu de gens
/// ont une adresse électronique, presque personne n'a de pièce à présenter
/// pour acheter du savon. C'est donc lui qui reconnaît un client — d'où
/// l'importance de le ramener toujours à la même forme.
///
/// Un même numéro s'écrit de dix façons : « 70 11 22 33 », « +226 70112233 »,
/// « 0022670112233 ». Sans normalisation, le même client existerait en
/// plusieurs exemplaires.
library;

/// Indicatif du Burkina Faso.
const indicatifBurkina = '226';

/// Ramène un numéro à ses huit chiffres nationaux.
///
/// Renvoie `null` si ce n'est pas un numéro burkinabè plausible : mieux vaut
/// ne rien enregistrer qu'une identité fausse.
String? normaliserTelephone(String? saisie) {
  if (saisie == null) return null;

  var chiffres = saisie.replaceAll(RegExp(r'\D'), '');
  if (chiffres.isEmpty) return null;

  // 00226… ou 226… en tête : c'est l'indicatif, on le retire.
  if (chiffres.startsWith('00$indicatifBurkina')) {
    chiffres = chiffres.substring(2 + indicatifBurkina.length);
  } else if (chiffres.length > 8 && chiffres.startsWith(indicatifBurkina)) {
    chiffres = chiffres.substring(indicatifBurkina.length);
  }

  if (chiffres.length != 8) return null;

  // Mobiles en 5, 6 et 7 ; fixes en 2. Le reste n'existe pas.
  if (!RegExp(r'^[2567]').hasMatch(chiffres)) return null;

  return chiffres;
}

/// Présente un numéro par groupes de deux, comme on l'écrit ici.
String presenterTelephone(String? normalise) {
  if (normalise == null || normalise.length != 8) return normalise ?? '';
  return '${normalise.substring(0, 2)} ${normalise.substring(2, 4)} '
      '${normalise.substring(4, 6)} ${normalise.substring(6)}';
}
