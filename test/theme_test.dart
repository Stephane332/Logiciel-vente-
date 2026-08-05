/// Tests du thème.
///
/// Un style de bouton sans famille de police écrase celle du thème. Sur
/// téléphone le libellé sortait dans la police du système ; sur le web, où
/// aucune police de repli n'existe, il ne sortait pas du tout. Ces tests
/// gardent la porte fermée.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:carnet/interface/theme/theme.dart';

void main() {
  for (final (nom, theme) in [('clair', themeClair()), ('sombre', themeSombre())]) {
    group('Thème $nom', () {
      test('tous les styles de texte portent la police embarquée', () {
        final styles = <String, TextStyle?>{
          'displayLarge': theme.textTheme.displayLarge,
          'displayMedium': theme.textTheme.displayMedium,
          'headlineMedium': theme.textTheme.headlineMedium,
          'titleLarge': theme.textTheme.titleLarge,
          'titleMedium': theme.textTheme.titleMedium,
          'bodyLarge': theme.textTheme.bodyLarge,
          'bodyMedium': theme.textTheme.bodyMedium,
          'labelLarge': theme.textTheme.labelLarge,
          'labelSmall': theme.textTheme.labelSmall,
        };

        styles.forEach((cle, style) {
          expect(style?.fontFamily, police, reason: '$cle sans police');
        });
      });

      test('les styles passés aux boutons la portent aussi', () {
        // C'est là que le défaut se logeait : ces styles-là ne venaient pas
        // du textTheme final mais de la table brute.
        for (final style in [
          theme.filledButtonTheme.style?.textStyle,
          theme.outlinedButtonTheme.style?.textStyle,
        ]) {
          final resolu = style?.resolve(<WidgetState>{});
          expect(resolu, isNotNull);
          expect(resolu!.fontFamily, police);
        }
      });
    });
  }

  testWidgets('le libellé d\'un bouton à icône garde la police du thème',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: themeClair(),
      home: Scaffold(
        body: Center(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.add),
            label: const Text('Nouveau client'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final libelle = tester.widget<Text>(find.text('Nouveau client'));
    final style = DefaultTextStyle.of(
            tester.element(find.text('Nouveau client')))
        .style;
    expect(libelle.style?.fontFamily ?? style.fontFamily, police);
  });
}
