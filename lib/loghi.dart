// Logo dei siti (favicon / apple-touch-icon) al posto del badge a lettera: STESSE regole di tk-ftp per computer
// (tkftp/logos.py, 1.0.5).
// Dove cercarlo: campo «Sito web» del sito; se è vuoto il dominio si ricava dall'host (via ftp., sftp., www., cpanel.…);
// se l'host è un IP o un server del provider (hostingssd101.netsons.net…) si prova il NOME del sito se sembra un dominio
// o è una parola sola («almacolorificio» → .it, poi .com, solo se risponde). Dalla home (anche se risponde 503/401/403/404
// con HTML, redirect seguiti) si leggono i <link rel="icon"> e apple-touch-icon e vince l'immagine più grande
// (SVG > misura dichiarata > apple-touch 180 > 32); ripiego /favicon.ico. Le immagini si riconoscono dai byte.
// Cache su disco (loghi/<id>.png o .svg + indice.json): rinnovo ogni 30 giorni, se non trovato si riprova dopo 1 giorno;
// un'immagine scelta a mano non si rinnova. Spento nelle impostazioni = nessuna richiesta di rete.
import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'modelli.dart';

const rinnovo = Duration(days: 30);
const riprovaFallito = Duration(days: 1);
const _timeout = Duration(seconds: 6);
const _maxByte = 2000000;
const _lato = 256;
const _prefissi = ['ftp.', 'sftp.', 'ftps.', 'www.', 'cpanel.', 'ssh.', 'webmail.', 'mail.', 'admin.', 'panel.', 'plesk.',
  'server.', 'host.', 'web.'];
const _provider = ['netsons.net', 'aruba.it', 'arubabusiness.it', 'register.it', 'siteground', 'hostinger', 'ovh.net',
  'keliweb', 'serverplan', 'amazonaws.com', 'googleusercontent.com', 'hetzner', 'contabo', 'vultr', 'linode',
  'digitalocean', 'cloudways', 'your-server.de', 'webhosting', 'hostingssd', 'dominiok', 'altervista.org', 'tophost.it',
  'netsonsdns', 'seeweb.it', 'ionos', '1and1', 'godaddy', 'bluehost', 'secureserver.net', 'fastweb', 'infomaniak',
  'plesk.page'];
const _ua = 'Mozilla/5.0 (Linux; Android) tk-ftp (logo del sito)';

// ------------------------------------------------------------------ dove cercare

bool _ip(String h) => InternetAddress.tryParse(h.replaceAll('[', '').replaceAll(']', '')) != null;

bool _daProvider(String host) {
  final h = host.toLowerCase();
  if (_provider.any(h.contains)) return true;
  final parti = h.split('.');
  return RegExp(r'\d').hasMatch(parti.first) && parti.length >= 3; // srv123.…, hostingssd101.…, vps12345.…
}

String _togliPrefissi(String host) {
  var h = host.toLowerCase().trim();
  while (h.startsWith('.')) {
    h = h.substring(1);
  }
  while (h.endsWith('.')) {
    h = h.substring(0, h.length - 1);
  }
  var cambiato = true;
  while (cambiato) {
    cambiato = false;
    for (final p in _prefissi) {
      if (h.startsWith(p) && '.'.allMatches(h).length >= 2) {
        h = h.substring(p.length);
        cambiato = true;
      }
    }
  }
  return h;
}

String _sembraDominio(String testo) {
  var t = testo.trim().toLowerCase().replaceFirst(RegExp(r'^https?://'), '');
  t = t.split('/').first;
  return RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)*\.[a-z]{2,}$').hasMatch(t) ? t : '';
}

/// Indirizzi da provare, nell'ordine (come `candidates()` del computer). Vuota = niente da cercare.
List<String> indirizziLogo(Sito s) {
  final web = s.sitoWeb.trim();
  if (web.isNotEmpty) {
    if (RegExp(r'^https?://', caseSensitive: false).hasMatch(web)) return [web];
    var w = web;
    while (w.startsWith('/')) {
      w = w.substring(1);
    }
    while (w.endsWith('/')) {
      w = w.substring(0, w.length - 1);
    }
    return ['https://$w'];
  }
  final out = <String>[];
  final host = s.host.trim();
  if (host.isNotEmpty && !_ip(host) && !_daProvider(host) && host.contains('.')) out.add('https://${_togliPrefissi(host)}');
  final nome = s.nome.trim();
  final dom = _sembraDominio(nome);
  if (dom.isNotEmpty) {
    out.add('https://${_togliPrefissi(dom)}');
  } else {
    final parola = nome.toLowerCase().replaceAll(RegExp(r'[^a-z0-9-]'), '');
    if (!nome.contains(' ') && parola.length >= 3 && parola.length <= 40 && out.isEmpty) {
      out.addAll(['https://$parola.it', 'https://$parola.com']); // una parola sola, tipo «almacolorificio»
    }
  }
  return LinkedHashSet<String>.from(out).toList();
}

// ------------------------------------------------------------------ rete

class _Risposta {
  _Risposta(this.url, this.tipo, this.dati);
  final String url, tipo;
  final Uint8List dati;
}

/// GET con redirect seguiti (anche verso altri domini). Con [htmlAncheInErrore] le pagine in errore
/// (503 manutenzione, 401/403/404) restituiscono comunque il loro HTML: spesso hanno i <link rel=icon>.
Future<_Risposta> _get(HttpClient client, String url, {bool htmlAncheInErrore = false}) async {
  var uri = Uri.parse(url);
  for (var salti = 0; salti < 8; salti++) {
    final req = await client.getUrl(uri).timeout(_timeout);
    req.followRedirects = false;
    req.headers.set(HttpHeaders.userAgentHeader, _ua);
    req.headers.set(HttpHeaders.acceptHeader, '*/*');
    final r = await req.close().timeout(_timeout);
    if (r.isRedirect || (r.statusCode >= 300 && r.statusCode < 400 && r.headers.value('location') != null)) {
      await r.drain<void>();
      uri = uri.resolve(r.headers.value('location')!);
      continue;
    }
    final tipo = r.headers.contentType?.toString() ?? '';
    if (r.statusCode >= 400 && !(htmlAncheInErrore && tipo.toLowerCase().contains('html'))) {
      await r.drain<void>();
      throw HttpException('HTTP ${r.statusCode}', uri: uri);
    }
    final b = BytesBuilder(copy: false);
    await for (final pezzo in r.timeout(_timeout)) {
      b.add(pezzo);
      if (b.length > _maxByte) throw const HttpException('file troppo grande');
    }
    return _Risposta(uri.toString(), tipo, b.takeBytes());
  }
  throw const HttpException('troppi redirect');
}

int _punteggio(List<String> rel, String misure, String tipo, String href) {
  final svg = tipo.contains('svg') || href.toLowerCase().split('?').first.endsWith('.svg');
  if (svg) return 1000;
  var meglio = 0;
  for (final m in RegExp(r'(\d+)\s*[xX]\s*(\d+)').allMatches(misure)) {
    final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!);
    final v = a < b ? a : b;
    if (v > meglio) meglio = v;
  }
  if (meglio == 0) meglio = rel.any((r) => r.startsWith('apple-touch-icon')) ? 180 : 32;
  return meglio;
}

Map<String, String> _attributi(String tag) {
  final out = <String, String>{};
  for (final m in RegExp(r'''([a-zA-Z:-]+)\s*=\s*("([^"]*)"|'([^']*)'|([^\s>]+))''').allMatches(tag)) {
    out[m.group(1)!.toLowerCase()] = _entita(m.group(3) ?? m.group(4) ?? m.group(5) ?? '');
  }
  return out;
}

String _entita(String s) =>
    s.replaceAll('&amp;', '&').replaceAll('&quot;', '"').replaceAll('&#39;', "'").replaceAll('&lt;', '<').replaceAll('&gt;', '>');

/// Indirizzi delle icone della pagina, dalla più grande; in fondo /favicon.ico.
List<String> indirizziIcone(String paginaUrl, String html) {
  final pagina = Uri.parse(paginaUrl);
  var base = pagina;
  final icone = <(List<String>, String, String, String)>[];
  for (final m in RegExp(r'<(link|base)\b[^>]*>', caseSensitive: false).allMatches(html)) {
    final a = _attributi(m.group(0)!);
    final href = a['href'] ?? '';
    if (m.group(1)!.toLowerCase() == 'base') {
      if (href.isNotEmpty) base = pagina.resolve(href);
      continue;
    }
    final rel = (a['rel'] ?? '').toLowerCase().split(RegExp(r'\s+'));
    if (href.isEmpty || rel.contains('mask-icon')) continue;
    if (rel.contains('icon') || rel.contains('apple-touch-icon') || rel.contains('apple-touch-icon-precomposed')) {
      icone.add((rel, a['sizes'] ?? '', a['type'] ?? '', href));
    }
  }
  final ordinate = [...icone]..sort((x, y) => _punteggio(y.$1, y.$2, y.$3, y.$4) - _punteggio(x.$1, x.$2, x.$3, x.$4));
  final url = [for (final i in ordinate) base.resolve(i.$4).toString(), pagina.resolve('/favicon.ico').toString()];
  return LinkedHashSet<String>.from(url).toList();
}

/// Tipo di immagine dai byte (il content-type dei server spesso è sbagliato). null = non è un'immagine.
String? tipoImmagine(Uint8List d) {
  bool inizia(List<int> p) => d.length >= p.length && List.generate(p.length, (i) => d[i] == p[i]).every((x) => x);
  if (inizia([0x89, 0x50, 0x4E, 0x47])) return 'png';
  if (inizia([0xFF, 0xD8, 0xFF])) return 'jpg';
  if (inizia([0x47, 0x49, 0x46, 0x38])) return 'gif';
  if (inizia([0x00, 0x00, 0x01, 0x00])) return 'ico';
  if (inizia([0x42, 0x4D])) return 'bmp';
  if (d.length > 12 && inizia([0x52, 0x49, 0x46, 0x46]) && ascii.decode(d.sublist(8, 12), allowInvalid: true) == 'WEBP') {
    return 'webp';
  }
  final testa = utf8.decode(d.length > 2000 ? d.sublist(0, 2000) : d, allowMalformed: true).toLowerCase();
  if (testa.contains('<svg')) return 'svg';
  return null;
}

/// Byte → PNG quadrato al massimo 256 px (la misura più grande se è un .ico), oppure lo SVG così com'è.
/// Ritorna (estensione, byte) o null.
(String, Uint8List)? normalizza(Uint8List dati) {
  final tipo = tipoImmagine(dati);
  if (tipo == null) return null;
  if (tipo == 'svg') return ('svg', dati);
  try {
    img.Image? i = tipo == 'ico' ? img.IcoDecoder().decodeImageLargest(dati) : img.decodeImage(dati);
    if (i == null || i.width < 8 || i.height < 8) return null;
    if (i.width > _lato || i.height > _lato) {
      i = i.width >= i.height
          ? img.copyResize(i, width: _lato, interpolation: img.Interpolation.cubic)
          : img.copyResize(i, height: _lato, interpolation: img.Interpolation.cubic);
    }
    return ('png', Uint8List.fromList(img.encodePng(i)));
  } catch (_) {
    return null;
  }
}

/// Cerca il logo partendo dalle home. Ritorna (estensione, byte, url) o null.
Future<(String, Uint8List, String)?> cercaLogo(List<String> basi) async {
  final client = HttpClient()..connectionTimeout = _timeout;
  try {
    for (final base in basi) {
      var pagina = base;
      var html = '';
      try {
        final r = await _get(client, base, htmlAncheInErrore: true);
        pagina = r.url;
        final inizio = utf8.decode(r.dati.length > 2000 ? r.dati.sublist(0, 2000) : r.dati, allowMalformed: true);
        if (r.tipo.contains('html') || inizio.toLowerCase().contains('<html')) html = utf8.decode(r.dati, allowMalformed: true);
      } catch (_) {
        // home irraggiungibile: si prova almeno /favicon.ico
      }
      for (final u in indirizziIcone(pagina, html)) {
        try {
          final r = await _get(client, u);
          final n = await Isolate.run(() => normalizza(r.dati));
          if (n != null) return (n.$1, n.$2, r.url);
        } catch (_) {}
      }
    }
    return null;
  } finally {
    client.close(force: true);
  }
}

// ------------------------------------------------------------------ cache e servizio

/// Loghi dei siti: cache su disco e ricerca in sottofondo, uno alla volta, senza doppioni.
class Loghi extends ChangeNotifier {
  Loghi._();
  static final Loghi istanza = Loghi._();

  /// Cartella della cache (sostituibile nelle prove).
  Future<Directory> Function() cartellaBase = getApplicationSupportDirectory;

  /// Ora (sostituibile nelle prove).
  DateTime Function() adesso = DateTime.now;

  /// Ricerca vera (sostituibile nelle prove).
  Future<(String, Uint8List, String)?> Function(List<String>) cerca = cercaLogo;

  Directory? _dir;
  Map<String, Map<String, Object?>> _indice = {};
  bool _caricato = false;
  bool? _acceso;
  final _byte = <String, Uint8List>{};
  final _coda = Queue<Sito>();
  final _inCoda = <String>{};
  bool _lavora = false;

  Future<Directory> _cartella() async {
    if (_dir != null) return _dir!;
    final d = Directory('${(await cartellaBase()).path}/loghi');
    await d.create(recursive: true);
    return _dir = d;
  }

  Future<void> _carica() async {
    if (_caricato) return;
    _caricato = true;
    try {
      final f = File('${(await _cartella()).path}/indice.json');
      if (await f.exists()) {
        _indice = (jsonDecode(await f.readAsString()) as Map)
            .map((k, v) => MapEntry('$k', Map<String, Object?>.from(v as Map)));
      }
    } catch (_) {
      _indice = {};
    }
  }

  Future<void> _salvaIndice() async {
    final d = await _cartella();
    final tmp = File('${d.path}/indice.json.tmp');
    await tmp.writeAsString(jsonEncode(_indice));
    await tmp.rename('${d.path}/indice.json');
  }

  /// Impostazione «Mostra il logo dei siti» (acceso di serie).
  Future<bool> acceso() async => _acceso ??= (await SharedPreferences.getInstance()).getBool('mostra_loghi') ?? true;

  Future<void> impostaAcceso(bool v) async {
    _acceso = v;
    await (await SharedPreferences.getInstance()).setBool('mostra_loghi', v);
    notifyListeners();
  }

  bool get accesoOra => _acceso ?? true;

  /// File del logo già in cache (png o svg), o null.
  File? file(String id) {
    final d = _dir;
    final est = _indice[id]?['est'];
    if (d == null || est == null) return null;
    final f = File('${d.path}/$id.$est');
    return f.existsSync() ? f : null;
  }

  /// Byte del logo in memoria (letti una volta dal disco), o null.
  Uint8List? byte(String id) {
    final f = file(id);
    if (f == null) return null;
    return _byte[id] ??= f.readAsBytesSync();
  }

  /// Il logo in cache è uno SVG.
  bool svg(String id) => _indice[id]?['est'] == 'svg';

  /// L'ultima ricerca automatica non ha trovato il logo e non ce n'è uno vecchio.
  bool fallito(String id) {
    final e = _indice[id];
    return e != null && e['fallito'] == true && e['manuale'] != true && file(id) == null;
  }

  List<String> _chiave(Sito s) => [s.sitoWeb, s.host, s.nome];

  bool daCercare(Sito s) {
    final e = _indice[s.id];
    if (e == null) return true;
    if (e['manuale'] == true) return false;
    if (jsonEncode(e['chiave']) != jsonEncode(_chiave(s))) return true; // cambiato sito web / host / nome
    final quando = DateTime.fromMillisecondsSinceEpoch((e['quando'] as num?)?.toInt() ?? 0);
    final eta = adesso().difference(quando);
    // trovato: si rinnova dopo 30 giorni; non trovato (anche se resta quello vecchio): si riprova dopo 1 giorno
    if (e['fallito'] != true && file(s.id) != null) return eta > rinnovo;
    return eta > riprovaFallito;
  }

  /// Salva l'esito: [immagine] trovata, oppure null = non trovata (un logo vecchio resta, se c'è e non si [cancella]).
  Future<void> _scrivi(Sito s, (String, Uint8List)? immagine, String fonte,
      {bool manuale = false, bool cancella = false}) async {
    final d = await _cartella();
    _byte.remove(s.id);
    final vecchiaEst = _indice[s.id]?['est'];
    String? est = vecchiaEst as String?;
    if (immagine != null || cancella) {
      for (final e in ['png', 'svg']) {
        final f = File('${d.path}/${s.id}.$e');
        if (f.existsSync()) f.deleteSync();
      }
      est = null;
    }
    if (immagine != null) {
      await File('${d.path}/${s.id}.${immagine.$1}').writeAsBytes(immagine.$2);
      est = immagine.$1;
    }
    _indice[s.id] = {
      'quando': adesso().millisecondsSinceEpoch,
      'est': est,
      'fallito': immagine == null,
      'fonte': fonte,
      'manuale': manuale,
      'chiave': _chiave(s),
    };
    await _salvaIndice();
  }

  /// Prepara la cache e mette in coda i siti che ne hanno bisogno (solo se l'opzione è accesa).
  Future<void> prepara(List<Sito> siti) async {
    try {
      await _cartella();
    } catch (_) {
      return; // cartella non disponibile (es. nelle anteprime senza telefono)
    }
    await _carica();
    notifyListeners();
    if (!await acceso()) return;
    for (final s in siti) {
      if (daCercare(s)) richiedi(s);
    }
  }

  void richiedi(Sito s) {
    if (!_inCoda.add(s.id)) return;
    _coda.add(s.copia());
    _lavoraCoda();
  }

  Future<void> _lavoraCoda() async {
    if (_lavora) return;
    _lavora = true;
    try {
      while (_coda.isNotEmpty) {
        final s = _coda.removeFirst();
        try {
          if (await acceso()) await aggiorna(s);
        } catch (_) {}
        _inCoda.remove(s.id);
        notifyListeners();
      }
    } finally {
      _lavora = false;
    }
  }

  /// Cerca e salva il logo (con [forza] anche se in cache è recente). Ritorna il file o null.
  Future<File?> aggiorna(Sito s, {bool forza = false, List<String>? basi}) async {
    await _cartella();
    await _carica();
    if (!forza && !daCercare(s)) return file(s.id);
    final trovato = await cerca(basi ?? indirizziLogo(s));
    if (trovato == null) {
      // non trovato ora: col rinnovo automatico si tiene quello vecchio, con «Aggiorna logo» si toglie
      await _scrivi(s, null, '', cancella: forza);
    } else {
      await _scrivi(s, (trovato.$1, trovato.$2), trovato.$3);
    }
    notifyListeners();
    return file(s.id);
  }

  /// Immagine scelta dall'utente: non viene più cercata né rinnovata.
  Future<void> manuale(Sito s, Uint8List dati) async {
    await _cartella();
    await _carica();
    final n = await Isolate.run(() => normalizza(dati));
    if (n == null) throw 'Immagine non leggibile';
    await _scrivi(s, n, 'manuale', manuale: true);
    notifyListeners();
  }

  Future<void> dimentica(String id, {bool salva = true}) async {
    final d = await _cartella();
    _byte.remove(id);
    _indice.remove(id);
    for (final est in ['png', 'svg']) {
      final f = File('${d.path}/$id.$est');
      if (f.existsSync()) f.deleteSync();
    }
    if (salva) {
      await _salvaIndice();
      notifyListeners();
    }
  }

  @visibleForTesting
  void azzera() {
    _dir = null;
    _indice = {};
    _byte.clear();
    _caricato = false;
    _acceso = null;
    _coda.clear();
    _inCoda.clear();
  }
}
