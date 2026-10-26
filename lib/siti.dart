// «I tuoi siti»: elenco per gruppi, ricerca, connessione, import/export FileZilla, gestione gruppi.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'archivio.dart';
import 'badge_sito.dart';
import 'condiviso.dart';
import 'connessione.dart';
import 'esplora.dart';
import 'fiducia.dart';
import 'filezilla.dart';
import 'loghi.dart';
import 'modelli.dart';
import 'modifica_sito.dart';
import 'tema.dart';
import 'tk_pro.dart';

/// Righe in più del benvenuto di tk-ftp: dove stanno le password e cosa va in rete.
const righeBenvenutoFtp = [
  "Le password e le chiavi SSH restano nella **cassaforte cifrata del telefono**. L'app si collega solo ai server "
      'che aggiungi tu; i loghi dei siti si scaricano dai loro siti web (si spegne in Impostazioni).',
];

class SchermataSiti extends StatefulWidget {
  const SchermataSiti({super.key});

  @override
  State<SchermataSiti> createState() => _SchermataSitiState();
}

class _SchermataSitiState extends State<SchermataSiti> {
  Archivio? _arch;
  final _chiusi = <String>{};
  String _cerca = '';
  bool _cercando = false;
  String? _connessioneA;

  /// Si chiude dopo il benvenuto del primo avvio: loghi (richieste ai siti web) e file condiviso aspettano lui.
  final _dopoBenvenuto = Completer<void>();

  @override
  void initState() {
    super.initState();
    Archivio.apri().then((a) async {
      if (!mounted) return;
      setState(() => _arch = a);
      await _dopoBenvenuto.future;
      if (!mounted) return;
      Loghi.istanza.prepara(a.siti);
      // file condiviso col computer: all'avvio prende in silenzio i siti cambiati sul computer
      final m = await sincronizza(context, FileCondiviso(a), silenziosa: true);
      if (!mounted) return;
      setState(() {});
      Loghi.istanza.prepara(a.siti);
      if (m != null) avviso(context, m);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // primo avvio: benvenuto (software libero, privacy, statistiche) PRIMA di qualunque chiamata in rete
      if (mounted) await benvenutoTk(context, righeExtra: righeBenvenutoFtp);
      if (!_dopoBenvenuto.isCompleted) _dopoBenvenuto.complete();
      // controllo discreto: parla solo se c'è una versione nuova
      if (mounted) proponiAggiornamento(context, avvisaSeAggiornata: false);
      // invito al caffè: al primo avvio e poi al massimo una volta al mese, mai sopra un'altra finestra
      if (mounted) invitoCaffe(context);
    });
  }

  List<Sito> get _filtrati {
    final q = _cerca.toLowerCase();
    final s = _arch?.siti ?? [];
    if (q.isEmpty) return s;
    return s
        .where((x) => '${x.nomeVisibile} ${x.host} ${x.utente} ${x.gruppo}'.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _modifica(Sito? s) async {
    final salvato = await Navigator.of(context).push<Sito>(MaterialPageRoute(
        builder: (_) => SchermataModificaSito(sito: s?.copia(), gruppi: _arch!.gruppi)));
    if (salvato == null) return;
    await _arch!.salva(salvato);
    setState(() {});
    Loghi.istanza.prepara([salvato]);
  }

  Future<void> _elimina(Sito s) async {
    if (!await conferma(context, 'Elimina sito', 'Eliminare «${s.nomeVisibile}»?')) return;
    await _arch!.elimina(s);
    setState(() {});
  }

  Future<void> _connetti(Sito s) async {
    var password = s.password;
    if (s.accesso == Accesso.chiedi) {
      final p = await chiediTesto(context, 'Password per ${s.nomeVisibile}', password: true, ok: 'Connetti');
      if (p == null) return;
      password = p;
    } else if (s.accesso == Accesso.chiave && s.chiave.isNotEmpty && chiaveCifrata(s.chiave) && password.isEmpty) {
      final p = await chiediTesto(context, 'Frase della chiave di ${s.nomeVisibile}', password: true, ok: 'Connetti');
      if (p == null) return;
      password = p;
    }
    await _apri(s, password);
  }

  Future<void> _apri(Sito s, String password) async {
    setState(() => _connessioneA = s.nomeVisibile);
    final c = Connessione.per(s);
    try {
      await c.apri(s, password);
      if (!mounted) return;
      setState(() => _connessioneA = null);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SchermataEsplora(sito: s, connessione: c)));
    } on DomandaFiducia catch (d) {
      await c.chiudi();
      if (!mounted) return;
      setState(() => _connessioneA = null);
      if (await _fidati(d)) {
        await Fiducia.ricorda(d.tipo, d.host, d.porta, d.impronta);
        if (mounted) await _apri(s, password);
      }
    } catch (e) {
      await c.chiudi();
      if (!mounted) return;
      setState(() => _connessioneA = null);
      avviso(context, '$e'.replaceFirst('Exception: ', ''));
    } finally {
      await c.chiudi();
    }
  }

  /// Server mai visto (o cambiato): si mostra l'impronta e si chiede se fidarsi. Nulla è ancora partito:
  /// né la password né i file.
  Future<bool> _fidati(DomandaFiducia d) {
    final cosa = d.tipo == TipoFiducia.chiave ? 'la chiave del server SFTP' : 'il certificato del server FTPS';
    final cambiato = d.vecchia != null;
    final testo = cambiato
        ? 'Per ${d.host}:${d.porta} avevi accettato un\'altra impronta: $cosa è cambiato. Può essere un rinnovo '
            'fatto dal tuo hosting, ma anche qualcuno che si mette in mezzo per rubare la password '
            '(succede sui Wi-Fi pubblici). Continua solo se sei sicuro.\n\nPrima:\n${d.vecchia}\n\nOra:\n${d.impronta}'
        : 'È la prima volta che ti colleghi a ${d.host}:${d.porta} e '
            '${d.tipo == TipoFiducia.chiave ? '$cosa non è ancora conosciuta' : '$cosa non è firmato da un\'autorità riconosciuta (autofirmato, scaduto o di un altro nome)'}. '
            'Se puoi, confronta l\'impronta con quella che ti dà il tuo hosting:\n\n${d.impronta}\n\n'
            'La ricordo: se un giorno cambia, te lo dico prima di mandare la password.';
    return conferma(context, cambiato ? 'Attenzione: server cambiato' : 'Server da verificare', testo,
        si: cambiato ? 'Fidati comunque' : 'Fidati e connetti', pericolo: cambiato);
  }

  // ---- FileZilla
  /// Importa/Esporta con FileZilla in un foglio dal basso.
  Future<void> _fileZilla() async {
    final scelta = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.devices_rounded, color: accento),
            title: const Text('Siti condivisi col computer'),
            subtitle: const Text('Il file tk-ftp-siti.xml di tk-ftp per Windows e Mac, sempre allineato'),
            onTap: () => Navigator.pop(c, 2),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_rounded, color: accento),
            title: const Text('Importa da FileZilla'),
            subtitle: const Text('Scegli il file .xml esportato da FileZilla o dal vecchio tk-ftp'),
            onTap: () => Navigator.pop(c, 0),
          ),
          ListTile(
            leading: const Icon(Icons.file_upload_rounded, color: accento),
            title: const Text('Esporta per FileZilla'),
            subtitle: const Text('Tutti i siti in un file .xml da aprire con FileZilla'),
            onTap: () => Navigator.pop(c, 1),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (scelta == 0) await _importa();
    if (scelta == 1) await _esporta();
    if (scelta == 2 && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => SchermataCondiviso(arch: _arch!)));
      if (mounted) setState(() {});
      Loghi.istanza.prepara(_arch!.siti);
    }
  }

  Future<void> _importa() async {
    final f = await FilePicker.pickFile();
    if (f == null) return;
    final byte = await f.readAsBytes();
    if (!mounted) return;
    final testo = utf8.decode(byte, allowMalformed: true);
    EsitoImport esito;
    try {
      esito = leggiFileZilla(testo);
      if (esito.cifrato) {
        // file condiviso di tk-ftp per computer: password cifrate con la frase segreta
        final fc = FileCondiviso(_arch!);
        var frase = await fc.fraseSalvata();
        String? errore;
        while (mounted) {
          if (frase == null) {
            if (!mounted) return;
            final r = await chiediFrase(context, errore: errore);
            if (r == null) break;
            frase = r.$1;
            if (r.$2) await fc.salvaFrase(frase);
          }
          final e = await leggiInDisparte(testo, frase);
          if (!e.fraseSbagliata) {
            esito = e;
            break;
          }
          await fc.dimenticaFrase();
          frase = null;
          errore = 'Frase sbagliata, riprova';
        }
      }
    } catch (e) {
      if (mounted) avviso(context, 'Importazione non riuscita: $e');
      return;
    }
    if (!mounted) return;
    final nuovi = esito.siti;
    if (nuovi.isEmpty) {
      avviso(context, 'Nel file non ci sono siti');
      return;
    }
    final note = [
      if (esito.saltati > 0) '${esito.saltati} con protocolli non gestiti dall\'app (lasciati fuori)',
      if (esito.bloccate > 0) '${esito.bloccate} password protette dalla password principale di FileZilla (da riscrivere)',
      if (esito.cifrato && esito.decifrate == 0) 'password cifrate non lette (manca la frase segreta)',
    ];
    // export vecchi (o di FileZilla) con le password solo in base64: chi ha il file le legge tutte
    final chiaro = esito.inChiaro > 0
        ? '\n\nNel file ${esito.inChiaro == 1 ? "c'è 1 password" : 'ci sono ${esito.inChiaro} password'} senza '
            "cifratura (solo in base64: chiunque abbia il file la può leggere). Dopo l'importazione cancella questo "
            'file; per portare i siti tra telefono e computer usa «Siti condivisi col computer» con la frase '
            'segreta, che cifra le password.'
        : '';
    final scelta = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        scrollable: true,
        title: const Text('Importa siti'),
        content: Text('Nel file ci sono ${nuovi.length} siti. Vuoi sostituire tutti i siti esistenti o aggiungere quelli nuovi?'
            '${note.isEmpty ? '' : '\n\nAttenzione: ${note.join('; ')}.'}$chiaro'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annulla')),
          TextButton(onPressed: () => Navigator.pop(d, 'tutto'), child: const Text('Sostituisci tutto')),
          FilledButton(onPressed: () => Navigator.pop(d, 'nuovi'), child: const Text('Aggiungi nuovi')),
        ],
      ),
    );
    if (scelta == null) return;
    final n = await _arch!.importa(nuovi, sostituisci: scelta == 'tutto');
    if (!mounted) return;
    setState(() {});
    Loghi.istanza.prepara(_arch!.siti);
    avviso(context, scelta == 'tutto' ? 'Siti importati: $n' : 'Siti aggiunti: $n');
  }

  Future<void> _esporta() async {
    if (_arch!.siti.isEmpty) return avviso(context, 'Non ci sono siti da esportare');
    final xml = Uint8List.fromList(utf8.encode(esportaFileZilla(_arch!.siti)));
    if (Platform.isAndroid) {
      final p = await FilePicker.saveFile(fileName: 'sitemanager.xml', bytes: xml, mimeType: 'text/xml');
      if (p != null && mounted) {
        avviso(context, 'Siti esportati. Le password sono solo in base64, come in FileZilla: tieni il file al sicuro');
      }
    } else {
      final f = File('${(await getTemporaryDirectory()).path}/sitemanager.xml');
      await f.writeAsBytes(xml);
      await SharePlus.instance.share(ShareParams(files: [XFile(f.path)], text: 'Siti tk-ftp per FileZilla'));
    }
  }

  // ---- informazioni
  Future<void> _informazioni() async {
    final l = Loghi.istanza;
    var loghi = await l.acceso();
    final arch = _arch;
    if (!mounted) return;
    await apriInformazioni(context,
        righe: () async => [
              ('Siti salvati', '${arch?.siti.length ?? 0}'),
              ('Gruppi', '${arch?.gruppi.length ?? 0}'),
              ('Password e chiavi SSH', 'cassaforte del telefono'),
              ('File condiviso col computer', arch != null && FileCondiviso(arch).collegato ? 'collegato' : 'no'),
            ],
        notaDati: 'Restano su questo telefono: password e chiavi SSH nella cassaforte cifrata del sistema '
            '(Keystore su Android, Portachiavi su iPhone), mai in chiaro né sui server di TecnikGeek.',
        interruttori: (_) => [
              StatefulBuilder(
                builder: (_, set) => RigaInterruttore(
                  titolo: 'Mostra il logo dei siti',
                  spiegazione: 'Il logo si scarica dal sito web di ogni sito salvato. Spento: nessuna richiesta.',
                  valore: loghi,
                  scuro: true,
                  onChanged: (v) async {
                    set(() => loghi = v);
                    await l.impostaAcceso(v);
                    if (v && _arch != null) l.prepara(_arch!.siti);
                  },
                ),
              ),
            ]);
    if (mounted) setState(() {});
  }

  // ---- impostazioni
  Future<void> _impostazioni() async {
    final l = Loghi.istanza;
    var acceso = await l.acceso();
    if (!mounted) return;
    final gruppi = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (d) => StatefulBuilder(
        builder: (d, set) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Text('Impostazioni', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: const Icon(Icons.folder_copy_rounded, color: accento),
              title: const Text('Gestisci gruppi', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Rinomina o elimina i gruppi dei siti'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.pop(d, true),
            ),
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              value: acceso,
              activeThumbColor: accento,
              secondary: const Icon(Icons.image_rounded, color: accento),
              title: const Text('Mostra il logo dei siti', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('Al posto della lettera, preso dal sito web. Spento: nessuna richiesta in rete'),
              onChanged: (v) async {
                set(() => acceso = v);
                await l.impostaAcceso(v);
                if (v && _arch != null) l.prepara(_arch!.siti);
              },
            ),
            const SizedBox(height: 12),
          ]),
        ),
      ),
    );
    if (gruppi == true && mounted) await _gestisciGruppi();
  }

  // ---- gruppi
  Future<void> _gestisciGruppi() async {
    final gruppi = _arch!.gruppi;
    if (gruppi.isEmpty) return avviso(context, 'Nessun gruppo creato');
    final g = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (d) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Gestisci gruppi', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          for (final g in gruppi)
            ListTile(
              leading: const Icon(Icons.folder_rounded, color: accento),
              title: Text(g),
              trailing: Text('${_arch!.siti.where((s) => s.gruppo == g).length} siti'),
              onTap: () => Navigator.pop(d, g),
            ),
        ]),
      ),
    );
    if (g == null || !mounted) return;
    final azione = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (d) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(g, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800))),
          ListTile(leading: const Icon(Icons.edit_rounded), title: const Text('Rinomina'), onTap: () => Navigator.pop(d, 0)),
          ListTile(
              leading: const Icon(Icons.folder_off_rounded),
              title: const Text('Elimina (mantieni siti)'),
              onTap: () => Navigator.pop(d, 1)),
          ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: rosso),
              title: const Text('Elimina con tutti i siti', style: TextStyle(color: rosso)),
              onTap: () => Navigator.pop(d, 2)),
        ]),
      ),
    );
    if (azione == null || !mounted) return;
    if (azione == 0) {
      final n = await chiediTesto(context, 'Rinomina gruppo', iniziale: g);
      if (n == null || n.isEmpty || n == g) return;
      await _arch!.rinominaGruppo(g, n);
      if (mounted) avviso(context, 'Gruppo rinominato');
    } else {
      final con = azione == 2;
      final ok = await conferma(
          context,
          'Conferma eliminazione',
          con
              ? 'Eliminare il gruppo «$g» e TUTTI i suoi siti? Operazione irreversibile.'
              : 'Eliminare il gruppo «$g»? I siti verranno spostati fuori dal gruppo.');
      if (!ok) return;
      await _arch!.eliminaGruppo(g, conSiti: con);
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final arch = _arch;
    final siti = arch?.siti ?? [];
    final nGruppi = arch?.gruppi.length ?? 0;
    final sotto = '${siti.length} ${siti.length == 1 ? 'sito' : 'siti'}'
        '${nGruppi > 0 ? ' · $nGruppi ${nGruppi == 1 ? 'gruppo' : 'gruppi'}' : ''}';
    return Scaffold(
      floatingActionButton: arch == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _modifica(null),
              backgroundColor: accento,
              foregroundColor: bianco,
              icon: const Icon(Icons.add_rounded),
              label: const Text('NUOVO SITO', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1)),
            ),
      body: Stack(children: [
        Column(children: [
          Testata(
            titolo: 'tk-ftp',
            sottotitolo: arch == null ? '' : sotto,
            azioni: [
              AzioneTk(_cercando ? Icons.close_rounded : Icons.search_rounded, 'Cerca', () => setState(() {
                    _cercando = !_cercando;
                    if (!_cercando) _cerca = '';
                  })),
              AzioneTk(Icons.swap_vert_rounded, 'FileZilla', _fileZilla),
              AzioneTk(Icons.tune_rounded, 'Impostazioni', _impostazioni),
              AzioneTk(Icons.info, 'Informazioni', _informazioni),
            ],
            sotto: _cercando
                ? TextField(
                    autofocus: true,
                    onChanged: (t) => setState(() => _cerca = t.trim()),
                    decoration: const InputDecoration(
                        hintText: 'Cerca per nome, indirizzo, utente…', prefixIcon: Icon(Icons.search_rounded), isDense: true),
                  )
                : null,
          ),
          Expanded(child: arch == null ? const SizedBox() : (siti.isEmpty ? _vuota() : _elenco())),
        ]),
        if (_connessioneA != null)
          Positioned.fill(
            child: Container(
              color: Colors.black45,
              alignment: Alignment.center,
              child: CardTk(
                padding: const EdgeInsets.all(22),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(color: accento, strokeWidth: 3)),
                  const SizedBox(width: 16),
                  Text('Connessione a $_connessioneA…', style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _vuota() => ListView(padding: const EdgeInsets.all(20), children: [
        CardTk(
          padding: const EdgeInsets.all(22),
          child: Column(children: [
            const LogoTk(lato: 72),
            const SizedBox(height: 14),
            const Text('Nessun sito salvato', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            const Text(
              'Aggiungi un sito con «Nuovo sito» oppure importa quelli che hai già in FileZilla '
              '(anche dalla tk-ftp precedente: lì usa «Esporta per FileZilla»).',
              textAlign: TextAlign.center,
              style: TextStyle(color: grigio500, height: 1.4),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _importa, icon: const Icon(Icons.file_download_rounded), label: const Text('Importa da FileZilla')),
          ]),
        ),
      ]);

  Widget _elenco() {
    final siti = _filtrati;
    final senza = siti.where((s) => s.gruppo.isEmpty).toList();
    final gruppi = <String, List<Sito>>{};
    for (final s in siti.where((s) => s.gruppo.isNotEmpty)) {
      gruppi.putIfAbsent(s.gruppo, () => []).add(s);
    }
    final nomi = gruppi.keys.toList()..sort();
    final righe = <Widget>[
      for (final s in senza) _cardSito(s),
      for (final g in nomi) ...[
        _testataGruppo(g, gruppi[g]!.length),
        if (!_chiusi.contains(g) || _cerca.isNotEmpty) ...gruppi[g]!.map(_cardSito),
      ],
    ];
    if (righe.isEmpty) {
      return const Padding(
          padding: EdgeInsets.all(40),
          child: Text('Nessun sito trovato', textAlign: TextAlign.center, style: TextStyle(color: grigio500)));
    }
    return ListView(
      padding: EdgeInsets.fromLTRB(14, 14, 14, 100 + MediaQuery.of(context).padding.bottom),
      children: righe,
    );
  }

  Widget _testataGruppo(String g, int n) {
    final aperto = !_chiusi.contains(g) || _cerca.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Material(
        color: navy,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => setState(() => aperto ? _chiusi.add(g) : _chiusi.remove(g)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(children: [
              AnimatedRotation(
                turns: aperto ? 0 : -.25,
                duration: const Duration(milliseconds: 180),
                child: const Icon(Icons.expand_more_rounded, color: bianco),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.folder_rounded, color: accento, size: 22),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(g,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: bianco, fontSize: 16, fontWeight: FontWeight.w800))),
              Pilla('$n ${n == 1 ? 'SITO' : 'SITI'}', navy3),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _cardSito(Sito s) {
    final nome = s.nomeVisibile;
    final prot = nomeProtocollo(s.protocollo);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: CardTk(
        onTap: () => _connetti(s),
        onLongPress: () => _modifica(s),
        child: Column(children: [
          Row(children: [
            BadgeSito(s),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(nome,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: navy)),
                Text('${s.host}:${s.porta}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: grigio500, fontSize: 13)),
                Text(s.utente.isEmpty ? 'anonimo' : s.utente,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: grigio500, fontSize: 12.5)),
              ]),
            ),
            Pilla(prot, coloriProtocollo[prot]!),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _quadrato(Icons.delete_outline_rounded, rosso, 'Elimina', () => _elimina(s), pieno: true),
            const SizedBox(width: 8),
            _quadrato(Icons.edit_rounded, navy, 'Modifica', () => _modifica(s)),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _connetti(s),
              icon: const Icon(Icons.power_rounded, size: 20),
              label: const Text('Connetti'),
            ),
          ]),
        ]),
      ),
    );
  }

  Widget _quadrato(IconData i, Color c, String tip, VoidCallback onTap, {bool pieno = false}) => Tooltip(
        message: tip,
        child: Material(
          color: pieno ? c.withValues(alpha: .1) : grigio100,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: SizedBox(width: 46, height: 46, child: Icon(i, color: c)),
          ),
        ),
      );
}
