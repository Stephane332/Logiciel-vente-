/// La sauvegarde chiffrée.
///
/// Ce fichier porte le nom, le téléphone et la dette de chaque client, et il
/// part par WhatsApp. Ces tests vérifient qu'une fois fermé il ne dit plus
/// rien de tout ça, qu'il se rouvre avec le bon mot de passe, et qu'il refuse
/// de s'ouvrir autrement — y compris quand on l'a retouché en route.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/donnees/coffre.dart';

void main() {
  const secret = 'Salif doit 12 500 F · 70000000';
  const motDePasse = 'gombo-du-mercredi';

  Future<String> fermer({String clair = secret, String mot = motDePasse}) =>
      Coffre.fermer(
        clair,
        motDePasse: mot,
        format: 2,
        nomCommerce: 'Chez Awa',
        faiteLe: DateTime(2026, 8, 16, 9),
      );

  group('Ce que le fichier laisse voir', () {
    test('plus rien du carnet', () async {
      final ferme = await fermer();

      expect(ferme, isNot(contains('Salif')));
      expect(ferme, isNot(contains('70000000')));
      expect(ferme, isNot(contains('12 500')));
    });

    test('assez pour reconnaître le bon fichier sans mot de passe', () async {
      final ferme = await fermer();

      expect(Coffre.estChiffre(ferme), isTrue);
      final (nom, date) = Coffre.entete(ferme)!;
      expect(nom, 'Chez Awa');
      expect(date, DateTime(2026, 8, 16, 9));
    });

    test('reste du JSON : on sait ce qu’on tient avant de l’ouvrir', () async {
      final brut = jsonDecode(await fermer()) as Map<String, Object?>;

      expect(brut['application'], 'carnet');
      expect(brut['chiffre'], isTrue);
    });
  });

  group('Rouvrir', () {
    test('le bon mot de passe rend le carnet intact', () async {
      expect(await Coffre.ouvrir(await fermer(), motDePasse), secret);
    });

    test('un mot de passe faux ne rend rien', () async {
      expect(await Coffre.ouvrir(await fermer(), 'gombo-du-jeudi'), isNull);
    });

    test('un mot de passe vide ne passe pas non plus', () async {
      expect(await Coffre.ouvrir(await fermer(), ''), isNull);
    });

    test('un fichier retouché en route est refusé', () async {
      final ferme = await fermer();
      final brut = jsonDecode(ferme) as Map<String, Object?>;

      // On change un octet du contenu chiffré : le sceau ne colle plus.
      final chiffre = base64Decode(brut['contenu']! as String);
      chiffre[0] = chiffre[0] ^ 0xFF;
      brut['contenu'] = base64Encode(chiffre);

      expect(await Coffre.ouvrir(jsonEncode(brut), motDePasse), isNull);
    });

    test("un fichier en clair n'est pas une enveloppe", () async {
      const clair = '{"application":"carnet","format":1,"evenements":[]}';

      expect(Coffre.estChiffre(clair), isFalse);
      expect(await Coffre.ouvrir(clair, motDePasse), isNull);
    });

    test("ce qui n'est pas du JSON ne fait rien planter", () async {
      expect(Coffre.estChiffre('pas du tout un fichier'), isFalse);
      expect(await Coffre.ouvrir('pas du tout un fichier', motDePasse), isNull);
    });
  });

  group('Deux sauvegardes du même carnet', () {
    test('ne se ressemblent pas, même avec le même mot de passe', () async {
      final une = await fermer();
      final deux = await fermer();

      // Sel et nonce tirés au hasard à chaque fois : sans ça, on verrait au
      // premier coup d'œil que deux fichiers portent le même contenu.
      expect(une, isNot(deux));

      // Et les deux s'ouvrent quand même.
      expect(await Coffre.ouvrir(une, motDePasse), secret);
      expect(await Coffre.ouvrir(deux, motDePasse), secret);
    });
  });
}
