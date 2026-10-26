// Prova del client FTP/FTPS contro un server vero sul PC (pyftpdlib: 2121 FTP, 2122 FTPS esplicito)
// e prove senza rete di elenchi Unix/Windows/MLSD e di FileZilla.
// Uso: avviare server.py, poi  FTP=1 RADICE=<cartella del server> flutter test
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tkftpmanager/connessione.dart';
import 'package:tkftpmanager/editor.dart';
import 'package:tkftpmanager/fiducia.dart';
import 'package:tkftpmanager/filezilla.dart';
import 'package:tkftpmanager/modelli.dart';

final conServer = Platform.environment['FTP'] == '1';

Future<void> giro(Protocollo p, int porta) async {
  final s = Sito(host: '127.0.0.1', porta: porta, protocollo: p, utente: 'prova', password: 'segreta');
  final c = Connessione.per(s);
  final sbagliata = Connessione.per(s);
  await expectLater(sbagliata.apri(s, 'no'), throwsA(contains('Autenticazione fallita')));
  await sbagliata.chiudi();
  await c.apri(s, 'segreta');
  final tmp = await Directory.systemTemp.createTemp('tkftp');
  final locale = File('${tmp.path}/prova è.txt')..writeAsStringSync('Ciao «mondo» èà ${'x' * 200000}');
  await c.creaCartella('/cartella prova');
  int ultimo = 0;
  await c.carica(locale, '/cartella prova/prova è.txt', avanzamento: (f, t) => ultimo = f);
  expect(ultimo, locale.lengthSync());
  final elenco = await c.elenca('/cartella prova');
  expect(elenco.map((f) => f.nome), contains('prova è.txt'));
  expect(elenco.first.dimensione, locale.lengthSync());
  final radice = await c.elenca('/');
  expect(radice.firstWhere((f) => f.nome == 'cartella prova').cartella, isTrue);
  await c.rinomina('/cartella prova/prova è.txt', '/cartella prova/rinominato.txt');
  final giu = File('${tmp.path}/giu.txt');
  await c.scarica('/cartella prova/rinominato.txt', giu, avanzamento: (f, t) => ultimo = f);
  expect(giu.readAsStringSync(), locale.readAsStringSync());
  await c.creaCartella('/cartella prova/sotto');
  await c.carica(locale, '/cartella prova/sotto/a.txt');
  await c.eliminaCartella('/cartella prova');
  expect((await c.elenca('/')).where((f) => f.nome == 'cartella prova'), isEmpty);
  await c.chiudi();
}

void main() {
  test('FTP sul server di prova', () async {
    if (!conServer) return markTestSkipped('server non avviato');
    await giro(Protocollo.ftp, 2121);
  }, timeout: const Timeout(Duration(seconds: 60)));

  // pyftpdlib su Windows si blocca quando un client chiude il TLS di un caricamento: in FTPS qui si prova
  // tutto tranne il caricamento (il file lo mette il test direttamente nella cartella del server).
  test('FTPS esplicito sul server di prova', () async {
    if (!conServer) return markTestSkipped('server non avviato');
    final radice = Platform.environment['RADICE']!;
    final s = Sito(host: '127.0.0.1', porta: 2122, protocollo: Protocollo.ftps, utente: 'prova', password: 'segreta');
    // certificato autofirmato del server di prova: accettato come farebbe l'utente (vedi fiducia_test.dart)
    SharedPreferences.setMockInitialValues({});
    try {
      await Connessione.per(s).apri(s, 'segreta');
    } on DomandaFiducia catch (d) {
      await Fiducia.ricorda(d.tipo, d.host, d.porta, d.impronta);
    }
    final c = Connessione.per(s);
    await c.apri(s, 'segreta');
    await c.creaCartella('/sicura');
    final testo = 'FTPS «ok» èà ${'y' * 150000}';
    File('$radice/sicura/dato è.txt').writeAsStringSync(testo);
    final elenco = await c.elenca('/sicura');
    expect(elenco.single.nome, 'dato è.txt');
    final tmp = await Directory.systemTemp.createTemp('tkftps');
    final giu = File('${tmp.path}/g.txt');
    await c.scarica('/sicura/dato è.txt', giu);
    expect(giu.readAsStringSync(), testo);
    await c.rinomina('/sicura/dato è.txt', '/sicura/b.txt');
    await c.eliminaCartella('/sicura');
    expect((await c.elenca('/')).where((f) => f.nome == 'sicura'), isEmpty);
    await c.chiudi();
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('elenchi Unix, Windows e MLSD', () {
    final u = leggiList('drwxr-xr-x    2 user group     4096 Jan  5 12:30 public html', '/www')!;
    expect(u.nome, 'public html');
    expect(u.cartella, isTrue);
    expect(u.percorso, '/www/public html');
    final l = leggiList('lrwxrwxrwx 1 u g 11 Mar 3 2021 web -> public_html', '/')!;
    expect(l.nome, 'web');
    expect(l.cartella, isTrue);
    final f = leggiList('-rw-r--r-- 1 u g 1234 Feb 10 2024 index.php', '/')!;
    expect(f.dimensione, 1234);
    expect(f.modificato!.year, 2024);
    final d = leggiList('01-15-24  03:45PM       <DIR>          immagini', '/')!;
    expect(d.cartella, isTrue);
    expect(d.modificato!.hour, 15);
    final w = leggiList('01-15-24  09:05AM              5120 foto.jpg', '/')!;
    expect(w.dimensione, 5120);
    final m = leggiMlsd('type=file;size=42;modify=20240102030405; nome con spazi.txt', '/a')!;
    expect(m.nome, 'nome con spazi.txt');
    expect(m.dimensione, 42);
    expect(leggiMlsd('type=cdir; .', '/'), isNull);
  });

  test('FileZilla: import ed export', () {
    const xml = '''<?xml version="1.0" encoding="UTF-8"?>
<FileZilla3 version="3.66.4" platform="linux"><Servers>
<Server><Host>ftp.uno.it</Host><Port>21</Port><Protocol>0</Protocol><User>u1</User><Pass encoding="base64">c2VncmV0YQ==</Pass><Logontype>1</Logontype><Name>Uno</Name><RemoteDir>1 2 3 www 4 html</RemoteDir><PasvMode>MODE_ACTIVE</PasvMode></Server>
<Folder expanded="1">Clienti
<Server><Host>sftp.due.it</Host><Port>22</Port><Protocol>1</Protocol><User>u2</User><Pass>cGFzcw==</Pass><Logontype>4</Logontype><Name>Due</Name></Server>
</Folder></Servers></FileZilla3>''';
    final siti = importaFileZilla(xml);
    expect(siti.length, 2);
    expect(siti[0].password, 'segreta');
    expect(siti[0].cartellaRemota, '/www/html');
    expect(siti[0].passivo, isFalse);
    expect(siti[1].gruppo, 'Clienti');
    expect(siti[1].protocollo, Protocollo.sftp);
    expect(siti[1].accesso, Accesso.chiedi);
    final di = importaFileZilla(esportaFileZilla(siti));
    expect(di.map((s) => '${s.nome}|${s.host}|${s.password}|${s.cartellaRemota}|${s.gruppo}'),
        siti.map((s) => '${s.nome}|${s.host}|${s.password}|${s.cartellaRemota}|${s.gruppo}'));
    expect(() => importaFileZilla('<pippo/>'), throwsA(contains('non riconosciuto')));
  });

  test('editor: Windows-1252 avanti e indietro', () {
    const t = 'Perché € “citazione” — caffè';
    expect(windows1252Decodifica(windows1252Codifica(t)), t);
  });
}
