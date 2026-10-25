// Badge del sito: il suo logo in un quadrato arrotondato bianco (nitido: SVG vettoriale o PNG fino a 256 px),
// altrimenti la lettera colorata di sempre. Si ridisegna da solo quando arriva un logo.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'loghi.dart';
import 'modelli.dart';
import 'tema.dart';

class BadgeSito extends StatelessWidget {
  const BadgeSito(this.sito, {super.key, this.lato = 48});

  final Sito sito;
  final double lato;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Loghi.istanza,
        builder: (context, _) {
          final l = Loghi.istanza;
          final dati = l.accesoOra ? l.byte(sito.id) : null;
          if (dati == null) return _lettera();
          final dentro = lato * .76;
          return Container(
            width: lato,
            height: lato,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bianco,
              borderRadius: BorderRadius.circular(lato * .26),
              border: Border.all(color: grigio200),
            ),
            child: SizedBox(
              width: dentro,
              height: dentro,
              child: l.svg(sito.id)
                  ? SvgPicture.memory(dati, fit: BoxFit.contain)
                  : Image.memory(dati, fit: BoxFit.contain, filterQuality: FilterQuality.high, gaplessPlayback: true),
            ),
          );
        },
      );

  Widget _lettera() {
    final nome = sito.nomeVisibile.trim();
    return CircleAvatar(
      radius: lato / 2,
      backgroundColor: coloreAvatar(nome),
      child: Text(nome.isEmpty ? '?' : nome[0].toUpperCase(),
          style: TextStyle(color: bianco, fontSize: lato * .42, fontWeight: FontWeight.w800)),
    );
  }
}
