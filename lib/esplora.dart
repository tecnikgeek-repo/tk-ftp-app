// Esplora file del server: naviga, carica, scarica, rinomina, elimina, nuova cartella, apri editor o immagine.
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'archivio.dart' show nativo;
import 'connessione.dart';
import 'editor.dart';
import 'immagine.dart';
import 'badge_sito.dart';
import 'modelli.dart';
import 'tema.dart';

class SchermataEsplora extends StatefulWidget {
  const SchermataEsplora({super.key, required this.sito, required this.connessione});

  final Sito sito;
  final Connessione connessione;

  @override
  State<SchermataEsplora> createState() => _SchermataEsploraState();
}

class _SchermataEsploraState extends State<SchermataEsplora> {
  late final List<String> _pila = [widget.sito.cartellaRemota.trim().isEmpty ? '/' : widget.sito.cartellaRemota.trim()];
  List<FileRemoto> _file = [];
  bool _carica = false;
  String? _errore;

  String get _qui => _pila.last;

  @override
  void initState() {
    super.initState();
    _aggiorna();
  }

  Future<void> _aggiorna() async {
    setState(() {
      _carica = true;
      _errore = null;
    });
    try {
      final f = await widget.connessione.elenca(_qui);
      if (mounted) setState(() => _file = f);
    } catch (e) {
      if (mounted) setState(() => _errore = '$e');
    } finally {
      if (mounted) setState(() => _carica = false);
    }
  }

  void _entra(String cartella) {
    _pila.add(cartella);
    _aggiorna();
  }

  bool _su() {
    if (_pila.length <= 1) return false;
    _pila.removeLast();
    _aggiorna();
    return true;
  }

  /// Esegue un trasferimento mostrando una finestra con la percentuale.
  Future<bool> _conAvanzamento(String titolo, Future<void> Function(Avanzamento) lavoro) async {
    final valore = ValueNotifier<double?>(null);
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: Text(titolo, maxLines: 2, overflow: TextOverflow.ellipsis),
          content: ValueListenableBuilder<double?>(
            valueListenable: valore,
            builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
              LinearProgressIndicator(value: v, color: accento, backgroundColor: grigio200, minHeight: 8, borderRadius: BorderRadius.circular(4)),
              const SizedBox(height: 10),
              Text(v == null ? 'Attendi…' : '${(v * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      ),
    ));
    try {
      await lavoro((fatti, totale) {
        if (totale > 0) valore.value = (fatti / totale).clamp(0, 1).toDouble();
      });
      return true;
    } catch (e) {
      if (mounted) avviso(context, '$e');
      return false;
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _scarica(FileRemoto f) async {
    final tmp = File('${(await getTemporaryDirectory()).path}/scaricati/${f.nome}');
    final ok = await _conAvanzamento('Scarico ${f.nome}', (av) => widget.connessione.scarica(f.percorso, tmp, avanzamento: av, dimensione: f.dimensione));
    if (!ok || !mounted) return;
    if (Platform.isAndroid) {
      try {
        await nativo.invokeMethod('salvaInDownload', {'percorso': tmp.path, 'nome': f.nome});
        if (mounted) avviso(context, 'Scaricato in Download: ${f.nome}');
      } catch (e) {
        if (mounted) avviso(context, 'Non riesco a salvarlo in Download: $e');
      }
    } else {
      await SharePlus.instance.share(ShareParams(files: [XFile(tmp.path)]));
    }
  }

  Future<void> _caricaFile() async {
    final scelti = await FilePicker.pickFiles();
    if (scelti.isEmpty || !mounted) return;
    var fatti = 0;
    for (final p in scelti) {
      final ok = await _conAvanzamento('Carico ${p.name}', (av) async {
        // su Android i file scelti sono spesso «content://»: si copiano prima in una cartella temporanea
        var locale = p.path == null ? null : File(p.path!);
        if (locale == null || !await locale.exists()) {
          locale = File('${(await getTemporaryDirectory()).path}/caricare/${p.name}');
          await locale.parent.create(recursive: true);
          final out = locale.openWrite();
          await out.addStream(p.readAsByteStream());
          await out.close();
        }
        await widget.connessione.carica(locale, unisci(_qui, p.name), avanzamento: av);
      });
      if (ok) fatti++;
    }
    if (!mounted) return;
    if (fatti > 0) avviso(context, fatti == 1 ? 'Caricato: ${scelti.first.name}' : 'Caricati $fatti file');
    _aggiorna();
  }

  Future<void> _nuovaCartella() async {
    final n = await chiediTesto(context, 'Nuova cartella', suggerimento: 'Nome cartella', ok: 'Crea');
    if (n == null || n.isEmpty) return;
    try {
      await widget.connessione.creaCartella(unisci(_qui, n));
      if (mounted) avviso(context, 'Cartella «$n» creata');
      _aggiorna();
    } catch (e) {
      if (mounted) avviso(context, '$e');
    }
  }

  Future<void> _rinomina(FileRemoto f) async {
    final n = await chiediTesto(context, 'Rinomina', iniziale: f.nome, ok: 'Rinomina');
    if (n == null || n.isEmpty || n == f.nome) return;
    try {
      await widget.connessione.rinomina(f.percorso, unisci(_qui, n));
      if (mounted) avviso(context, 'Rinominato in «$n»');
      _aggiorna();
    } catch (e) {
      if (mounted) avviso(context, '$e');
    }
  }

  Future<void> _elimina(FileRemoto f) async {
    if (!await conferma(context, 'Elimina', 'Eliminare «${f.nome}»? L\'operazione è irreversibile.')) return;
    final ok = await _conAvanzamento('Elimino ${f.nome}', (_) async {
      if (f.cartella) {
        await widget.connessione.eliminaCartella(f.percorso);
      } else {
        await widget.connessione.eliminaFile(f.percorso);
      }
    });
    if (ok && mounted) avviso(context, '«${f.nome}» eliminato');
    _aggiorna();
  }

  void _apri(FileRemoto f) {
    if (f.cartella) {
      _entra(f.percorso);
    } else if (f.immagine) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SchermataImmagine(file: f, connessione: widget.connessione)));
    } else if (f.testoModificabile) {
      _editor(f);
    } else {
      _menu(f);
    }
  }

  Future<void> _editor(FileRemoto f) async {
    if (f.dimensione > 2000000) {
      avviso(context, 'File troppo grande per l\'editor: scaricalo');
      _menu(f);
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => SchermataEditor(file: f, connessione: widget.connessione)));
  }

  Future<void> _menu(FileRemoto f) async {
    final scelta = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (d) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: _iconaFile(f),
            title: Text(f.nome, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text([f.dimensioneLeggibile, dataBreve(f.modificato)].where((x) => x.isNotEmpty).join(' · ')),
          ),
          const Divider(),
          if (f.testoModificabile)
            ListTile(leading: const Icon(Icons.code_rounded), title: const Text('Apri nell\'editor'), onTap: () => Navigator.pop(d, 3)),
          if (f.immagine)
            ListTile(leading: const Icon(Icons.image_rounded), title: const Text('Guarda l\'immagine'), onTap: () => Navigator.pop(d, 4)),
          if (!f.cartella)
            ListTile(leading: const Icon(Icons.download_rounded), title: const Text('Scarica'), onTap: () => Navigator.pop(d, 0)),
          ListTile(leading: const Icon(Icons.drive_file_rename_outline_rounded), title: const Text('Rinomina'), onTap: () => Navigator.pop(d, 1)),
          ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: rosso),
              title: const Text('Elimina', style: TextStyle(color: rosso)),
              onTap: () => Navigator.pop(d, 2)),
        ]),
      ),
    );
    if (scelta == 0) _scarica(f);
    if (scelta == 1) _rinomina(f);
    if (scelta == 2) _elimina(f);
    if (scelta == 3) _editor(f);
    if (scelta == 4 && mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => SchermataImmagine(file: f, connessione: widget.connessione)));
    }
  }

  Widget _iconaFile(FileRemoto f) {
    final (IconData i, Color c) = f.cartella
        ? (Icons.folder_rounded, accento)
        : f.immagine
            ? (Icons.image_rounded, const Color(0xFF0E9AA7))
            : f.testoModificabile
                ? (Icons.code_rounded, const Color(0xFF2E5BFF))
                : const {'zip', 'rar', '7z', 'gz', 'tar', 'tgz'}.contains(f.estensione)
                    ? (Icons.folder_zip_rounded, const Color(0xFF7C3AED))
                    : f.estensione == 'pdf'
                        ? (Icons.picture_as_pdf_rounded, rosso)
                        : (Icons.insert_drive_file_rounded, grigio500);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: c.withValues(alpha: .12), borderRadius: BorderRadius.circular(12)),
      child: Icon(i, color: c),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (fatto, _) {
        if (!fatto && !_su()) Navigator.of(context).pop();
      },
      child: Scaffold(
        body: Column(children: [
          Testata(
            titolo: widget.sito.nomeVisibile,
            sottotitolo: '${nomeProtocollo(widget.sito.protocollo)} · ${widget.sito.host}',
            logo: false,
            marchio: BadgeSito(widget.sito, lato: 42),
            indietro: () {
              if (!_su()) Navigator.of(context).pop();
            },
            azioni: [
              AzioneTk(Icons.upload_rounded, 'Carica file', _caricaFile),
              AzioneTk(Icons.create_new_folder_rounded, 'Nuova cartella', _nuovaCartella),
              AzioneTk(Icons.refresh_rounded, 'Aggiorna', _aggiorna),
            ],
            sotto: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .1), borderRadius: BorderRadius.circular(12)),
              child: Row(children: [
                const Icon(Icons.folder_open_rounded, color: accento, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Text(_qui, style: const TextStyle(color: bianco, fontFamily: 'monospace', fontSize: 13)),
                  ),
                ),
              ]),
            ),
          ),
          if (_carica) const LinearProgressIndicator(color: accento, backgroundColor: Colors.transparent, minHeight: 3),
          Expanded(
            child: RefreshIndicator(
              color: accento,
              onRefresh: _aggiorna,
              child: _errore != null
                  ? ListView(padding: const EdgeInsets.all(24), children: [
                      CardTk(
                        child: Column(children: [
                          const Icon(Icons.error_outline_rounded, color: rosso, size: 40),
                          const SizedBox(height: 8),
                          Text(_errore!, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton(onPressed: _aggiorna, child: const Text('Riprova')),
                        ]),
                      ),
                    ])
                  : (_file.isEmpty && !_carica)
                      ? ListView(children: const [
                          Padding(
                            padding: EdgeInsets.all(48),
                            child: Column(children: [
                              Icon(Icons.folder_off_rounded, color: grigio300, size: 56),
                              SizedBox(height: 10),
                              Text('Cartella vuota', style: TextStyle(color: grigio500, fontSize: 16)),
                            ]),
                          ),
                        ])
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.of(context).padding.bottom),
                          itemCount: _file.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (_, i) {
                            final f = _file[i];
                            return CardTk(
                              padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                              onTap: () => _apri(f),
                              onLongPress: () => _menu(f),
                              child: Row(children: [
                                _iconaFile(f),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(f.nome,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: navy)),
                                    const SizedBox(height: 2),
                                    Text(
                                      [f.cartella ? 'Cartella' : f.dimensioneLeggibile, dataBreve(f.modificato)]
                                          .where((x) => x.isNotEmpty)
                                          .join(' · '),
                                      style: const TextStyle(color: grigio500, fontSize: 12),
                                    ),
                                  ]),
                                ),
                                IconButton(onPressed: () => _menu(f), icon: const Icon(Icons.more_vert_rounded, color: grigio500)),
                              ]),
                            );
                          },
                        ),
            ),
          ),
        ]),
      ),
    );
  }
}
