/// Outils de texte, pour les messages qui partent du téléphone.
library;

const _accents = 'àâäáãåçéèêëíìîïñóòôöõúùûüýÿÀÂÄÁÃÅÇÉÈÊËÍÌÎÏÑÓÒÔÖÕÚÙÛÜÝ';
const _sans = 'aaaaaaceeeeiiiinooooouuuuyyAAAAAACEEEEIIIINOOOOOUUUUY';

/// Retire les accents d'un texte, sans toucher au reste.
///
/// Sert à deux choses très différentes : fabriquer un code d'article qui
/// voyagera dans des échanges où les accents posent problème, et alléger un
/// SMS — voir [tientEnUnSms].
String sansAccents(String texte) {
  final tampon = StringBuffer();
  for (final caractere in texte.split('')) {
    final index = _accents.indexOf(caractere);
    tampon.write(index >= 0 ? _sans[index] : caractere);
  }
  return tampon.toString();
}

/// Nombre de SMS que coûtera un message.
///
/// Un SMS tient 160 caractères tant qu'il n'utilise que l'alphabet GSM. Un
/// seul caractère hors de cet alphabet — un é, une apostrophe courbe, un tiret
/// long — bascule tout le message en Unicode, et la limite tombe à **70
/// caractères**. Le même texte peut donc coûter du simple au triple.
///
/// Ça compte : ici le SMS se paie à l'unité, et un commerçant qui découvre
/// qu'envoyer un reçu lui coûte trois messages arrête d'en envoyer.
int nombreDeSms(String message) {
  final unicode = !_gsm.hasMatch(message);
  final limite = unicode ? 70 : 160;
  // Au-delà d'un message, chaque segment perd de la place pour l'en-tête de
  // concaténation.
  final limiteConcatenee = unicode ? 67 : 153;

  if (message.length <= limite) return message.isEmpty ? 0 : 1;
  return (message.length / limiteConcatenee).ceil();
}

/// Vrai quand le message tient en un seul SMS.
bool tientEnUnSms(String message) => nombreDeSms(message) <= 1;

/// L'alphabet GSM 03.38, celui qui tient en 160 caractères.
///
/// Volontairement restreint à ce dont on se sert : lettres non accentuées,
/// chiffres, ponctuation courante et les symboles des codes USSD.
final _gsm = RegExp(r"^[A-Za-z0-9 \r\n@£$¥èéùìòÇØøÅåΔ_ΦΓΛ"
    r"ΩΠΨΣΘΞÆæßÉ!\x22#¤%&'()*+,\-./:;<=>?¡ÄÖÑÜ§¿"
    r'äöñüà]*$');

/// Raccourcit un nom trop long en gardant ses deux bouts.
///
/// Deux articles d'une même famille ne diffèrent presque jamais par leur
/// début : « Sac de riz parfumé 25 kg qualité supérieure » et « … qualité
/// normale » commencent pareil. Rogner par la fin, comme le fait une tuile
/// ordinaire, donne deux étiquettes identiques — et le commerçant vend l'un
/// pour l'autre sans s'en apercevoir.
///
/// On coupe donc au milieu : le début situe le produit, la fin le distingue.
String nomAbrege(String nom, {int maximum = 30}) {
  final propre = nom.trim();
  if (propre.length <= maximum) return propre;

  // Un peu plus de place au début, qui porte le nom du produit ; la fin ne
  // sert qu'à départager.
  final tete = ((maximum - 1) * 0.6).round();
  final queue = maximum - 1 - tete;
  return '${propre.substring(0, tete).trimRight()}…'
      '${propre.substring(propre.length - queue).trimLeft()}';
}
