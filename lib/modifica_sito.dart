// Nuovo sito / modifica: tutti i campi della versione precedente, in una pagina intera.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'badge_sito.dart';
import 'connessione.dart';
import 'loghi.dart';
import 'modelli.dart';
import 'tema.dart';

class SchermataModificaSito extends StatefulWidget {
  const SchermataModificaSito({super.key, this.sito, required this.gruppi});

  final Sito? sito;
  final List<String> gruppi;

  @override
  State<SchermataModificaSito> createState() => _SchermataModificaSitoState();
}

class _SchermataModificaSitoState extends State<SchermataModificaSito> {
  late final Sito _s = widget.sito ?? Sito();
  late final _nome = TextEditingController(text: _s.nome);
  late final _host = TextEditingController(text: _s.host);
  late final _porta = TextEditingController(text: widget.sito == null ? '21' : '${_s.porta}');
  late final _utente = TextEditingController(text: _s.utente);
  late final _password = TextEditingController(text: _s.password);
  late final _remota = TextEditingController(text: _s.cartellaRemota);
  late final _locale = TextEditingController(text: _s.cartellaLocale);
  late final _gruppo = TextEditingController(text: _s.gruppo);
  late final _note = TextEditingController(text: _s.note);
  late final _web = TextEditingController(text: _s.sitoWeb);
  bool _cercaLogo = false;
  late Protocollo _prot = _s.protocollo;
  late Accesso _acc = _s.accesso;
  late bool _passivo = _s.passivo;
  late String _chiave = _s.chiave;
  late String _nomeChiave = _s.nomeChiave;
  late final Protocollo _protIniziale = _s.protocollo;
  bool _vedi = false;
  String? _erroreHost;

  void _cambiaProtocollo(Protocollo p) {
    setState(() {
      _prot = p;
      if (p != Protocollo.sftp && _acc == Accesso.chiave) _acc = Accesso.normale;
      // la porta segue il protocollo, se era quella predefinita
      final t = _porta.text.trim();
      if (t.isEmpty || t == '21' || t == '22' || t == '990') _porta.text = p == Protocollo.sftp ? '22' : '21';
    });
  }

  void _salva() {
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() => _erroreHost = 'Campo obbligatorio');
      return;
    }
    _s
      ..nome = _nome.text.trim().isEmpty ? host : _nome.text.trim()
      ..host = host
      ..porta = int.tryParse(_porta.text.trim()) ?? (_prot == Protocollo.sftp ? 22 : 21)
      ..protocollo = _prot
      ..accesso = _acc
      ..utente = _utente.text.trim()
      ..password = _password.text
      ..cartellaRemota = _remota.text.trim().isEmpty ? '/' : _remota.text.trim()
      ..cartellaLocale = _locale.text.trim()
      ..gruppo = _gruppo.text.trim()
      ..note = _note.text.trim()
      ..sitoWeb = _web.text.trim()
      ..passivo = _passivo
      ..chiave = _acc == Accesso.chiave ? _chiave : _s.chiave
      ..nomeChiave = _nomeChiave
      // protocollo cambiato a mano: la variante di FileZilla non vale più
      ..codiceFz = _prot == _protIniziale ? _s.codiceFz : '';
    Navigator.of(context).pop(_s);
  }

  /// Copia del sito con i campi come sono scritti adesso (per cercare il logo prima di salvare).
  Sito _bozza() => _s.copia()
    ..nome = _nome.text.trim().isEmpty ? _host.text.trim() : _nome.text.trim()
    ..host = _host.text.trim()
    ..sitoWeb = _web.text.trim();

  Future<void> _aggiornaLogo() async {
    final l = Loghi.istanza;
    if (!await l.acceso()) {
      if (mounted) avviso(context, 'I loghi sono spenti: accendili in Impostazioni (icona in alto nella lista dei siti)');
      return;
    }
    setState(() => _cercaLogo = true);
    final f = await l.aggiorna(_bozza(), forza: true);
    if (!mounted) return;
    setState(() => _cercaLogo = false);
    if (f == null) avviso(context, "Logo non trovato: scrivi l'indirizzo del sito in «Sito web»");
  }

  Future<void> _scegliImmagine() async {
    final f = await FilePicker.pickFile(type: FileType.image);
    if (f == null) return;
    try {
      await Loghi.istanza.manuale(_bozza(), await f.readAsBytes());
    } catch (e) {
      if (mounted) avviso(context, '$e');
    }
  }

  Future<void> _scegliChiave() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final testo = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    if (!mounted) return;
    final problema = problemaChiave(testo);
    if (problema != null) {
      avviso(context, problema);
      return;
    }
    setState(() {
      _chiave = testo;
      _nomeChiave = f.name;
    });
    if (chiaveCifrata(testo) && _password.text.isEmpty) {
      avviso(context, 'La chiave è protetta da una frase: scrivila sotto, oppure te la chiedo a ogni connessione');
    }
  }

  Widget _etichetta(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6, left: 2),
        child: Text(t.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: grigio500, letterSpacing: .6)),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Testata(
          titolo: widget.sito == null ? 'Nuovo sito' : 'Modifica sito',
          sottotitolo: widget.sito == null ? 'Aggiungi un server FTP, FTPS o SFTP' : _s.nomeVisibile,
          indietro: () => Navigator.of(context).pop(),
          logo: false,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 6, 16, 24 + MediaQuery.of(context).padding.bottom),
            children: [
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _etichetta('Nome'),
                  TextField(controller: _nome, decoration: const InputDecoration(hintText: 'Es. Sito del cliente')),
                  _etichetta('Protocollo'),
                  SegmentedButton<Protocollo>(
                    segments: const [
                      ButtonSegment(value: Protocollo.ftp, label: Text('FTP')),
                      ButtonSegment(value: Protocollo.ftps, label: Text('FTPS')),
                      ButtonSegment(value: Protocollo.sftp, label: Text('SFTP')),
                    ],
                    selected: {_prot},
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: navy,
                      selectedForegroundColor: bianco,
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    onSelectionChanged: (v) => _cambiaProtocollo(v.first),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 6, left: 2),
                    child: Text(
                      switch (_prot) {
                        Protocollo.ftp => 'FTP normale, porta 21',
                        Protocollo.ftps => 'FTP sicuro (TLS): porta 21, oppure 990 per il TLS implicito',
                        Protocollo.sftp => 'SFTP (SSH), porta 22',
                      },
                      style: const TextStyle(color: grigio500, fontSize: 12.5),
                    ),
                  ),
                  _etichetta('Indirizzo del server'),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _host,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        onChanged: (_) => setState(() => _erroreHost = null),
                        decoration: InputDecoration(hintText: 'ftp.esempio.it', errorText: _erroreHost),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 92,
                      child: TextField(
                          controller: _porta,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Porta')),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _etichetta('Accesso'),
                  DropdownButtonFormField<Accesso>(
                    initialValue: _acc,
                    key: ValueKey(_prot == Protocollo.sftp),
                    isExpanded: true,
                    items: [
                      const DropdownMenuItem(value: Accesso.normale, child: Text('Normale (utente e password)')),
                      const DropdownMenuItem(value: Accesso.chiedi, child: Text('Chiedi la password a ogni accesso')),
                      if (_prot == Protocollo.sftp)
                        const DropdownMenuItem(value: Accesso.chiave, child: Text('File chiave (SSH)')),
                      const DropdownMenuItem(value: Accesso.anonimo, child: Text('Anonimo')),
                    ],
                    onChanged: (v) => setState(() => _acc = v!),
                  ),
                  if (_acc != Accesso.anonimo) ...[
                    _etichetta('Utente'),
                    TextField(controller: _utente, autocorrect: false),
                  ],
                  if (_acc == Accesso.chiave) ...[
                    _etichetta('File della chiave'),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: _chiave.isEmpty ? grigio100 : accentoChiaro, borderRadius: BorderRadius.circular(12)),
                      child: Row(children: [
                        Icon(Icons.vpn_key_rounded, color: _chiave.isEmpty ? grigio500 : accentoScuro),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(
                                _chiave.isEmpty
                                    ? 'Nessuna chiave su questo telefono'
                                    : (_nomeChiave.isEmpty ? 'Chiave caricata' : _nomeChiave),
                                style: const TextStyle(fontWeight: FontWeight.w800, color: navy)),
                            if (_s.fileChiave.isNotEmpty)
                              Text('Sul computer: ${_s.fileChiave}',
                                  style: const TextStyle(color: grigio500, fontSize: 12.5)),
                          ]),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 46),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                      onPressed: _scegliChiave,
                      icon: const Icon(Icons.folder_open_rounded, color: navy),
                      label: Text(_chiave.isEmpty ? 'Scegli il file della chiave' : 'Cambia file della chiave',
                          style: const TextStyle(color: navy, fontWeight: FontWeight.w700)),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6, left: 2),
                      child: Text('Chiave privata OpenSSH (per esempio da una cartella nel cloud). Resta cifrata nel telefono.',
                          style: TextStyle(color: grigio500, fontSize: 12.5)),
                    ),
                  ],
                  if (_acc == Accesso.normale || _acc == Accesso.chiave) ...[
                    _etichetta(_acc == Accesso.chiave ? 'Frase della chiave (se c\'è)' : 'Password'),
                    TextField(
                      controller: _password,
                      obscureText: !_vedi,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: InputDecoration(
                        suffixIcon: IconButton(
                          icon: Icon(_vedi ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                          onPressed: () => setState(() => _vedi = !_vedi),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _etichetta('Logo'),
                  Row(children: [
                    BadgeSito(_s, lato: 56),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _web,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _aggiornaLogo(),
                        decoration: const InputDecoration(
                            labelText: 'Sito web (per il logo)', hintText: "Vuoto = dall'indirizzo del server"),
                      ),
                    ),
                  ]),
                  ListenableBuilder(
                    listenable: Loghi.istanza,
                    builder: (context, _) => Loghi.istanza.fallito(_s.id) && Loghi.istanza.accesoOra
                        ? const Padding(
                            padding: EdgeInsets.only(top: 6, left: 2),
                            child: Text("Logo non trovato: scrivi l'indirizzo del sito",
                                style: TextStyle(color: accentoScuro, fontSize: 12.5, fontWeight: FontWeight.w700)),
                          )
                        : const SizedBox(),
                  ),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: _cercaLogo ? null : _aggiornaLogo,
                        icon: _cercaLogo
                            ? const SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: accento))
                            : const Icon(Icons.refresh_rounded, color: navy),
                        label: const Text('Aggiorna logo', style: TextStyle(color: navy, fontWeight: FontWeight.w700)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                        onPressed: _scegliImmagine,
                        icon: const Icon(Icons.photo_library_rounded, color: navy),
                        label: const Text('Scegli immagine', style: TextStyle(color: navy, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
                  _etichetta('Cartella remota iniziale'),
                  TextField(controller: _remota, autocorrect: false, decoration: const InputDecoration(hintText: '/')),
                  _etichetta('Cartella locale (per altri programmi FTP)'),
                  TextField(controller: _locale, autocorrect: false),
                  _etichetta('Gruppo'),
                  Autocomplete<String>(
                    initialValue: TextEditingValue(text: _gruppo.text),
                    optionsBuilder: (v) =>
                        widget.gruppi.where((g) => g.toLowerCase().contains(v.text.toLowerCase())),
                    onSelected: (g) => _gruppo.text = g,
                    fieldViewBuilder: (context, c, f, onSubmit) => TextField(
                      controller: c,
                      focusNode: f,
                      onChanged: (t) => _gruppo.text = t,
                      decoration: const InputDecoration(hintText: 'Nessun gruppo'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _passivo,
                    activeThumbColor: accento,
                    title: const Text('Modalità passiva', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Consigliata: funziona anche dietro router e firewall'),
                    onChanged: (v) => setState(() => _passivo = v),
                  ),
                  _etichetta('Note'),
                  TextField(controller: _note, maxLines: 3, minLines: 2),
                ]),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Annulla', style: TextStyle(color: navy, fontWeight: FontWeight.w700)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 50)),
                    onPressed: _salva,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Salva'),
                  ),
                ),
              ]),
            ],
          ),
        ),
      ]),
    );
  }
}
