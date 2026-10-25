// Anteprime dello splash e della prima schermata (caratteri veri) in build/anteprime/, senza telefono.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tkftpmanager/archivio.dart';
import 'package:tkftpmanager/condiviso.dart';
import 'package:tkftpmanager/modelli.dart';
import 'package:tkftpmanager/modifica_sito.dart';
import 'package:tkftpmanager/siti.dart';
import 'package:tkftpmanager/tema.dart';

import 'caratteri.dart';

Future<void> _scatta(WidgetTester t, Widget w, String nome) async {
  final k = GlobalKey();
  await t.pumpWidget(RepaintBoundary(key: k, child: MaterialApp(debugShowCheckedModeBanner: false, theme: temaKit(), home: w)));
  await t.pump(const Duration(milliseconds: 500));
  await t.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final img = await (k.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    Directory('build/anteprime').createSync(recursive: true);
    File('build/anteprime/$nome.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
  await t.pump(const Duration(milliseconds: 500));
}

void main() {
  setUpAll(caricaCaratteri);

  testWidgets('anteprime', (t) async {
    SharedPreferences.setMockInitialValues({});
    configTk = configFtp;
    t.view.physicalSize = const Size(780, 1688);
    t.view.devicePixelRatio = 2;
    await _scatta(t, const SchermataAvvio(), 'avvio');
    await _scatta(t, const SchermataSiti(), 'home');
    await _scatta(t, const SchermataInformazioni(), 'info');
    await _scatta(t, const SchermataModificaSito(gruppi: ['Clienti']), 'modifica');
    final arch = await t.runAsync(Archivio.apri);
    await _scatta(t, SchermataCondiviso(arch: arch!), 'condiviso');
    await _scatta(
        t,
        SchermataModificaSito(
            sito: Sito(
                nome: 'Server',
                host: 'sftp.esempio.it',
                porta: 65100,
                protocollo: Protocollo.sftp,
                accesso: Accesso.chiave,
                utente: 'root',
                fileChiave: r'C:\Users\TecnikGeek\.ssh\id_ed25519'),
            gruppi: const []),
        'modifica-chiave');
    await t.pumpWidget(const SizedBox());
  });
}
