// Server da verificare: FTPS con certificato autofirmato e SFTP mai visto si fermano PRIMA della password e
// chiedono; accettata l'impronta si entra; se l'impronta cambia ci si ferma di nuovo.
// Uso: server di prova di tk-ftp per computer (tests/servers.py <radice> 2121: 2122 FTPS, 2123 FTPS implicito,
// 2124 SFTP), poi  FTP=1 flutter test test/fiducia_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tkftpmanager/connessione.dart';
import 'package:tkftpmanager/fiducia.dart';
import 'package:tkftpmanager/modelli.dart';

final conServer = Platform.environment['FTP'] == '1';

Future<void> giro(Sito s, TipoFiducia tipo) async {
  SharedPreferences.setMockInitialValues({});
  // 1. server mai visto: domanda, niente accesso
  DomandaFiducia? d;
  try {
    await Connessione.per(s).apri(s, 'segreta');
  } on DomandaFiducia catch (e) {
    d = e;
  }
  expect(d, isNotNull, reason: 'un server mai visto deve fermarsi');
  expect(d!.tipo, tipo);
  expect(d.vecchia, isNull);
  expect(d.impronta, isNotEmpty);

  // 2. accettato: si entra e si lavora
  await Fiducia.ricorda(tipo, s.host, s.porta, d.impronta);
  final c = Connessione.per(s);
  await c.apri(s, 'segreta');
  await c.elenca('/');
  await c.chiudi();

  // 3. impronta diversa da quella accettata (come un server finto in mezzo): ci si ferma di nuovo
  await Fiducia.ricorda(tipo, s.host, s.porta, 'impronta-di-un-altro-server');
  DomandaFiducia? cambiata;
  try {
    await Connessione.per(s).apri(s, 'segreta');
  } on DomandaFiducia catch (e) {
    cambiata = e;
  }
  expect(cambiata, isNotNull, reason: 'un server cambiato deve fermarsi');
  expect(cambiata!.vecchia, 'impronta-di-un-altro-server');
  expect(cambiata.impronta, d.impronta);
}

void main() {
  test('FTPS esplicito autofirmato', () async {
    if (!conServer) return markTestSkipped('server non avviato');
    await giro(Sito(host: '127.0.0.1', porta: 2122, protocollo: Protocollo.ftps, utente: 'prova'),
        TipoFiducia.certificato);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('FTPS implicito autofirmato', () async {
    if (!conServer) return markTestSkipped('server non avviato');
    await giro(Sito(host: '127.0.0.1', porta: 2123, protocollo: Protocollo.ftps, utente: 'prova', codiceFz: '3'),
        TipoFiducia.certificato);
  }, timeout: const Timeout(Duration(seconds: 60)));

  test('SFTP mai visto', () async {
    if (!conServer) return markTestSkipped('server non avviato');
    await giro(Sito(host: '127.0.0.1', porta: 2124, protocollo: Protocollo.sftp, utente: 'prova'), TipoFiducia.chiave);
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('a capo nei nomi rifiutato prima di arrivare al server', () async {
    if (!conServer) return markTestSkipped('server non avviato');
    SharedPreferences.setMockInitialValues({});
    final s = Sito(host: '127.0.0.1', porta: 2121, protocollo: Protocollo.ftp, utente: 'prova');
    final c = Connessione.per(s);
    await c.apri(s, 'segreta');
    await expectLater(c.creaCartella('/a\r\nDELE /b'), throwsA(contains('a capo')));
    await c.chiudi();
  }, timeout: const Timeout(Duration(seconds: 30)));
}
