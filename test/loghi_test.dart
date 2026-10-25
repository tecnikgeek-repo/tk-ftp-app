// Loghi dei siti: dove cercare, scelta dell'icona, ripieghi e cache, contro un server HTTP finto locale
// (stesse prove di tests/test_logos.py di tk-ftp per computer).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tkftpmanager/loghi.dart';
import 'package:tkftpmanager/modelli.dart';

Uint8List png(int lato) => Uint8List.fromList(img.encodePng(img.Image(width: lato, height: lato)..clear(img.ColorRgb8(200, 30, 30))));

Uint8List ico(List<int> lati) =>
    Uint8List.fromList(img.IcoEncoder().encodeImages([for (final l in lati) img.Image(width: l, height: l)]));

const svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="red"/></svg>';

late HttpServer server;
late String base;
var richieste = <String>[];

Future<void> avviaServer() async {
  server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  base = 'http://127.0.0.1:${server.port}';
  server.listen((r) async {
    richieste.add(r.uri.path);
    final res = r.response;
    void html(String corpo, {int stato = 200}) {
      res.statusCode = stato;
      res.headers.contentType = ContentType.html;
      res.write('<html><head>$corpo</head><body></body></html>');
    }

    void byte(Uint8List b, String tipo) {
      res.headers.set('content-type', tipo);
      res.add(b);
    }

    switch (r.uri.path) {
      case '/grande/':
        html('<link rel="icon" href="/p16.png" sizes="16x16"><link rel="apple-touch-icon" href="/p180.png">');
      case '/misure/':
        html('<link rel="icon" href="/p16.png" sizes="16x16"><link rel="icon" href="/p64.png" sizes="64x64">');
      case '/svg/':
        html('<link rel="icon" href="/p16.png"><link rel="icon" type="image/svg+xml" href="/logo.svg">');
      case '/manutenzione/':
        html('<link rel="icon" href="/p64.png" sizes="64x64">', stato: 503);
      case '/vietato/':
        html("<link rel='shortcut icon' href='/p64.png'>", stato: 403);
      case '/vai':
        res.statusCode = 302;
        res.headers.set('location', '/grande/');
      case '/base/':
        html('<base href="/sotto/"><link rel="icon" href="p64.png">');
      case '/sotto/p64.png' || '/p64.png':
        byte(png(64), 'image/png');
      case '/p16.png':
        byte(png(16), 'image/png');
      case '/p180.png':
        byte(png(180), 'image/png');
      case '/grosso.png':
        byte(png(600), 'image/png');
      case '/logo.svg':
        byte(Uint8List.fromList(utf8.encode(svg)), 'text/plain'); // tipo sbagliato: si riconosce dai byte
      case '/finto/':
        html('<link rel="icon" href="/nonimmagine.png"><link rel="icon" href="/tiposbagliato">');
      case '/nonimmagine.png':
        html('errore');
      case '/tiposbagliato':
        byte(png(48), 'application/octet-stream');
      case '/vuoto/':
        html('');
      case '/favicon.ico':
        byte(ico([16, 48, 32]), 'image/x-icon');
      case '/enorme/':
        html('<link rel="icon" href="/grosso.png">');
      default:
        res.statusCode = 404;
        res.headers.contentType = ContentType.text;
        res.write('non trovato');
    }
    await res.close();
  });
}

Future<(String, int)> trova(String percorso) async {
  final r = await cercaLogo(['$base$percorso']);
  expect(r, isNotNull, reason: percorso);
  if (r!.$1 == 'svg') return ('svg', 0);
  return (r.$1, img.decodePng(r.$2)!.width);
}

void main() {
  setUpAll(() async {
    HttpOverrides.global = null;
    await avviaServer();
  });
  tearDownAll(() => server.close(force: true));

  test('dove cercare: come il computer', () {
    expect(indirizziLogo(Sito(host: 'ftp.pietrodefilippis.it', nome: 'Sito mio')), ['https://pietrodefilippis.it']);
    expect(indirizziLogo(Sito(host: 'sftp.www.esempio.it', nome: 'x y')), ['https://esempio.it']);
    expect(indirizziLogo(Sito(host: 'hostingssd54.netsons.net', nome: 'almacolorificio')),
        ['https://almacolorificio.it', 'https://almacolorificio.com']);
    expect(indirizziLogo(Sito(host: '93.184.216.34', nome: 'garageputeoli.it')), ['https://garageputeoli.it']);
    expect(indirizziLogo(Sito(host: 'srv12.provider.com', nome: 'Garage Puteoli')), isEmpty);
    expect(indirizziLogo(Sito(host: 'ftp.aruba.it', nome: 'www.cliente.it')), ['https://cliente.it']);
    expect(indirizziLogo(Sito(host: '1.2.3.4', nome: 'x', sitoWeb: 'www.cliente.it/')), ['https://www.cliente.it']);
    expect(indirizziLogo(Sito(host: '1.2.3.4', sitoWeb: 'http://a.it/b')), ['http://a.it/b']);
  });

  test('icone in ordine: SVG, misura, apple-touch, poi /favicon.ico', () {
    final u = indirizziIcone('https://a.it/pagina/', '''
<link rel="icon" href="/f32.png" sizes="32x32"><link rel="apple-touch-icon" href="t.png">
<link rel="mask-icon" href="/m.svg"><LINK REL="icon" TYPE="image/svg+xml" HREF="/s.svg"><link rel="icon" href="//cdn.it/x.png" sizes="96x96">''');
    expect(u, [
      'https://a.it/s.svg',
      'https://a.it/pagina/t.png',
      'https://cdn.it/x.png',
      'https://a.it/f32.png',
      'https://a.it/favicon.ico',
    ]);
  });

  test('immagini riconosciute dai byte', () {
    expect(tipoImmagine(png(10)), 'png');
    expect(tipoImmagine(ico([16])), 'ico');
    expect(tipoImmagine(Uint8List.fromList(utf8.encode('<?xml version="1.0"?>\n$svg'))), 'svg');
    expect(tipoImmagine(Uint8List.fromList(utf8.encode('<html>no</html>'))), isNull);
  });

  test('server finto: scelta della più grande, SVG, pagine in errore, redirect, ripieghi', () async {
    expect(await trova('/grande/'), ('png', 180));
    expect(await trova('/misure/'), ('png', 64));
    expect(await trova('/svg/'), ('svg', 0));
    expect(await trova('/manutenzione/'), ('png', 64)); // 503 con HTML
    expect(await trova('/vietato/'), ('png', 64)); // 403 con HTML
    expect(await trova('/vai'), ('png', 180)); // redirect
    expect(await trova('/base/'), ('png', 64)); // <base href>
    expect(await trova('/finto/'), ('png', 48)); // HTML spacciato per PNG scartato, tipo sbagliato riconosciuto
    expect(await trova('/vuoto/'), ('png', 48)); // nessun link: /favicon.ico, la misura più grande dell'ICO
    expect(await trova('/non-esiste/'), ('png', 48)); // home 404 senza HTML: /favicon.ico lo stesso
    expect(await trova('/enorme/'), ('png', 256)); // ridotto a 256
    expect(await cercaLogo(['http://127.0.0.1:1/']), isNull); // niente server
  });

  test('cache: 30 giorni, nuovo tentativo dopo 1 giorno, manuale, spento = nessuna richiesta', () async {
    SharedPreferences.setMockInitialValues({});
    final dir = await Directory.systemTemp.createTemp('loghi');
    final l = Loghi.istanza
      ..azzera()
      ..cartellaBase = (() async => dir);
    var ora = DateTime(2026, 10, 19);
    l.adesso = () => ora;
    var chiamate = 0;
    Uint8List? risposta = png(64);
    l.cerca = (basi) async {
      chiamate++;
      return risposta == null ? null : ('png', risposta, '$base/p64.png');
    };
    final s = Sito(host: 'ftp.esempio.it', nome: 'Esempio');
    expect(await l.aggiorna(s), isNotNull);
    expect(chiamate, 1);
    ora = ora.add(const Duration(days: 29));
    await l.aggiorna(s);
    expect(chiamate, 1, reason: 'entro 30 giorni non si ricerca');
    ora = ora.add(const Duration(days: 2));
    await l.aggiorna(s);
    expect(chiamate, 2, reason: 'dopo 30 giorni si rinnova');

    // non trovato: il vecchio resta, si riprova dopo 1 giorno
    risposta = null;
    s.sitoWeb = 'nuovo.it'; // cambiato: si ricerca subito
    expect(await l.aggiorna(s), isNotNull, reason: 'il logo vecchio resta');
    expect(chiamate, 3);
    ora = ora.add(const Duration(hours: 20));
    await l.aggiorna(s);
    expect(chiamate, 3);
    ora = ora.add(const Duration(hours: 5));
    await l.aggiorna(s);
    expect(chiamate, 4);
    // «Aggiorna logo» non trovato: tolto, e la scheda lo dice
    await l.aggiorna(s, forza: true);
    expect(l.file(s.id), isNull);
    expect(l.fallito(s.id), isTrue);

    // scelto a mano: mai più ricercato
    await l.manuale(s, png(300));
    expect(img.decodePng(l.file(s.id)!.readAsBytesSync())!.width, 256);
    ora = ora.add(const Duration(days: 400));
    await l.aggiorna(s);
    expect(chiamate, 5, reason: 'manuale: nessuna ricerca');

    // la cache si rilegge dal disco
    l.azzera();
    l.cartellaBase = () async => dir;
    l.adesso = () => ora;
    await l.prepara([]);
    expect(l.file(s.id), isNotNull);

    // spento: nessuna richiesta di rete
    richieste.clear();
    l
      ..azzera()
      ..cartellaBase = (() async => await Directory.systemTemp.createTemp('loghi2'))
      ..cerca = cercaLogo;
    await l.impostaAcceso(false);
    await l.prepara([Sito(host: '127.0.0.1', nome: 'x', sitoWeb: '$base/grande/')]);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(richieste, isEmpty);
    await l.impostaAcceso(true);
    await l.prepara([Sito(host: '127.0.0.1', nome: 'x', sitoWeb: '$base/grande/')]);
    for (var i = 0; i < 50 && richieste.length < 2; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(richieste, contains('/grande/'));
  });
}
