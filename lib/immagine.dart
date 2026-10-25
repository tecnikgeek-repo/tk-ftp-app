// Visualizzatore di immagini del server: scarica in cache e mostra a tutto schermo con zoom.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'connessione.dart';
import 'modelli.dart';
import 'tema.dart';

class SchermataImmagine extends StatefulWidget {
  const SchermataImmagine({super.key, required this.file, required this.connessione});

  final FileRemoto file;
  final Connessione connessione;

  @override
  State<SchermataImmagine> createState() => _SchermataImmagineState();
}

class _SchermataImmagineState extends State<SchermataImmagine> {
  File? _file;
  String? _errore;

  @override
  void initState() {
    super.initState();
    () async {
      try {
        final f = File('${(await getTemporaryDirectory()).path}/img_${widget.file.nome.replaceAll('/', '_')}');
        await widget.connessione.scarica(widget.file.percorso, f);
        if (mounted) setState(() => _file = f);
      } catch (e) {
        if (mounted) setState(() => _errore = '$e');
      }
    }();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          Positioned.fill(
            child: _file != null
                ? InteractiveViewer(maxScale: 8, child: Center(child: Image.file(_file!)))
                : Center(
                    child: _errore != null
                        ? Text(_errore!, style: const TextStyle(color: bianco), textAlign: TextAlign.center)
                        : const CircularProgressIndicator(color: accento),
                  ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.black45,
              padding: EdgeInsets.fromLTRB(4, MediaQuery.of(context).padding.top + 4, 12, 8),
              child: Row(children: [
                AzioneTk(Icons.arrow_back, 'Indietro', () => Navigator.of(context).pop()),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(widget.file.nome,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: bianco, fontWeight: FontWeight.w700)),
                    Text(widget.file.dimensioneLeggibile, style: const TextStyle(color: grigio300, fontSize: 12)),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      );
}
