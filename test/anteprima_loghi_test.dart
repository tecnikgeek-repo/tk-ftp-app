// Schermata della lista siti con i loghi VERI scaricati dai siti (serve la rete): build/anteprime/loghi-*.png.
// Uso:  LOGHI_VERI=1 flutter test test/anteprima_loghi_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tkftpmanager/esplora.dart';
import 'package:tkftpmanager/connessione.dart';
import 'package:tkftpmanager/loghi.dart';
import 'package:tkftpmanager/modelli.dart';
import 'package:tkftpmanager/modifica_sito.dart';
import 'package:tkftpmanager/siti.dart';
import 'package:tkftpmanager/tema.dart';

final veri = Platform.environment['LOGHI_VERI'] == '1';

Future<void> _caratteri() async {
  final dir = '${Platform.environment['FLUTTER_ROOT'] ?? r'C:\dev\flutter'}/bin/cache/artifacts/material_fonts';
  final roboto = FontLoader('Roboto');
  for (final f in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
    final file = File('$dir/$f');
    if (file.existsSync()) roboto.addFont(Future.value(ByteData.view(file.readAsBytesSync().buffer)));
  }
  await roboto.load();
  final icone = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.view(File('$dir/MaterialIcons-Regular.otf').readAsBytesSync().buffer)));
  await icone.load();
}

Future<void> _scatta(WidgetTester t, Widget w, String nome) async {
  final k = GlobalKey();
  await t.pumpWidget(RepaintBoundary(key: k, child: MaterialApp(debugShowCheckedModeBanner: false, theme: temaKit(), home: w)));
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await t.pump(const Duration(milliseconds: 300));
  }
  await t.runAsync(() async {
    final img = await (k.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/anteprime').createSync(recursive: true);
    File('build/anteprime/$nome.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  await t.pump(const Duration(milliseconds: 500));
}

final siti = [
  Sito(id: 'pd', nome: 'pietrodefilippis.it', host: 'ftp.pietrodefilippis.it', protocollo: Protocollo.sftp, porta: 65100, utente: 'aahdrftt'),
  Sito(id: 'alma', nome: 'almacolorificio', host: 'hostingssd54.netsons.net', utente: 'alma', gruppo: '1. Clienti'),
  Sito(id: 'garage', nome: 'Garage Puteoli', host: '93.184.216.34', sitoWeb: 'garageputeoli.it', protocollo: Protocollo.ftps, utente: 'garage', gruppo: '1. Clienti'),
  Sito(id: 'senza', nome: 'Server di prova', host: '10.0.0.5', utente: 'prova'),
];

void main() {
  setUpAll(_caratteri);

  testWidgets('loghi veri nella lista siti', (t) async {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({'siti': jsonEncode([for (final s in siti) s.aJson()])});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'), (c) async => null);
    final dir = await t.runAsync(() => Directory.systemTemp.createTemp('loghi-veri'));
    final l = Loghi.istanza
      ..azzera()
      ..cartellaBase = (() async => dir!);
    final esiti = await t.runAsync(() async {
      final out = <String>[];
      for (final s in siti) {
        final sw = Stopwatch()..start();
        final f = await l.aggiorna(s, forza: true);
        out.add('${s.nome}: ${f == null ? 'NESSUN LOGO' : '${f.path.split('.').last} ${f.lengthSync()} byte'} '
            '(${indirizziLogo(s).join(', ')}) ${sw.elapsedMilliseconds} ms');
      }
      return out;
    });
    File('build/anteprime/loghi-esiti.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync(esiti!.join('\n'));
    configTk = configFtp;
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;
    await _scatta(t, const SchermataSiti(), 'loghi-lista');
    t.view.physicalSize = const Size(780, 3600);
    await _scatta(t, SchermataModificaSito(sito: siti[1], gruppi: const ['1. Clienti']), 'loghi-scheda');
    t.view.physicalSize = const Size(780, 1688);
    await _scatta(t, SchermataEsplora(sito: siti[0], connessione: ConnessioneSftp()), 'loghi-connesso');
    await t.pumpWidget(const SizedBox());
  }, skip: !veri);
}
