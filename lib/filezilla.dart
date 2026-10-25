// Gestore siti di FileZilla (sitemanager.xml) e file condiviso col computer (tk-ftp-siti.xml, stesso formato):
// lettura e scrittura allineate a tk-ftp per computer (tkftp/filezilla.py), comprese le password cifrate.
import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'cifratura.dart';
import 'modelli.dart';

/// Risultato della lettura di un file FileZilla / tk-ftp.
class EsitoImport {
  final siti = <Sito>[];

  /// Siti con protocolli che l'app non gestisce (HTTP, S3, …), lasciati fuori.
  int saltati = 0;

  /// Password protette dalla «password principale» di FileZilla: non si possono leggere.
  int bloccate = 0;

  /// Il file ha le password cifrate da tk-ftp (serve la frase segreta).
  bool cifrato = false;

  /// La frase data non apre il file.
  bool fraseSbagliata = false;

  /// Password cifrate effettivamente lette.
  int decifrate = 0;

  /// Password lette solo in base64 (export vecchi dell'app o di FileZilla): chi ha il file le può leggere.
  int inChiaro = 0;

  /// File cifrato letto senza frase: i siti ci sono, le password no.
  bool get senzaFrase => cifrato && decifrate == 0 && !fraseSbagliata && _senzaChiave;
  bool _senzaChiave = true;
}

/// Solo i siti (come prima): per chi non deve sapere altro.
List<Sito> importaFileZilla(String testo) => leggiFileZilla(testo).siti;

EsitoImport leggiFileZilla(String testo, {String? frase}) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(testo.startsWith('\uFEFF') ? testo.substring(1) : testo);
  } catch (_) {
    throw 'Il file non è un XML valido';
  }
  final radice = doc.rootElement;
  final XmlElement? servers = radice.name.local == 'FileZilla3'
      ? radice.findElements('Servers').firstOrNull
      : (radice.name.local == 'Servers' ? radice : null);
  if (servers == null) throw 'Formato XML non riconosciuto';
  final esito = EsitoImport();
  Uint8List? chiave;
  final tk = radice.findElements('TkFtp').firstOrNull;
  final sale = tk?.getAttribute('sale') ?? '';
  if (tk != null && sale.isNotEmpty) {
    esito.cifrato = true;
    if (frase != null && frase.isNotEmpty) {
      try {
        final iter = int.tryParse(tk.getAttribute('iterazioni') ?? '') ?? iterazioniTk;
        final k = derivaChiave(frase, base64.decode(sale), iter);
        final c = apriSigillo(k, tk.getAttribute('controllo') ?? '');
        if (c != null && utf8.decode(c, allowMalformed: true) == parolaControllo) {
          chiave = k;
          esito._senzaChiave = false;
        } else {
          esito.fraseSbagliata = true;
        }
      } catch (_) {
        esito.fraseSbagliata = true;
      }
    }
  }
  // Le prime tk-ftp per telefono scrivevano <Pass> in base64 senza l'attributo encoding.
  final vecchiaApp = radice.getAttribute('version') == '3.66.4' && radice.getAttribute('platform') == 'linux';
  _leggi(servers, '', esito, chiave, vecchiaApp);
  return esito;
}

void _leggi(XmlElement nodo, String prefisso, EsitoImport esito, Uint8List? chiave, bool vecchiaApp) {
  for (final e in nodo.childElements) {
    if (e.name.local == 'Server') {
      final s = _sito(e, prefisso, esito, chiave, vecchiaApp);
      if (s != null) esito.siti.add(s);
    } else if (e.name.local == 'Folder') {
      // il nome della cartella è il testo prima del primo elemento
      final nome =
          e.children.whereType<XmlText>().map((t) => t.value.trim()).firstWhere((t) => t.isNotEmpty, orElse: () => 'Gruppo');
      _leggi(e, prefisso.isEmpty ? nome : '$prefisso/$nome', esito, chiave, vecchiaApp);
    }
  }
}

String _testo(XmlElement e, String tag) => e.findElements(tag).firstOrNull?.innerText.trim() ?? '';

Sito? _sito(XmlElement e, String gruppo, EsitoImport esito, Uint8List? chiave, bool vecchiaApp) {
  final host = _testo(e, 'Host');
  if (host.isEmpty) return null;
  final codice = _testo(e, 'Protocol').isEmpty ? '0' : _testo(e, 'Protocol');
  final protocollo = switch (codice) {
    '0' || '6' => Protocollo.ftp,
    '3' || '4' => Protocollo.ftps,
    '1' => Protocollo.sftp,
    _ => null,
  };
  if (protocollo == null) {
    esito.saltati++;
    return null;
  }
  var password = '';
  final pe = e.findElements('Pass').firstOrNull;
  if (pe != null && pe.innerText.isNotEmpty) {
    final codifica = (pe.getAttribute('encoding') ?? '').toLowerCase();
    if (codifica == 'base64' || (codifica.isEmpty && vecchiaApp)) {
      try {
        password = utf8.decode(base64.decode(pe.innerText.trim()));
        if (password.isNotEmpty) esito.inChiaro++;
      } catch (_) {
        password = codifica.isEmpty ? pe.innerText : '';
      }
    } else if (codifica == 'crypt') {
      esito.bloccate++;
    } else {
      password = pe.innerText;
    }
  }
  final tkPass = _testo(e, 'TkPass');
  if (tkPass.isNotEmpty && chiave != null) {
    final p = apriSigillo(chiave, tkPass);
    if (p != null) {
      password = utf8.decode(p, allowMalformed: true);
      esito.decifrate++;
    }
  }
  final lt = _testo(e, 'Logontype').isEmpty ? '1' : _testo(e, 'Logontype');
  var accesso = switch (lt) {
    '0' => Accesso.anonimo,
    '2' || '3' => Accesso.chiedi,
    '5' => Accesso.chiave,
    _ => Accesso.normale,
  };
  // «4» in FileZilla è «account»; le prime tk-ftp per telefono lo usavano per «chiedi la password»
  if (lt == '4') accesso = vecchiaApp || password.isEmpty ? Accesso.chiedi : Accesso.normale;
  final fileChiave = _testo(e, 'Keyfile');
  if (fileChiave.isNotEmpty && protocollo == Protocollo.sftp && accesso != Accesso.anonimo) {
    if (lt == '5' || password.isEmpty) accesso = Accesso.chiave;
  }
  final predefinita = protocollo == Protocollo.sftp ? 22 : (codice == '3' ? 990 : 21);
  final porta = int.tryParse(_testo(e, 'Port')) ?? 0;
  final remota = decodificaCartella(_testo(e, 'RemoteDir'));
  return Sito(
    nome: _testo(e, 'Name').isEmpty ? host : _testo(e, 'Name'),
    host: host,
    porta: porta > 0 ? porta : predefinita,
    protocollo: protocollo,
    codiceFz: codice,
    accesso: accesso,
    utente: _testo(e, 'User'),
    password: accesso == Accesso.normale ? password : '',
    fileChiave: fileChiave,
    cartellaRemota: remota.isEmpty ? '/' : remota,
    cartellaLocale: _testo(e, 'LocalDir'),
    passivo: _testo(e, 'PasvMode') != 'MODE_ACTIVE',
    note: _testo(e, 'Comments'),
    gruppo: gruppo,
    sitoWeb: _testo(e, 'TkWebsite'),
  );
}

// ------------------------------------------------------------------ cartella remota (RemoteDir)

/// FileZilla salva la cartella come «tipo lunghezza_prefisso [prefisso] (lunghezza segmento)…»:
/// «1 0 3 www 6 public» = /www/public, «1 0» = /. Accetta anche il formato delle prime tk-ftp per telefono
/// («1 N l1 s1 …», con N = numero di segmenti).
String decodificaCartella(String grezza) {
  final r = grezza.trim();
  if (r.isEmpty) return '';
  if (!RegExp(r'^\d').hasMatch(r)) return r; // già un percorso
  final vera = _percorsoSicuro(r);
  if (vera != null) return vera;
  try {
    final t = r.split(' ');
    final n = int.parse(t[1]);
    var i = 2;
    final parti = <String>[];
    for (var k = 0; k < n; k++) {
      final l = int.parse(t[i]);
      final s = t[i + 1];
      parti.add(s.length > l ? s.substring(0, l) : s);
      i += 2;
    }
    return '/${parti.join('/')}';
  } catch (_) {
    return '';
  }
}

String? _percorsoSicuro(String r) {
  var pos = 0;
  int numero() {
    final inizio = pos;
    while (pos < r.length && r.codeUnitAt(pos) >= 48 && r.codeUnitAt(pos) <= 57) {
      pos++;
    }
    if (pos == inizio) throw const FormatException();
    return int.parse(r.substring(inizio, pos));
  }

  void spazio() {
    if (pos >= r.length || r[pos] != ' ') throw const FormatException();
    pos++;
  }

  final int tipo;
  var prefisso = '';
  final segmenti = <String>[];
  try {
    tipo = numero();
    spazio();
    final lp = numero();
    if (lp > 0) {
      spazio();
      if (pos + lp > r.length) throw const FormatException();
      prefisso = r.substring(pos, pos + lp);
      pos += lp;
    }
    while (pos < r.length) {
      spazio();
      final l = numero();
      spazio();
      if (pos + l > r.length) throw const FormatException();
      segmenti.add(r.substring(pos, pos + l));
      pos += l;
    }
  } on FormatException {
    return null;
  }
  if (tipo == 3 || prefisso.endsWith(':')) {
    // server Windows/DOS: C:\a\b
    return prefisso.isNotEmpty ? '$prefisso\\${segmenti.join('\\')}' : segmenti.join('\\');
  }
  return '/${segmenti.join('/')}';
}

String codificaCartella(String p) {
  final t = p.trim();
  if (t.isEmpty) return '';
  if (t == '/') return '1 0';
  final parti = t.replaceAll('\\', '/').split('/').where((x) => x.isNotEmpty);
  return '1 0${parti.map((x) => ' ${x.length} $x').join()}';
}

// ------------------------------------------------------------------ scrittura

String _codiceProtocollo(Sito s) => switch (s.protocollo) {
      Protocollo.sftp => '1',
      Protocollo.ftps => s.tlsImplicito ? '3' : '4',
      Protocollo.ftp => s.codiceFz == '6' ? '6' : '0',
    };

String _codiceAccesso(Accesso a) => switch (a) {
      Accesso.anonimo => '0',
      Accesso.normale => '1',
      Accesso.chiedi => '2',
      Accesso.chiave => '5',
    };

/// Documento FileZilla. [frase]: le password vanno cifrate (`<TkPass>`, file condiviso col computer);
/// senza frase e con [conPassword] vanno in base64 come fa FileZilla; altrimenti niente password.
String esportaFileZilla(List<Sito> siti, {bool conPassword = true, String? frase}) {
  Uint8List? chiave;
  final b = XmlBuilder();
  b.processing('xml', 'version="1.0" encoding="UTF-8" standalone="yes"');
  b.element('FileZilla3', attributes: {'version': '3.70.6', 'platform': 'android'}, nest: () {
    if (frase != null && frase.isNotEmpty) {
      final sale = byteCasuali(16);
      chiave = derivaChiave(frase, sale);
      b.element('TkFtp', attributes: {
        'versione': '1',
        'cifratura': cifraturaTk,
        'iterazioni': '$iterazioniTk',
        'sale': base64.encode(sale),
        'controllo': sigilla(chiave!, utf8.encode(parolaControllo)),
      });
    }
    b.element('Servers', nest: () {
      void server(Sito s) => b.element('Server', nest: () {
            void campo(String t, String v) => b.element(t, nest: v);
            campo('Host', s.host);
            campo('Port', '${s.porta}');
            campo('Protocol', _codiceProtocollo(s));
            campo('Type', '0');
            campo('User', s.utente);
            if (s.password.isNotEmpty && s.accesso == Accesso.normale) {
              if (chiave != null) {
                campo('TkPass', sigilla(chiave!, utf8.encode(s.password)));
              } else if (conPassword) {
                b.element('Pass', attributes: {'encoding': 'base64'}, nest: base64.encode(utf8.encode(s.password)));
              }
            }
            if (s.fileChiave.isNotEmpty) campo('Keyfile', s.fileChiave);
            campo('Logontype', _codiceAccesso(s.accesso));
            campo('TimezoneOffset', '0');
            campo('PasvMode', s.passivo ? 'MODE_PASSIVE' : 'MODE_ACTIVE');
            campo('MaximumMultipleConnections', '0');
            campo('EncodingType', 'Auto');
            campo('BypassProxy', '0');
            campo('Name', s.nomeVisibile);
            if (s.note.isNotEmpty) campo('Comments', s.note);
            if (s.cartellaLocale.isNotEmpty) campo('LocalDir', s.cartellaLocale);
            final remota = codificaCartella(s.cartellaRemota);
            if (remota.isNotEmpty) campo('RemoteDir', remota);
            // campo di tk-ftp (FileZilla lo ignora): stesso nome che usa tk-ftp per computer
            if (s.sitoWeb.isNotEmpty) campo('TkWebsite', s.sitoWeb);
            campo('SyncBrowsing', '0');
            campo('DirectoryComparison', '0');
          });

      // gruppi annidati come FileZilla: «Clienti/Napoli» = cartella Napoli dentro Clienti
      final ordinati = [...siti]..sort((a, c) {
          final g = a.gruppo.toLowerCase().compareTo(c.gruppo.toLowerCase());
          return g != 0 ? g : a.nomeVisibile.toLowerCase().compareTo(c.nomeVisibile.toLowerCase());
        });
      for (final s in ordinati.where((s) => s.gruppo.isEmpty)) {
        server(s);
      }
      final albero = _Nodo();
      for (final s in ordinati.where((s) => s.gruppo.isNotEmpty)) {
        var n = albero;
        for (final parte in s.gruppo.split('/').where((p) => p.trim().isNotEmpty)) {
          n = n.figli.putIfAbsent(parte.trim(), _Nodo.new);
        }
        n.siti.add(s);
      }
      void cartella(String nome, _Nodo n) => b.element('Folder', attributes: {'expanded': '1'}, nest: () {
            b.text(nome);
            n.figli.forEach(cartella);
            n.siti.forEach(server);
          });
      albero.figli.forEach(cartella);
    });
  });
  return b.buildDocument().toXmlString(pretty: true, indent: '    ');
}

class _Nodo {
  final figli = <String, _Nodo>{};
  final siti = <Sito>[];
}
