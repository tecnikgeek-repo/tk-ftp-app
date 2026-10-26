// Connessione al server: FTP / FTPS (TLS esplicito sulla 21, implicito sulla 990) scritto qui, SFTP con dartssh2.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import 'fiducia.dart';
import 'modelli.dart';

typedef Avanzamento = void Function(int fatti, int totale);

abstract class Connessione {
  static Connessione per(Sito s) => s.protocollo == Protocollo.sftp ? ConnessioneSftp() : ConnessioneFtp();

  Future<void> apri(Sito sito, String password);
  Future<List<FileRemoto>> elenca(String cartella);
  Future<void> scarica(String remoto, File locale, {Avanzamento? avanzamento, int dimensione = 0});
  Future<void> carica(File locale, String remoto, {Avanzamento? avanzamento});
  Future<void> eliminaFile(String percorso);
  Future<void> eliminaCartella(String percorso);
  Future<void> creaCartella(String percorso);
  Future<void> rinomina(String da, String a);
  Future<void> chiudi();
}

int _ordina(FileRemoto a, FileRemoto b) {
  if (a.cartella != b.cartella) return a.cartella ? -1 : 1;
  return a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
}

// ======================================================================= FTP / FTPS

class _Risposta {
  _Risposta(this.codice, this.testo);
  final int codice;
  final String testo;
  bool get ok => codice >= 200 && codice < 400;

  /// Risposta all'avvio di un trasferimento: 125/150 = parte (la fine arriva dopo), 2xx = già finito.
  bool get avviato => codice >= 100 && codice < 300;
  bool get finito => codice >= 200;
  @override
  String toString() => '$codice $testo';
}

class ConnessioneFtp implements Connessione {
  RawSocket? _raw;
  StreamSubscription<RawSocketEvent>? _sub;
  final _inArrivo = <int>[];
  final _righe = <String>[];
  Completer<void>? _attesaRighe;
  List<int> _daScrivere = [];
  late String _host;
  late int _porta;
  bool _tls = false;
  bool _mlsd = false;
  String? _fidato; // impronta del certificato accettata dall'utente per questo server
  String? _rifiutato; // impronta del certificato non valido appena visto (da chiedere all'utente)

  /// Certificato che il sistema non riconosce (autofirmato, scaduto, di un altro nome): passa solo se
  /// l'utente l'aveva già accettato; altrimenti la connessione si ferma e si chiede.
  bool _certificatoNonValido(X509Certificate c) {
    final impronta = improntaCertificato(c.der);
    if (impronta == _fidato) return true;
    _rifiutato = impronta;
    return false;
  }

  Exception _erroreTls() => _rifiutato != null
      ? DomandaFiducia(TipoFiducia.certificato, _host, _porta, _rifiutato!, _fidato)
      : Exception('Connessione sicura non riuscita con $_host');
  Future<void> _coda = Future.value();

  // ---- canale di controllo (RawSocket: serve per passare a TLS a metà strada, «AUTH TLS»)
  void _ascolta(RawSocket s) {
    _sub = s.listen((ev) {
      if (ev == RawSocketEvent.read) {
        final b = s.read();
        if (b != null) {
          _inArrivo.addAll(b);
          _spezzaRighe();
        }
      } else if (ev == RawSocketEvent.write) {
        _scriviResto();
      } else if (ev == RawSocketEvent.readClosed || ev == RawSocketEvent.closed) {
        _attesaRighe?.complete();
      }
    }, onError: (_) => _attesaRighe?.complete());
  }

  void _spezzaRighe() {
    while (true) {
      final i = _inArrivo.indexOf(10);
      if (i < 0) break;
      var riga = utf8.decode(_inArrivo.sublist(0, i), allowMalformed: true);
      _inArrivo.removeRange(0, i + 1);
      if (riga.endsWith('\r')) riga = riga.substring(0, riga.length - 1);
      _righe.add(riga);
    }
    if (_righe.isNotEmpty && _attesaRighe != null && !_attesaRighe!.isCompleted) _attesaRighe!.complete();
  }

  void _scriviResto() {
    final s = _raw;
    if (s == null || _daScrivere.isEmpty) return;
    final n = s.write(_daScrivere);
    _daScrivere = _daScrivere.sublist(n);
    s.writeEventsEnabled = _daScrivere.isNotEmpty;
  }

  Future<String> _riga() async {
    while (_righe.isEmpty) {
      if (_raw == null) throw 'Connessione chiusa dal server';
      _attesaRighe = Completer();
      await _attesaRighe!.future.timeout(const Duration(seconds: 30), onTimeout: () => throw 'Il server non risponde');
      if (_righe.isEmpty && (_sub == null)) throw 'Connessione chiusa dal server';
    }
    return _righe.removeAt(0);
  }

  Future<_Risposta> _leggiRisposta() async {
    var r = await _riga();
    while (r.length < 3 || int.tryParse(r.substring(0, 3)) == null) {
      r = await _riga();
    }
    final codice = int.parse(r.substring(0, 3));
    final testo = StringBuffer(r.length > 4 ? r.substring(4) : '');
    if (r.length > 3 && r[3] == '-') {
      while (true) {
        final x = await _riga();
        if (x.startsWith('$codice ')) {
          testo.write('\n${x.substring(4)}');
          break;
        }
        testo.write('\n$x');
      }
    }
    return _Risposta(codice, testo.toString().trim());
  }

  Future<_Risposta> _comando(String c) async {
    // un a capo dentro un nome (anche arrivato dal server) farebbe partire un secondo comando
    if (c.contains('\r') || c.contains('\n')) throw 'Nome non valido: contiene un a capo';
    _daScrivere = [..._daScrivere, ...utf8.encode('$c\r\n')];
    _scriviResto();
    return _leggiRisposta();
  }

  Future<_Risposta> _esigi(String c, {String errore = ''}) async {
    final r = await _comando(c);
    if (!r.ok) throw '${errore.isEmpty ? 'Il server ha rifiutato' : errore}: ${r.testo} (${r.codice})';
    return r;
  }

  /// Un comando alla volta sul canale di controllo.
  Future<T> _inFila<T>(Future<T> Function() lavoro) {
    final c = Completer<T>();
    _coda = _coda.then((_) async {
      try {
        c.complete(await lavoro());
      } catch (e) {
        c.completeError(e);
      }
    });
    return c.future;
  }

  @override
  Future<void> apri(Sito sito, String password) async {
    _host = sito.host.trim();
    _porta = sito.porta;
    final ftps = sito.protocollo == Protocollo.ftps;
    final implicito = sito.tlsImplicito;
    if (ftps) _fidato = await Fiducia.impronta(TipoFiducia.certificato, _host, _porta);
    try {
      _raw = implicito
          ? await RawSecureSocket.connect(_host, sito.porta,
              timeout: const Duration(seconds: 15), onBadCertificate: _certificatoNonValido)
          : await RawSocket.connect(_host, sito.porta, timeout: const Duration(seconds: 15));
    } on SocketException catch (e) {
      throw 'Non riesco a collegarmi a ${sito.host}:${sito.porta} (${e.osError?.message ?? e.message})';
    } on HandshakeException {
      throw _erroreTls();
    }
    _tls = implicito;
    _ascolta(_raw!);
    final saluto = await _leggiRisposta();
    if (!saluto.ok) throw 'Connessione rifiutata: ${saluto.testo}';
    if (ftps && !implicito) {
      await _esigi('AUTH TLS', errore: 'Il server non accetta FTPS');
      final vecchia = _sub!;
      try {
        _raw = await RawSecureSocket.secure(_raw!, subscription: vecchia, onBadCertificate: _certificatoNonValido);
      } on HandshakeException {
        throw _erroreTls();
      }
      _ascolta(_raw!);
      _tls = true;
    }
    if (_tls) {
      await _comando('PBSZ 0');
      await _comando('PROT P');
    }
    final anonimo = sito.accesso == Accesso.anonimo || sito.utente.isEmpty || sito.utente == 'anonymous';
    var r = await _comando('USER ${anonimo ? 'anonymous' : sito.utente}');
    if (r.codice == 331) r = await _comando('PASS ${anonimo ? '' : password}');
    if (!r.ok) throw 'Autenticazione fallita: controlla utente e password';
    final feat = await _comando('FEAT');
    _mlsd = feat.testo.toUpperCase().contains('MLSD');
    if (feat.testo.toUpperCase().contains('UTF8')) await _comando('OPTS UTF8 ON');
    await _esigi('TYPE I');
  }

  Future<Socket> _apriDati() async {
    var r = await _comando('PASV');
    int? porta;
    if (r.codice == 227) {
      final m = RegExp(r'(\d+),(\d+),(\d+),(\d+),(\d+),(\d+)').firstMatch(r.testo);
      if (m != null) porta = int.parse(m.group(5)!) * 256 + int.parse(m.group(6)!);
    }
    if (porta == null) {
      r = await _comando('EPSV');
      final m = RegExp(r'\|\|\|(\d+)\|').firstMatch(r.testo);
      if (r.codice == 229 && m != null) porta = int.parse(m.group(1)!);
    }
    if (porta == null) throw 'Il server non accetta la modalità passiva: ${r.testo}';
    // si usa sempre l'indirizzo del server (l'IP del PASV è spesso quello interno, dietro NAT)
    return Socket.connect(_host, porta, timeout: const Duration(seconds: 15));
  }

  /// In FTPS il canale dati si protegge dopo il comando (RETR/STOR/LIST): il server fa la stretta di mano solo allora.
  Future<Socket> _proteggi(Socket dati) async {
    if (!_tls) return dati;
    try {
      return await SecureSocket.secure(dati, host: _host, onBadCertificate: _certificatoNonValido)
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      dati.destroy();
      throw 'Connessione sicura sul canale dati non riuscita';
    }
  }

  Future<void> _fine() async {
    final r = await _leggiRisposta();
    if (!r.ok) throw '${r.testo} (${r.codice})';
  }

  @override
  Future<List<FileRemoto>> elenca(String cartella) => _inFila(() async {
        await _esigi('CWD $cartella', errore: 'Cartella non raggiungibile');
        final grezzo = await _apriDati();
        final r = await _comando(_mlsd ? 'MLSD' : 'LIST -a');
        if (!r.avviato) {
          grezzo.destroy();
          // alcuni server non capiscono «-a»
          if (!_mlsd) return _elencaSemplice(cartella);
          throw 'Elenco non riuscito: ${r.testo}';
        }
        final ricevuti = BytesBuilder(copy: false);
        await (await _proteggi(grezzo)).listen(ricevuti.add).asFuture<void>();
        if (!r.finito) await _fine();
        return _interpreta(utf8.decode(ricevuti.takeBytes(), allowMalformed: true), cartella);
      });

  Future<List<FileRemoto>> _elencaSemplice(String cartella) async {
    final grezzo = await _apriDati();
    final r = await _comando('LIST');
    if (!r.avviato) {
      grezzo.destroy();
      throw 'Elenco non riuscito: ${r.testo}';
    }
    final ricevuti = BytesBuilder(copy: false);
    await (await _proteggi(grezzo)).listen(ricevuti.add).asFuture<void>();
    if (!r.finito) await _fine();
    return _interpreta(utf8.decode(ricevuti.takeBytes(), allowMalformed: true), cartella);
  }

  List<FileRemoto> _interpreta(String testo, String cartella) {
    final out = <FileRemoto>[];
    for (final riga in const LineSplitter().convert(testo)) {
      final f = _mlsd ? leggiMlsd(riga, cartella) : leggiList(riga, cartella);
      if (f != null && f.nome != '.' && f.nome != '..') out.add(f);
    }
    return out..sort(_ordina);
  }

  @override
  Future<void> scarica(String remoto, File locale, {Avanzamento? avanzamento, int dimensione = 0}) => _inFila(() async {
        var totale = dimensione;
        final sz = await _comando('SIZE $remoto');
        if (sz.codice == 213) totale = int.tryParse(sz.testo.trim()) ?? totale;
        await locale.parent.create(recursive: true);
        final grezzo = await _apriDati();
        final r = await _comando('RETR $remoto');
        if (!r.avviato) {
          grezzo.destroy();
          throw 'Scaricamento non riuscito: ${r.testo}';
        }
        final dati = await _proteggi(grezzo);
        final out = locale.openWrite();
        var fatti = 0;
        await dati.listen((b) {
          out.add(b);
          fatti += b.length;
          avanzamento?.call(fatti, totale);
        }).asFuture<void>();
        await out.close();
        if (!r.finito) await _fine();
      });

  @override
  Future<void> carica(File locale, String remoto, {Avanzamento? avanzamento}) => _inFila(() async {
        final totale = await locale.length();
        final grezzo = await _apriDati();
        final r = await _comando('STOR $remoto');
        if (!r.avviato) {
          grezzo.destroy();
          throw 'Caricamento non riuscito: ${r.testo}';
        }
        final dati = await _proteggi(grezzo);
        var fatti = 0;
        await for (final b in locale.openRead()) {
          dati.add(b);
          fatti += b.length;
          avanzamento?.call(fatti, totale);
          await dati.flush();
        }
        await dati.close();
        await _fine();
      });

  @override
  Future<void> eliminaFile(String percorso) =>
      _inFila(() async => _esigi('DELE $percorso', errore: 'Eliminazione non riuscita'));

  @override
  Future<void> eliminaCartella(String percorso) async {
    for (final f in await elenca(percorso)) {
      if (f.cartella) {
        await eliminaCartella(f.percorso);
      } else {
        await eliminaFile(f.percorso);
      }
    }
    await _inFila(() async {
      await _comando('CWD /');
      await _esigi('RMD $percorso', errore: 'Eliminazione della cartella non riuscita');
    });
  }

  @override
  Future<void> creaCartella(String percorso) =>
      _inFila(() async => _esigi('MKD $percorso', errore: 'Creazione della cartella non riuscita'));

  @override
  Future<void> rinomina(String da, String a) => _inFila(() async {
        final r = await _comando('RNFR $da');
        if (r.codice != 350) throw 'Rinomina non riuscita: ${r.testo}';
        await _esigi('RNTO $a', errore: 'Rinomina non riuscita');
      });

  @override
  Future<void> chiudi() async {
    try {
      if (_raw != null) await _comando('QUIT').timeout(const Duration(seconds: 3));
    } catch (_) {}
    await _sub?.cancel();
    _sub = null;
    await _raw?.close();
    _raw = null;
  }
}

/// Riga MLSD: «type=dir;size=0;modify=20240101120000; nome».
FileRemoto? leggiMlsd(String riga, String cartella) {
  final i = riga.indexOf(' ');
  if (i < 0) return null;
  final nome = riga.substring(i + 1);
  final fatti = <String, String>{};
  for (final p in riga.substring(0, i).split(';')) {
    final j = p.indexOf('=');
    if (j > 0) fatti[p.substring(0, j).toLowerCase()] = p.substring(j + 1);
  }
  final tipo = (fatti['type'] ?? '').toLowerCase();
  if (tipo == 'cdir' || tipo == 'pdir') return null;
  DateTime? quando;
  final m = fatti['modify'];
  if (m != null && m.length >= 14) {
    quando = DateTime.tryParse('${m.substring(0, 8)}T${m.substring(8, 14)}Z')?.toLocal();
  }
  return FileRemoto(
    nome: nome,
    percorso: unisci(cartella, nome),
    cartella: tipo == 'dir' || tipo.startsWith('os.unix=slink'),
    dimensione: int.tryParse(fatti['size'] ?? '') ?? 0,
    modificato: quando,
  );
}

final _unix = RegExp(
    r'^([\-dlbcps])[rwxsStT\-]{9}\S*\s+\d+\s+\S+\s+\S+\s+(\d+)\s+(\w{3})\s+(\d{1,2})\s+(\d{1,2}:\d{2}|\d{4})\s+(.+)$');
final _dos = RegExp(r'^(\d{2})-(\d{2})-(\d{2,4})\s+(\d{1,2}):(\d{2})(AM|PM)?\s+(<DIR>|\d+)\s+(.+)$', caseSensitive: false);
const _mesi = ['jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec'];

/// Riga LIST in formato Unix («drwxr-xr-x 2 u g 4096 Jan 1 12:00 nome») o Windows/IIS.
FileRemoto? leggiList(String riga, String cartella) {
  final u = _unix.firstMatch(riga);
  if (u != null) {
    var nome = u.group(6)!;
    final link = u.group(1) == 'l';
    if (link && nome.contains(' -> ')) nome = nome.substring(0, nome.indexOf(' -> '));
    DateTime? quando;
    final mese = _mesi.indexOf(u.group(3)!.toLowerCase()) + 1;
    final giorno = int.parse(u.group(4)!);
    final x = u.group(5)!;
    if (mese > 0) {
      if (x.contains(':')) {
        final ora = x.split(':');
        final adesso = DateTime.now();
        var d = DateTime(adesso.year, mese, giorno, int.parse(ora[0]), int.parse(ora[1]));
        if (d.isAfter(adesso.add(const Duration(days: 1)))) d = DateTime(adesso.year - 1, mese, giorno, d.hour, d.minute);
        quando = d;
      } else {
        quando = DateTime(int.parse(x), mese, giorno);
      }
    }
    return FileRemoto(
      nome: nome,
      percorso: unisci(cartella, nome),
      // i collegamenti (es. public_html → …) di solito sono cartelle
      cartella: u.group(1) == 'd' || link,
      dimensione: int.tryParse(u.group(2)!) ?? 0,
      modificato: quando,
    );
  }
  final d = _dos.firstMatch(riga);
  if (d != null) {
    final nome = d.group(8)!;
    var anno = int.parse(d.group(3)!);
    if (anno < 100) anno += anno < 70 ? 2000 : 1900;
    var ora = int.parse(d.group(4)!);
    final ap = d.group(6)?.toUpperCase();
    if (ap == 'PM' && ora < 12) ora += 12;
    if (ap == 'AM' && ora == 12) ora = 0;
    final dir = d.group(7)!.toUpperCase() == '<DIR>';
    return FileRemoto(
      nome: nome,
      percorso: unisci(cartella, nome),
      cartella: dir,
      dimensione: dir ? 0 : int.tryParse(d.group(7)!) ?? 0,
      modificato: DateTime(anno, int.parse(d.group(1)!), int.parse(d.group(2)!), ora, int.parse(d.group(5)!)),
    );
  }
  return null;
}

// ======================================================================= SFTP

/// La chiave privata del sito è protetta da una frase?
bool chiaveCifrata(String testo) {
  try {
    return SSHKeyPair.isEncryptedPem(testo);
  } catch (_) {
    return false;
  }
}

/// Controlla che il testo sia una chiave privata che l'app sa usare; ritorna l'errore da mostrare o null.
String? problemaChiave(String testo) {
  final t = testo.trim();
  if (t.startsWith('PuTTY-User-Key-File')) {
    return 'È una chiave di PuTTY (.ppk): aprila con PuTTYgen e usa «Conversions → Export OpenSSH key», poi scegli quel file';
  }
  if (!t.contains('PRIVATE KEY')) return 'Il file non contiene una chiave privata (deve iniziare con «-----BEGIN …PRIVATE KEY-----»)';
  return null;
}

/// Chiavi del sito pronte per l'accesso; [frase] serve solo se la chiave è protetta.
List<SSHKeyPair> chiaviPrivate(Sito sito, String frase) {
  if (sito.chiave.trim().isEmpty) {
    throw 'Per questo sito serve il file della chiave: tieni premuto il sito, «Modifica» e scegli il file'
        '${sito.fileChiave.isNotEmpty ? ' (sul computer è ${sito.fileChiave})' : ''}';
  }
  final problema = problemaChiave(sito.chiave);
  if (problema != null) throw problema;
  try {
    return SSHKeyPair.fromPem(sito.chiave, chiaveCifrata(sito.chiave) ? frase : null);
  } catch (_) {
    throw chiaveCifrata(sito.chiave) ? 'Frase della chiave sbagliata' : 'Chiave privata non valida o di un tipo non supportato';
  }
}

class ConnessioneSftp implements Connessione {
  SSHClient? _ssh;
  SftpClient? _sftp;

  SftpClient get _s => _sftp ?? (throw 'Non connesso');

  @override
  Future<void> apri(Sito sito, String password) async {
    final identita = sito.accesso == Accesso.chiave ? chiaviPrivate(sito, password) : null;
    final host = sito.host.trim();
    final fidata = await Fiducia.impronta(TipoFiducia.chiave, host, sito.porta);
    String? vista; // impronta della chiave del server se non è quella accettata
    // Gli errori del socket arrivano nella zona in cui è stato aperto: chiusa la connessione per una chiave
    // rifiutata, la libreria scrive ancora sul socket e l'errore resterebbe senza nessuno che lo raccoglie.
    // Qui il primo errore va ad «apri», quelli del socket già chiuso si lasciano cadere.
    final pronto = Completer<void>();
    runZonedGuarded(() async {
      final sock = await SSHSocket.connect(host, sito.porta, timeout: const Duration(seconds: 15));
      _ssh = SSHClient(
        sock,
        username: sito.utente,
        identities: identita,
        // la password parte solo dopo questo controllo: a un server sconosciuto o cambiato non arriva
        onPasswordRequest: identita == null ? () => password : null,
        onVerifyHostKey: (tipo, impronta) {
          final testo = '$tipo ${utf8.decode(impronta)}';
          if (testo == fidata) return true;
          vista = testo;
          return false;
        },
      );
      await _ssh!.authenticated.timeout(const Duration(seconds: 20));
      _sftp = await _ssh!.sftp();
      if (!pronto.isCompleted) pronto.complete();
    }, (e, st) {
      if (!pronto.isCompleted) return pronto.completeError(e, st);
      if (e is SocketException) return;
      Zone.root.handleUncaughtError(e, st);
    });
    try {
      await pronto.future;
    } catch (e) {
      // chiave rifiutata qui sopra: la libreria chiude con un suo errore, si chiede all'utente
      if (vista != null) throw DomandaFiducia(TipoFiducia.chiave, host, sito.porta, vista!, fidata);
      if (e is SSHAuthFailError) {
        throw identita != null
            ? 'Il server non accetta questa chiave: controlla utente e file della chiave'
            : 'Autenticazione fallita: controlla utente e password';
      }
      if (e is SocketException) {
        throw 'Non riesco a collegarmi a ${sito.host}:${sito.porta} (${e.osError?.message ?? e.message})';
      }
      if (e is TimeoutException) throw 'Il server non risponde';
      rethrow;
    }
  }

  @override
  Future<List<FileRemoto>> elenca(String cartella) async {
    final nomi = await _s.listdir(cartella);
    return [
      for (final n in nomi)
        if (n.filename != '.' && n.filename != '..')
          FileRemoto(
            nome: n.filename,
            percorso: unisci(cartella, n.filename),
            cartella: n.attr.isDirectory || n.longname.startsWith('l'),
            dimensione: n.attr.size ?? 0,
            modificato: n.attr.modifyTime == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(n.attr.modifyTime! * 1000),
          )
    ]..sort(_ordina);
  }

  @override
  Future<void> scarica(String remoto, File locale, {Avanzamento? avanzamento, int dimensione = 0}) async {
    final f = await _s.open(remoto, mode: SftpFileOpenMode.read);
    try {
      final totale = (await f.stat()).size ?? dimensione;
      await locale.parent.create(recursive: true);
      final out = locale.openWrite();
      await out.addStream(f.read(onProgress: (n) => avanzamento?.call(n, totale)));
      await out.close();
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> carica(File locale, String remoto, {Avanzamento? avanzamento}) async {
    final totale = await locale.length();
    final f = await _s.open(remoto,
        mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate);
    try {
      await f.write(locale.openRead().map(Uint8List.fromList), onProgress: (n) => avanzamento?.call(n, totale));
    } finally {
      await f.close();
    }
  }

  @override
  Future<void> eliminaFile(String percorso) => _s.remove(percorso);

  @override
  Future<void> eliminaCartella(String percorso) async {
    for (final f in await elenca(percorso)) {
      if (f.cartella) {
        await eliminaCartella(f.percorso);
      } else {
        await eliminaFile(f.percorso);
      }
    }
    await _s.rmdir(percorso);
  }

  @override
  Future<void> creaCartella(String percorso) => _s.mkdir(percorso);

  @override
  Future<void> rinomina(String da, String a) => _s.rename(da, a);

  @override
  Future<void> chiudi() async {
    _sftp?.close();
    _ssh?.close();
    _sftp = null;
    _ssh = null;
  }
}
