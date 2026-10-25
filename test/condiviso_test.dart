// Compatibilità con tk-ftp per computer: formato FileZilla vero (RemoteDir, Logontype, Protocol) e file condiviso
// tk-ftp-siti.xml con le password cifrate.
//  - test/dati/condiviso-desktop.xml è scritto dal CODICE DEL COMPUTER (tools/condiviso_desktop.py genera …):
//    qui si decifra con lo stesso schema.
//  - il file scritto qui (build/condiviso-app.xml) si rilegge col codice del computer:
//    python tools/condiviso_desktop.py verifica <cartella tk-ftp-desktop> build/condiviso-app.xml
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tkftpmanager/cifratura.dart';
import 'package:tkftpmanager/filezilla.dart';
import 'package:tkftpmanager/modelli.dart';

const frase = 'Frase di prova è €';

Map<String, Sito> perHost(List<Sito> s) => {for (final x in s) x.host: x};

Map<String, Object?> senzaId(Sito s) => s.aJson(conPassword: true)..remove('id');

void main() {
  test('RemoteDir nel formato vero di FileZilla (e in quello delle prime app)', () {
    expect(decodificaCartella('1 0 3 www 6 public'), '/www/public');
    expect(decodificaCartella('1 0'), '/');
    expect(decodificaCartella('1 0 9 cartella  2 è!'), '/cartella /è!');
    expect(decodificaCartella('1 2 3 www 4 html'), '/www/html'); // vecchia app telefono
    expect(decodificaCartella('3 2 C: 3 www 4 html'), r'C:\www\html');
    expect(decodificaCartella('/già/percorso'), '/già/percorso');
    expect(decodificaCartella(''), '');
    expect(codificaCartella('/www/public'), '1 0 3 www 6 public');
    expect(codificaCartella('/'), '1 0');
    for (final p in ['/a', '/www/public', '/con spazio/x y', '/']) {
      expect(decodificaCartella(codificaCartella(p)), p);
    }
  });

  test('Logontype e Protocol senza confusioni, in import ed export', () {
    const xml = r'''<?xml version="1.0" encoding="UTF-8"?>
<FileZilla3 version="3.69.1" platform="windows"><Servers>
<Server><Host>a.it</Host><Port>21</Port><Protocol>0</Protocol><User>u</User><Pass encoding="base64">c2VncmV0YQ==</Pass><Logontype>1</Logontype><Name>Normale</Name><RemoteDir>1 0 3 www 6 public</RemoteDir></Server>
<Server><Host>b.it</Host><Port>21</Port><Protocol>6</Protocol><User>u</User><Logontype>2</Logontype><Name>Chiedi</Name></Server>
<Server><Host>c.it</Host><Port>21</Port><Protocol>0</Protocol><User>u</User><Logontype>3</Logontype><Name>Interattivo</Name></Server>
<Server><Host>d.it</Host><Port>21</Port><Protocol>0</Protocol><User></User><Logontype>0</Logontype><Name>Anonimo</Name></Server>
<Server><Host>e.it</Host><Port>65100</Port><Protocol>1</Protocol><User>root</User><Keyfile>C:\k\id_ed25519</Keyfile><Logontype>5</Logontype><Name>Chiave</Name></Server>
<Server><Host>f.it</Host><Port>990</Port><Protocol>3</Protocol><User>u</User><Pass encoding="base64">eA==</Pass><Logontype>1</Logontype><Name>Implicito</Name></Server>
<Server><Host>g.it</Host><Port>2121</Port><Protocol>3</Protocol><User>u</User><Logontype>2</Logontype><Name>Implicito su altra porta</Name></Server>
<Server><Host>h.it</Host><Protocol>4</Protocol><User>u</User><Pass encoding="crypt">xyz</Pass><Logontype>1</Logontype><Name>Bloccata</Name></Server>
<Server><Host>i.it</Host><Protocol>5</Protocol><User>u</User><Logontype>1</Logontype><Name>Storj</Name></Server>
</Servers></FileZilla3>''';
    final e = leggiFileZilla(xml);
    final s = perHost(e.siti);
    expect(e.saltati, 1);
    expect(e.bloccate, 1);
    expect(s['a.it']!.accesso, Accesso.normale);
    expect(s['a.it']!.password, 'segreta');
    expect(s['a.it']!.cartellaRemota, '/www/public');
    expect(s['b.it']!.accesso, Accesso.chiedi);
    expect(s['b.it']!.codiceFz, '6');
    expect(s['c.it']!.accesso, Accesso.chiedi);
    expect(s['d.it']!.accesso, Accesso.anonimo);
    expect(s['e.it']!.accesso, Accesso.chiave);
    expect(s['e.it']!.fileChiave, r'C:\k\id_ed25519');
    expect(s['f.it']!.tlsImplicito, isTrue);
    expect(s['g.it']!.tlsImplicito, isTrue);
    expect(s['h.it']!.tlsImplicito, isFalse);
    expect(s['h.it']!.porta, 21);
    expect(s['h.it']!.password, '');

    final doc = esportaFileZilla(e.siti);
    String campo(String host, String tag) =>
        RegExp('<Host>${RegExp.escape(host)}</Host>[\\s\\S]*?<$tag>([^<]*)</$tag>').firstMatch(doc)!.group(1)!;
    expect(campo('a.it', 'Logontype'), '1');
    expect(campo('b.it', 'Logontype'), '2');
    expect(campo('b.it', 'Protocol'), '6');
    expect(campo('d.it', 'Logontype'), '0');
    expect(campo('e.it', 'Logontype'), '5');
    expect(campo('e.it', 'Keyfile'), r'C:\k\id_ed25519');
    expect(campo('f.it', 'Protocol'), '3');
    expect(campo('g.it', 'Protocol'), '3');
    expect(campo('h.it', 'Protocol'), '4');
    expect(campo('a.it', 'RemoteDir'), '1 0 3 www 6 public');
    expect(doc, contains('<Pass encoding="base64">c2VncmV0YQ==</Pass>'));
    final di = perHost(leggiFileZilla(doc).siti);
    for (final h in s.keys) {
      expect(senzaId(di[h]!), senzaId(s[h]!), reason: h);
    }
  });

  test('file della vecchia app telefono (Pass senza encoding, Logontype 4)', () {
    const xml = '''<FileZilla3 version="3.66.4" platform="linux"><Servers>
<Server><Host>x.it</Host><Protocol>1</Protocol><User>u</User><Pass>cGFzcw==</Pass><Logontype>1</Logontype><RemoteDir>1 2 3 www 4 html</RemoteDir></Server>
<Server><Host>y.it</Host><Protocol>0</Protocol><User>u</User><Pass></Pass><Logontype>4</Logontype></Server>
</Servers></FileZilla3>''';
    final s = perHost(importaFileZilla(xml));
    expect(s['x.it']!.password, 'pass');
    expect(s['x.it']!.cartellaRemota, '/www/html');
    expect(s['y.it']!.accesso, Accesso.chiedi);
  });

  test('cifratura: stesso schema in andata e ritorno', () {
    final sale = byteCasuali(16);
    final k = derivaChiave('abc', sale, 1000);
    final b = sigilla(k, utf8.encode('ciao è'));
    expect(utf8.decode(apriSigillo(k, b)!), 'ciao è');
    expect(apriSigillo(derivaChiave('abd', sale, 1000), b), isNull);
  });

  test('file condiviso scritto da tk-ftp per COMPUTER: si decifra qui, e quello scritto qui torna al computer', () {
    final testo = File('test/dati/condiviso-desktop.xml').readAsStringSync();
    final senza = leggiFileZilla(testo);
    expect(senza.cifrato, isTrue);
    expect(senza.senzaFrase, isTrue);
    expect(senza.siti.length, 6);
    expect(senza.siti.every((s) => s.password.isEmpty), isTrue);
    expect(leggiFileZilla(testo, frase: 'sbagliata').fraseSbagliata, isTrue);

    final e = leggiFileZilla(testo, frase: frase);
    expect(e.fraseSbagliata, isFalse);
    expect(e.decifrate, 3);
    final s = perHost(e.siti);
    expect(s['ftp.chiaro.it']!.password, 'pässwörd €1');
    expect(s['ftp.chiaro.it']!.codiceFz, '6');
    expect(s['ftp.chiaro.it']!.cartellaRemota, '/www/public');
    expect(s['ftp.chiaro.it']!.gruppo, '1. Clienti');
    expect(s['ftps.implicito.it']!.password, 'x"<&>y');
    expect(s['ftps.implicito.it']!.tlsImplicito, isTrue);
    expect(s['ftps.implicito.it']!.gruppo, '1. Clienti/Napoli');
    expect(s['ftps.implicito.it']!.passivo, isFalse);
    expect(s['sftp.chiave.it']!.accesso, Accesso.chiave);
    expect(s['sftp.chiave.it']!.porta, 65100);
    expect(s['sftp.chiave.it']!.fileChiave, r'C:\Users\TecnikGeek\.ssh\id_ed25519');
    expect(s['sftp.chiave.it']!.cartellaRemota, '/var/www');
    expect(s['ftp.chiedi.it']!.accesso, Accesso.chiedi);
    expect(s['ftp.anonimo.it']!.accesso, Accesso.anonimo);
    expect(s['ftp.anonimo.it']!.cartellaRemota, '/pub');
    expect(s['ftps.esplicito.it']!.password, 'segreta');
    expect(s['ftps.esplicito.it']!.tlsImplicito, isFalse);
    // «Sito web (per il logo)» scritto sul computer (<TkWebsite>) arriva al telefono
    expect(s['ftp.chiaro.it']!.sitoWeb, 'www.chiaro.it');
    expect(s['sftp.chiave.it']!.sitoWeb, 'https://chiave.it/negozio');
    expect(s['ftps.esplicito.it']!.sitoWeb, 'esplicito.it');
    expect(s['ftp.chiedi.it']!.sitoWeb, '');

    // l'app riscrive il file: lo rilegge il codice del computer (tools/condiviso_desktop.py verifica)
    final scritto = esportaFileZilla(e.siti, conPassword: false, frase: frase);
    expect(scritto, isNot(contains('<Pass')));
    expect(scritto, contains('<TkPass>'));
    expect(scritto, contains('<TkWebsite>www.chiaro.it</TkWebsite>'));
    Directory('build').createSync(recursive: true);
    File('build/condiviso-app.xml').writeAsStringSync(scritto);
    final di = perHost(leggiFileZilla(scritto, frase: frase).siti);
    for (final h in s.keys) {
      expect(senzaId(di[h]!), senzaId(s[h]!), reason: h);
    }
    // senza frase e senza password: nessuna password nel file
    expect(esportaFileZilla(e.siti, conPassword: false), isNot(contains('Pass>')));
  });

  test("password solo in base64 contate (avviso di rifare l'export cifrato)", () {
    final siti = [
      Sito(nome: 'A', host: 'a.esempio.it', porta: 21, protocollo: Protocollo.ftp, accesso: Accesso.normale,
          utente: 'u', password: 'segreta'),
      Sito(nome: 'B', host: 'b.esempio.it', porta: 21, protocollo: Protocollo.ftp, accesso: Accesso.normale,
          utente: 'u', password: 'altra'),
    ];
    // export FileZilla (password in base64): da avvisare
    expect(leggiFileZilla(esportaFileZilla(siti)).inChiaro, 2);
    // file condiviso cifrato: niente avviso
    final cifrato = esportaFileZilla(siti, conPassword: false, frase: frase);
    expect(leggiFileZilla(cifrato, frase: frase).inChiaro, 0);
    // export delle prime app (base64 senza attributo encoding)
    const vecchio = '<?xml version="1.0"?><FileZilla3 version="3.66.4" platform="linux"><Servers><Server>'
        '<Host>c.esempio.it</Host><Port>21</Port><Protocol>0</Protocol><User>u</User><Pass>c2VncmV0YQ==</Pass>'
        '<Logontype>1</Logontype><Name>C</Name></Server></Servers></FileZilla3>';
    final e = leggiFileZilla(vecchio);
    expect(e.inChiaro, 1);
    expect(e.siti.single.password, 'segreta');
  });
}
