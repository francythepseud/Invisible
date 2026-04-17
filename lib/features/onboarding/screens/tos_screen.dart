import 'package:flutter/material.dart';
import 'package:invisible/core/services/profile_service.dart';
import 'package:invisible/core/services/tos_service.dart';
import 'package:invisible/utils/constants.dart';

/// Schermata di accettazione Termini di Servizio.
/// Mostrata una sola volta dopo il primo login.
/// L'utente DEVE accettare per entrare — back button e rifiuto fanno logout.
class TosScreen extends StatefulWidget {
  final VoidCallback onAccepted;
  const TosScreen({super.key, required this.onAccepted});

  @override
  State<TosScreen> createState() => _TosScreenState();
}

class _TosScreenState extends State<TosScreen> {
  bool _tosChecked     = false;
  bool _privacyChecked = false;
  bool _loading        = false;
  final _scrollController = ScrollController();

  Future<void> _accept() async {
    setState(() => _loading = true);
    await TosService().accept();
    if (mounted) widget.onAccepted();
  }

  /// Rifiuto: logout e torna al login
  Future<void> _refuse() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppConstants.surfaceBlack,
        title: const Text('Rifiuta Termini di Servizio'),
        content: const Text(
          'Se non accetti i Termini di Servizio non puoi utilizzare Invisible.\n\nVerrai disconnesso.',
          style: TextStyle(color: AppConstants.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annulla'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppConstants.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnetti', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      final nav = Navigator.of(context);
      await ProfileService().logout();
      nav.popUntil((route) => route.isFirst);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canAccept = _tosChecked && _privacyChecked && !_loading;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _refuse();
      },
      child: Scaffold(
      backgroundColor: AppConstants.backgroundBlack,
      appBar: AppBar(
        backgroundColor: AppConstants.surfaceBlack,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Termini di Servizio',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          TextButton(
            onPressed: _refuse,
            child: const Text(
              'Rifiuta',
              style: TextStyle(color: AppConstants.error, fontSize: 13),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppConstants.primaryBlue.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppConstants.primaryBlue.withValues(alpha: 0.4)),
            ),
            child: Text(
              'v${AppConstants.tosVersion}',
              style: const TextStyle(
                fontSize: 11,
                color: AppConstants.primaryBlue,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Testo ToS scrollabile ──────────────────────────────────────────
          Expanded(
            child: Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _section('1. Accettazione dei Termini',
                      'Utilizzando Invisible accetti questi Termini di Servizio. Se non accetti, non puoi utilizzare l\'applicazione.'),
                    _section('2. Descrizione del Servizio',
                      'Invisible è un\'applicazione di comunicazione cifrata end-to-end. I messaggi, le chiamate e i file scambiati sono protetti con crittografia Double Ratchet + X3DH (AES-256-GCM). Il server relay non può leggere il contenuto delle comunicazioni.'),
                    _section('3. Uso Consentito',
                      'Sei autorizzato a utilizzare Invisible esclusivamente per comunicazioni lecite. È espressamente vietato:\n\n'
                      '• Trasmettere materiale illegale, incluso materiale pedopornografico (CSAM)\n'
                      '• Utilizzare il servizio per attività criminali o fraudolente\n'
                      '• Violare la privacy di terzi\n'
                      '• Tentare di compromettere la sicurezza del sistema\n'
                      '• Qualsiasi altro uso contrario alle leggi vigenti'),
                    _section('4. Responsabilità dell\'Utente',
                      'Sei l\'unico responsabile di tutto il contenuto che trasmetti tramite Invisible. Il gestore del servizio non può accedere ai contenuti cifrati e non è responsabile dell\'uso che ne fai. Qualsiasi uso illecito è di tua esclusiva responsabilità civile e penale.'),
                    _section('5. Assenza di Responsabilità del Fornitore',
                      'Il fornitore del servizio:\n\n'
                      '• Non può leggere i messaggi (crittografia end-to-end)\n'
                      '• Non è responsabile dei contenuti scambiati tra utenti\n'
                      '• Si riserva il diritto di sospendere l\'accesso in caso di violazioni segnalate\n'
                      '• Non garantisce la disponibilità continuativa del servizio'),
                    _section('6. Privacy e Dati',
                      'Invisible è progettato con principio zero-knowledge. Non raccogliamo nome, cognome, numero di telefono o email. L\'unico dato tecnico conservato è la firma crittografica di questa accettazione (data, ora, versione ToS, piattaforma) come prova legale del consenso.'),
                    _section('7. Panic Button',
                      'Il Panic Button cancella irrevocabilmente tutti i dati locali. Questa operazione non è annullabile. Il fornitore non è responsabile per dati persi a seguito dell\'utilizzo del Panic Button.'),
                    _section('8. Modifiche ai Termini',
                      'Il fornitore può modificare questi Termini in qualsiasi momento. In caso di modifiche sostanziali, ti verrà richiesta una nuova accettazione al successivo accesso.'),
                    _section('9. Legge Applicabile',
                      'Questi Termini sono regolati dalla legge italiana. Per qualsiasi controversia è competente il Foro di residenza del fornitore.'),
                    _section('10. Contatti',
                      'Per segnalazioni di abusi o violazioni dei presenti Termini, contatta il gestore del servizio tramite i canali indicati al momento dell\'installazione.'),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),

          // ── Checkbox + pulsante ────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Container(
            color: AppConstants.surfaceBlack,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            child: Column(
              children: [
                _CheckRow(
                  value: _tosChecked,
                  onChanged: (v) => setState(() => _tosChecked = v ?? false),
                  label: 'Ho letto e accetto i Termini di Servizio',
                ),
                const SizedBox(height: 10),
                _CheckRow(
                  value: _privacyChecked,
                  onChanged: (v) => setState(() => _privacyChecked = v ?? false),
                  label: 'Ho letto e accetto la Privacy Policy (art. 13 GDPR)',
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: canAccept
                          ? AppConstants.primaryBlue
                          : AppConstants.surfaceBlack,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: canAccept
                              ? AppConstants.primaryBlue
                              : AppConstants.textTertiary,
                        ),
                      ),
                    ),
                    onPressed: canAccept ? _accept : null,
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Accetto e continuo',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ), // Container
          ), // SafeArea
        ],
      ),
      ), // Scaffold
    ); // PopScope
  }

  Widget _section(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppConstants.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: AppConstants.textSecondary,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final String label;

  const _CheckRow({
    required this.value,
    required this.onChanged,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
              activeColor: AppConstants.primaryBlue,
              side: const BorderSide(color: AppConstants.textTertiary),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppConstants.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
