// Siti condivisi col computer: il file «tk-ftp-siti.xml» che tk-ftp per computer tiene nella cartella scelta
// (per esempio Dropbox). Sul telefono si sceglie una volta e resta collegato (Android); a ogni sincronizzazione
// si leggono i siti del computer (nuovi e cambiati entrano, niente si cancella) e si riscrive il file con tutti
// i siti, così il computer prende quelli del telefono. Password cifrate con la frase segreta (cifratura.dart).
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'archivio.dart';
import 'filezilla.dart';
import 'modelli.dart';
import 'tema.dart';

const nomeFileCondiviso = 'tk-ftp-siti.xml';
const _chiaveFrase = 'frase-condivisa';

/// Collegamento al file condiviso (solo Android: su iPhone si sceglie il file ogni volta).
class FileCondiviso {
  FileCondiviso(this.arch);
  final Archivio arch;

  String get uri => arch.preferenze.getString('condiviso_uri') ?? '';
  String get nome => arch.preferenze.getString('condiviso_nome') ?? '';
  int get ultima => arch.preferenze.getInt('condiviso_ultima') ?? 0;
  int get modificatoLetto => arch.preferenze.getInt('condiviso_modificato') ?? 0;
  bool get collegato => uri.isNotEmpty;

  /// Password nel file (cifrate): di serie sì se il file del computer le ha.
  bool get conPassword => arch.preferenze.getBool('condiviso_password') ?? true;
  Future<void> impostaConPassword(bool v) => arch.preferenze.setBool('condiviso_password', v);

  Future<String?> fraseSalvata() async {
    try {
      final f = await cassaforte.read(key: _chiaveFrase);
      return f == null || f.isEmpty ? null : f;
    } catch (_) {
      return null;
    }
  }

  Future<void> salvaFrase(String f) => cassaforte.write(key: _chiaveFrase, value: f);
  Future<void> dimenticaFrase() => cassaforte.delete(key: _chiaveFrase);

  Future<bool> scegli() async {
    final r = await nativo.invokeMapMethod<String, Object?>('scegliFile');
    if (r == null) return false;
    await arch.preferenze.setString('condiviso_uri', '${r['uri']}');
    await arch.preferenze.setString('condiviso_nome', '${r['nome'] ?? ''}');
    await arch.preferenze.remove('condiviso_modificato');
    return true;
  }

  Future<void> scollega() async {
    for (final k in ['condiviso_uri', 'condiviso_nome', 'condiviso_ultima', 'condiviso_modificato']) {
      await arch.preferenze.remove(k);
    }
  }

  Future<int> modificato() async {
    final r = await nativo.invokeMapMethod<String, Object?>('infoFile', {'uri': uri});
    return (r?['modificato'] as num?)?.toInt() ?? 0;
  }

  Future<String> leggi() async {
    final b = await nativo.invokeMethod<Uint8List>('leggiFile', {'uri': uri});
    return utf8.decode(b ?? Uint8List(0), allowMalformed: true);
  }

  Future<int> scrivi(String testo) async {
    final r = await nativo.invokeMapMethod<String, Object?>('scriviFile', {'uri': uri, 'dati': utf8.encode(testo)});
    return (r?['modificato'] as num?)?.toInt() ?? 0;
  }

  Future<void> segnaFatto(int modificato) async {
    await arch.preferenze.setInt('condiviso_ultima', DateTime.now().millisecondsSinceEpoch);
    await arch.preferenze.setInt('condiviso_modificato', modificato);
  }
}

/// Il file ha le password cifrate? (lettura veloce, senza frase)
bool fileCifrato(String testo) {
  try {
    return leggiFileZilla(testo).cifrato;
  } catch (_) {
    return false;
  }
}

/// Lettura con la frase, fuori dal thread dello schermo (la frase costa 200.000 giri di PBKDF2).
Future<EsitoImport> leggiInDisparte(String testo, String? frase) => Isolate.run(() => leggiFileZilla(testo, frase: frase));

Future<String> scriviInDisparte(List<Sito> siti, String? frase) {
  final copie = [for (final s in siti) s.copia()];
  return Isolate.run(() => esportaFileZilla(copie, conPassword: false, frase: frase));
}

/// Chiede la frase segreta, con la scelta di ricordarla. Ritorna (frase, ricorda) o null.
Future<(String, bool)?> chiediFrase(BuildContext context, {bool nuova = false, String? errore}) {
  final c = TextEditingController();
  var ricorda = true;
  var vedi = false;
  return showDialog<(String, bool)>(
    context: context,
    builder: (d) => StatefulBuilder(
      builder: (d, set) => AlertDialog(
        title: Text(nuova ? 'Scegli la frase segreta' : 'Frase segreta'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
            nuova
                ? 'Le password nel file saranno cifrate con questa frase. Sul computer scrivi la stessa in tk-ftp → '
                    'Impostazioni → «Siti condivisi col telefono».'
                : 'Le password del file sono cifrate: scrivi la frase segreta scelta in tk-ftp per computer.',
            style: const TextStyle(color: grigio500, height: 1.35),
          ),
          if (errore != null) ...[
            const SizedBox(height: 10),
            Text(errore, style: const TextStyle(color: rosso, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: c,
            autofocus: true,
            obscureText: !vedi,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              hintText: 'Frase segreta',
              suffixIcon: IconButton(
                icon: Icon(vedi ? Icons.visibility_off_rounded : Icons.visibility_rounded),
                onPressed: () => set(() => vedi = !vedi),
              ),
            ),
          ),
          const SizedBox(height: 6),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: ricorda,
            activeColor: accento,
            title: const Text('Ricordala su questo telefono'),
            subtitle: const Text('Resta nella cassaforte del telefono, cifrata'),
            onChanged: (v) => set(() => ricorda = v ?? false),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Annulla')),
          FilledButton(
            onPressed: () {
              if (c.text.isNotEmpty) Navigator.pop(d, (c.text, ricorda));
            },
            child: const Text('Conferma'),
          ),
        ],
      ),
    ),
  );
}

/// Sincronizza col file collegato: legge, unisce, riscrive. [silenziosa] = all'avvio: niente domande,
/// solo lettura se il file è cambiato. Ritorna il messaggio da mostrare (null = niente da dire).
Future<String?> sincronizza(BuildContext context, FileCondiviso fc, {bool silenziosa = false}) async {
  if (!fc.collegato) return null;
  final String testo;
  try {
    if (silenziosa) {
      final m = await fc.modificato();
      if (m != 0 && m == fc.modificatoLetto) return null;
    }
    testo = await fc.leggi();
  } catch (e) {
    return silenziosa ? null : 'Non riesco a leggere il file condiviso: è stato spostato o cancellato? Sceglilo di nuovo.';
  }
  final cifrato = testo.trim().isEmpty ? false : fileCifrato(testo);
  String? frase = await fc.fraseSalvata();
  EsitoImport? esito;
  String? errore;
  if (testo.trim().isNotEmpty) {
    while (true) {
      if (cifrato && frase == null) {
        if (silenziosa || !context.mounted) break;
        final r = await chiediFrase(context, errore: errore);
        if (r == null) break;
        frase = r.$1;
        if (r.$2) await fc.salvaFrase(frase);
      }
      try {
        esito = await leggiInDisparte(testo, cifrato ? frase : null);
      } catch (e) {
        return 'Il file condiviso non si legge: $e';
      }
      if (!esito.fraseSbagliata) break;
      // frase sbagliata: quella salvata non vale più
      await fc.dimenticaFrase();
      frase = null;
      errore = 'Frase sbagliata, riprova';
      if (silenziosa) {
        esito = await leggiInDisparte(testo, null);
        break;
      }
    }
    esito ??= await leggiInDisparte(testo, null);
  }
  var aggiunti = 0, aggiornati = 0;
  if (esito != null) (aggiunti, aggiornati) = await fc.arch.unisci(esito.siti);
  final senzaPassword = cifrato && (frase == null || esito?.fraseSbagliata == true);

  var inviati = 0;
  var modificato = 0;
  if (!silenziosa && !senzaPassword) {
    // riscrive il file con tutti i siti: il computer prende quelli del telefono
    var fraseScrittura = fc.conPassword || cifrato ? frase : null;
    if (fc.conPassword && fraseScrittura == null && context.mounted) {
      final r = await chiediFrase(context, nuova: true);
      if (r != null) {
        fraseScrittura = r.$1;
        if (r.$2) await fc.salvaFrase(fraseScrittura);
      }
    }
    try {
      modificato = await fc.scrivi(await scriviInDisparte(fc.arch.siti, fraseScrittura));
      inviati = fc.arch.siti.length;
    } catch (e) {
      return 'Siti letti, ma il file non si riesce a riscrivere: $e';
    }
  } else {
    try {
      modificato = await fc.modificato();
    } catch (_) {}
  }
  await fc.segnaFatto(modificato);
  final parti = <String>[
    if (esito != null) 'Dal computer: $aggiunti nuovi, $aggiornati aggiornati',
    if (inviati > 0) 'file aggiornato con $inviati siti',
  ];
  if (senzaPassword) {
    parti.add(silenziosa
        ? 'password cifrate non lette (apri «Siti condivisi» e scrivi la frase)'
        : 'password non lette: senza la frase il file non è stato riscritto');
  }
  if (silenziosa && aggiunti == 0 && aggiornati == 0 && !senzaPassword) return null;
  return parti.join(' · ');
}

// ======================================================================= schermata

class SchermataCondiviso extends StatefulWidget {
  const SchermataCondiviso({super.key, required this.arch});
  final Archivio arch;

  @override
  State<SchermataCondiviso> createState() => _SchermataCondivisoState();
}

class _SchermataCondivisoState extends State<SchermataCondiviso> {
  late final _fc = FileCondiviso(widget.arch);
  bool _frase = false;
  bool _lavoro = false;
  String? _esito;

  @override
  void initState() {
    super.initState();
    _aggiornaFrase();
  }

  Future<void> _aggiornaFrase() async {
    final f = await _fc.fraseSalvata();
    if (mounted) setState(() => _frase = f != null);
  }

  Future<void> _sincronizza() async {
    setState(() => _lavoro = true);
    final m = await sincronizza(context, _fc);
    await _aggiornaFrase();
    if (!mounted) return;
    setState(() {
      _lavoro = false;
      _esito = m;
    });
  }

  Future<void> _scegli() async {
    if (!Platform.isAndroid) return _iPhone();
    try {
      if (!await _fc.scegli()) return;
    } catch (e) {
      if (mounted) avviso(context, 'Non riesco ad aprire il file: $e');
      return;
    }
    if (!mounted) return;
    setState(() {});
    if (_fc.nome.isNotEmpty && _fc.nome != nomeFileCondiviso) {
      final ok = await conferma(context, 'File diverso',
          'Il file scelto si chiama «${_fc.nome}», quello di tk-ftp per computer è «$nomeFileCondiviso». Lo uso lo stesso?',
          si: 'Usalo', pericolo: false);
      if (!ok) {
        await _fc.scollega();
        if (mounted) setState(() {});
        return;
      }
    }
    await _sincronizza();
  }

  /// iPhone: i file non restano collegati, si legge una volta e si rimanda col foglio Condividi.
  Future<void> _iPhone() async {
    final f = await FilePicker.pickFile();
    if (f == null || !mounted) return;
    final testo = utf8.decode(await f.readAsBytes(), allowMalformed: true);
    String? frase = await _fc.fraseSalvata();
    if (!mounted) return;
    if (fileCifrato(testo) && frase == null) {
      final r = await chiediFrase(context);
      if (r != null) {
        frase = r.$1;
        if (r.$2) await _fc.salvaFrase(frase);
      }
    }
    setState(() => _lavoro = true);
    final esito = await leggiInDisparte(testo, frase);
    final (a, g) = await widget.arch.unisci(esito.siti);
    final xml = await scriviInDisparte(widget.arch.siti, _fc.conPassword ? frase : null);
    final file = File('${(await getTemporaryDirectory()).path}/$nomeFileCondiviso')..writeAsStringSync(xml);
    if (!mounted) return;
    setState(() {
      _lavoro = false;
      _esito = 'Dal computer: $a nuovi, $g aggiornati${esito.fraseSbagliata ? ' · frase sbagliata, password non lette' : ''}';
    });
    await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: 'Siti tk-ftp per il computer'));
  }

  Future<void> _scollega() async {
    if (!await conferma(context, 'Scollega il file', 'I siti restano sul telefono; il file non si sincronizza più.',
        si: 'Scollega', pericolo: false)) {
      return;
    }
    await _fc.scollega();
    if (mounted) setState(() => _esito = null);
  }

  Future<void> _dimentica() async {
    await _fc.dimenticaFrase();
    await _aggiornaFrase();
    if (mounted) avviso(context, 'Frase segreta tolta da questo telefono');
  }

  String _quando(int ms) => ms == 0 ? 'mai' : dataBreve(DateTime.fromMillisecondsSinceEpoch(ms));

  @override
  Widget build(BuildContext context) {
    final collegato = _fc.collegato;
    return Scaffold(
      body: Column(children: [
        Testata(
          titolo: 'Siti condivisi',
          sottotitolo: 'Insieme a tk-ftp per Windows e Mac',
          indietro: () => Navigator.of(context).pop(),
          logo: false,
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + MediaQuery.of(context).padding.bottom),
            children: [
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const TitoloSezione('Come funziona'),
                  const SizedBox(height: 8),
                  const Text(
                    'Sul computer, in tk-ftp → Impostazioni → «Siti condivisi col telefono», scegli una cartella '
                    'che arriva anche qui (per esempio Dropbox). Lì nasce il file «$nomeFileCondiviso»: '
                    'sceglilo qui sotto una volta sola.',
                    style: TextStyle(height: 1.4),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sincronizzando, i siti nuovi o cambiati sul computer arrivano sul telefono e il file si '
                    'riscrive con tutti i siti del telefono. Un sito cancellato da una parte non sparisce dall\'altra.',
                    style: TextStyle(color: grigio500, height: 1.4, fontSize: 13),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const TitoloSezione('File collegato'),
                  const SizedBox(height: 10),
                  Row(children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                          color: collegato ? accentoChiaro : grigio100, borderRadius: BorderRadius.circular(12)),
                      child: Icon(collegato ? Icons.link_rounded : Icons.link_off_rounded,
                          color: collegato ? accentoScuro : grigio500),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(collegato ? (_fc.nome.isEmpty ? nomeFileCondiviso : _fc.nome) : 'Nessun file collegato',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w800, color: navy, fontSize: 15.5)),
                        Text(
                            collegato
                                ? 'Ultima sincronizzazione: ${_quando(_fc.ultima)}'
                                : (Platform.isAndroid ? 'Scegli il file dalla cartella condivisa' : 'Su iPhone si sceglie ogni volta'),
                            style: const TextStyle(color: grigio500, fontSize: 12.5)),
                      ]),
                    ),
                    if (collegato) const Pilla('Collegato', verde),
                  ]),
                  const SizedBox(height: 14),
                  BottoneTk(
                    testo: collegato ? 'Scegli un altro file' : 'Scegli il file $nomeFileCondiviso',
                    icona: Icons.folder_open_rounded,
                    chiaro: collegato,
                    onTap: _lavoro ? null : _scegli,
                  ),
                  if (collegato) ...[
                    const SizedBox(height: 10),
                    BottoneTk(
                        testo: 'Sincronizza adesso', icona: Icons.sync_rounded, onTap: _lavoro ? null : _sincronizza),
                    TextButton(
                      onPressed: _lavoro ? null : _scollega,
                      child: const Text('Scollega il file', style: TextStyle(color: rosso, fontWeight: FontWeight.w700)),
                    ),
                  ],
                  if (_lavoro) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(color: accento, backgroundColor: accentoChiaro),
                  ],
                  if (_esito != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: grigio100, borderRadius: BorderRadius.circular(12)),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.info_outline_rounded, color: navy, size: 20),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_esito!, style: const TextStyle(height: 1.35))),
                      ]),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 12),
              CardTk(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const TitoloSezione('Password'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _fc.conPassword,
                    activeThumbColor: accento,
                    title: const Text('Password nel file, cifrate', style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: const Text('Cifrate con la frase segreta (AES-256): senza la frase nessuno le legge'),
                    onChanged: (v) async {
                      await _fc.impostaConPassword(v);
                      setState(() {});
                    },
                  ),
                  Row(children: [
                    Icon(_frase ? Icons.lock_rounded : Icons.lock_open_rounded,
                        color: _frase ? verde : grigio500, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          _frase ? 'Frase segreta ricordata su questo telefono' : 'Frase segreta non salvata: te la chiedo quando serve',
                          style: const TextStyle(color: grigio500, fontSize: 13)),
                    ),
                    if (_frase)
                      TextButton(onPressed: _dimentica, child: const Text('Dimentica', style: TextStyle(color: rosso))),
                  ]),
                ]),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}
