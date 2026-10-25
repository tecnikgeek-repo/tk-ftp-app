// Editor di codice per i file del server (HTML, PHP, CSS, JS…): scarica, modifica, risalva con la stessa codifica.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'connessione.dart';
import 'modelli.dart';
import 'tema.dart';

const _fondoCodice = Color(0xFF0E1626);
const _testoCodice = Color(0xFFE6EDF7);

class SchermataEditor extends StatefulWidget {
  const SchermataEditor({super.key, required this.file, required this.connessione});

  final FileRemoto file;
  final Connessione connessione;

  @override
  State<SchermataEditor> createState() => _SchermataEditorState();
}

class _SchermataEditorState extends State<SchermataEditor> {
  final _testo = TextEditingController();
  bool _pronto = false;
  bool _occupato = true;
  bool _modificato = false;
  // stessa codifica del file originale: i file vecchi sono spesso Windows-1252, e le accentate devono restare giuste
  bool _utf8 = true;
  bool _bom = false;

  Future<File> get _cache async =>
      File('${(await getTemporaryDirectory()).path}/editor_${widget.file.nome.replaceAll('/', '_')}');

  @override
  void initState() {
    super.initState();
    _carica();
  }

  Future<void> _carica() async {
    try {
      final f = await _cache;
      await widget.connessione.scarica(widget.file.percorso, f);
      _testo.text = _decodifica(await f.readAsBytes());
      _testo.addListener(() {
        if (!_modificato) setState(() => _modificato = true);
      });
      setState(() {
        _pronto = true;
        _occupato = false;
      });
    } catch (e) {
      if (!mounted) return;
      avviso(context, 'Errore apertura: $e');
      Navigator.of(context).pop();
    }
  }

  String _decodifica(List<int> b) {
    _bom = b.length >= 3 && b[0] == 0xEF && b[1] == 0xBB && b[2] == 0xBF;
    final dati = _bom ? b.sublist(3) : b;
    try {
      _utf8 = true;
      return utf8.decode(dati);
    } on FormatException {
      _utf8 = false;
      _bom = false;
      return windows1252Decodifica(dati);
    }
  }

  Future<void> _salva() async {
    if (!_pronto) return;
    setState(() => _occupato = true);
    try {
      final f = await _cache;
      final corpo = _utf8 ? utf8.encode(_testo.text) : windows1252Codifica(_testo.text);
      await f.writeAsBytes([if (_bom) ...[0xEF, 0xBB, 0xBF], ...corpo]);
      await widget.connessione.carica(f, widget.file.percorso);
      if (!mounted) return;
      setState(() => _modificato = false);
      avviso(context, 'Salvato sul server');
    } catch (e) {
      if (mounted) avviso(context, 'Errore salvataggio: $e');
    } finally {
      if (mounted) setState(() => _occupato = false);
    }
  }

  Future<bool> _puoiUscire() async {
    if (!_modificato) return true;
    final r = await showDialog<int>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Modifiche non salvate'),
        content: const Text('Vuoi salvare le modifiche sul server prima di uscire?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, 0), child: const Text('Esci senza salvare')),
          FilledButton(onPressed: () => Navigator.pop(d, 1), child: const Text('Salva')),
        ],
      ),
    );
    if (r == 1) await _salva();
    return r != null;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (fatto, _) async {
        if (fatto) return;
        final nav = Navigator.of(context);
        if (await _puoiUscire()) nav.pop();
      },
      child: Scaffold(
        backgroundColor: _fondoCodice,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _occupato ? null : _salva,
          backgroundColor: _occupato ? navy3 : accento,
          foregroundColor: bianco,
          icon: _occupato
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: bianco, strokeWidth: 2))
              : const Icon(Icons.save_rounded),
          label: Text(_modificato ? 'Salva' : 'Salvato'),
        ),
        body: Column(children: [
          Testata(
            titolo: widget.file.nome,
            sottotitolo: '${widget.file.percorso}${_utf8 ? '' : '  ·  Windows-1252'}',
            logo: false,
            indietro: () async {
              final nav = Navigator.of(context);
              if (await _puoiUscire()) nav.pop();
            },
          ),
          Expanded(
            child: !_pronto
                ? const Center(child: CircularProgressIndicator(color: accento))
                : Scrollbar(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(12, 12, 12, 90 + MediaQuery.of(context).padding.bottom),
                      child: TextField(
                        controller: _testo,
                        maxLines: null,
                        keyboardType: TextInputType.multiline,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(color: _testoCodice, fontFamily: 'monospace', fontSize: 13.5, height: 1.45),
                        cursorColor: accento,
                        decoration: const InputDecoration(
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          isCollapsed: true,
                        ),
                      ),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}

// Windows-1252: uguale a Latin-1 tranne 0x80–0x9F (€, virgolette tipografiche, trattini…).
const _cp1252 = {
  0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021, 0x88: 0x02C6,
  0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018, 0x92: 0x2019, 0x93: 0x201C,
  0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC, 0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A,
  0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
};

String windows1252Decodifica(List<int> b) => String.fromCharCodes(b.map((x) => _cp1252[x] ?? x));

List<int> windows1252Codifica(String s) {
  final inverso = {for (final e in _cp1252.entries) e.value: e.key};
  return [for (final r in s.runes) r < 0x100 && !(r >= 0x80 && r <= 0x9F) ? r : (inverso[r] ?? 0x3F)];
}
