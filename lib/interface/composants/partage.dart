/// Envoi d'un document au client.
///
/// Le document part par WhatsApp ou par SMS, avec le texte déjà rempli. Le
/// commerçant n'a plus qu'à appuyer sur envoyer.
///
/// WhatsApp d'abord : c'est ce que tout le monde utilise ici, et c'est
/// gratuit une fois la connexion payée. Le SMS reste le repli — il marche
/// partout, y compris sur un téléphone sans internet.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../domaine/telephone.dart';
import '../theme/palette.dart';

/// Présente un document et propose de l'envoyer.
class FeuilleDocument extends StatelessWidget {
  final String titre;
  final String texte;

  /// Version envoyée par SMS, quand elle diffère.
  ///
  /// Le SMS se paie à l'unité ici, et un seul caractère accentué fait tomber
  /// la limite de 160 à 70 caractères : le même message peut coûter du simple
  /// au triple. WhatsApp, lui, ne compte rien — il garde le texte complet.
  final String? texteSms;

  /// Numéro du destinataire, au format national. Nul si on ne le connaît pas :
  /// le commerçant choisira le contact lui-même.
  final String? telephone;

  /// Une action de plus, sous les boutons de partage. Sert au reçu, d'où
  /// part « Faire une facture » — c'est là que le client la réclame, pas
  /// dans un écran qu'il faudrait aller chercher.
  final String? actionSecondaire;
  final VoidCallback? surActionSecondaire;

  const FeuilleDocument({
    super.key,
    required this.titre,
    required this.texte,
    this.texteSms,
    this.telephone,
    this.actionSecondaire,
    this.surActionSecondaire,
  });

  static Future<void> presenter(
    BuildContext context, {
    required String titre,
    required String texte,
    String? texteSms,
    String? telephone,
    String? actionSecondaire,
    VoidCallback? surActionSecondaire,
  }) =>
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => FeuilleDocument(
          titre: titre,
          texte: texte,
          texteSms: texteSms,
          telephone: telephone,
          actionSecondaire: actionSecondaire,
          surActionSecondaire: surActionSecondaire,
        ),
      );

  Future<void> _ouvrir(String lien) =>
      launchUrl(Uri.parse(lien), mode: LaunchMode.externalApplication);

  /// Ouvre WhatsApp avec le message pré-rempli.
  ///
  /// WhatsApp veut le numéro en forme internationale ; le composeur SMS le
  /// prend en forme nationale. Les deux formes viennent du domaine.
  Future<void> _versWhatsapp() {
    final international = telephoneInternational(telephone);
    final destinataire = international == null ? '' : 'phone=$international&';
    return _ouvrir(
        'https://wa.me/?${destinataire}text=${Uri.encodeComponent(texte)}');
  }

  /// Ouvre l'application SMS avec le message pré-rempli.
  Future<void> _versSms() => _ouvrir(
      'sms:${telephone ?? ''}?body=${Uri.encodeComponent(texteSms ?? texte)}');

  @override
  Widget build(BuildContext context) {
    final textes = Theme.of(context).textTheme;

    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: Espace.l,
        right: Espace.l,
        bottom: Espace.l + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(child: Text(titre, style: textes.titleLarge)),
          const SizedBox(height: Espace.l),

          // Le document tel qu'il partira, en chasse fixe pour que les
          // montants restent alignés comme sur le téléphone du client.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(Espace.m),
            decoration: BoxDecoration(
              color: Couleurs.fond,
              borderRadius: BorderRadius.circular(Rayon.m),
              border: Border.all(color: Couleurs.bordure),
            ),
            child: Text(
              texte,
              style: const TextStyle(
                // Une police embarquée, pas « monospace » demandée au
                // système : dans un navigateur, ce nom ne résout rien et le
                // document s'affichait dans un cadre vide. Sur téléphone
                // l'ancien code marchait — c'est le pilotage qui l'a vu.
                fontFamily: 'CarnetMono',
                fontSize: 12,
                height: 1.45,
                color: Couleurs.encre,
              ),
            ),
          ),

          const SizedBox(height: Espace.l),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _versWhatsapp,
                  icon: const Icon(Icons.chat_rounded, size: 20),
                  label: const Text('WhatsApp'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF25D366),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: Espace.m),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _versSms,
                  icon: const Icon(Icons.sms_outlined, size: 20),
                  label: const Text('SMS'),
                ),
              ),
            ],
          ),
          const SizedBox(height: Espace.s),
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: texte));
              HapticFeedback.selectionClick();
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copier le texte'),
            style: TextButton.styleFrom(foregroundColor: Couleurs.encreDouce),
          ),
          if (actionSecondaire != null) ...[
            const Divider(height: Espace.xl),
            OutlinedButton.icon(
              onPressed: surActionSecondaire,
              icon: const Icon(Icons.receipt_long_outlined, size: 20),
              label: Text(actionSecondaire!),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
