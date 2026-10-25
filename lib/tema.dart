// Colori e pezzi propri di tk-ftp; tutto il resto (testata, card, dialoghi, Informazioni, splash) è nel kit comune.
import 'package:flutter/material.dart';

import 'kit_tk.dart';

export 'kit_tk.dart';

const accento = Color(0xFFE39A2E);
const accentoScuro = Color(0xFFB9741A);
const accentoChiaro = Color(0xFFFBEFD9);

const coloriProtocollo = {'FTP': Color(0xFF2E5BFF), 'FTPS': verde, 'SFTP': Color(0xFF7C3AED)};
const _coloriAvatar = [
  Color(0xFF2E5BFF), Color(0xFFE39A2E), Color(0xFF1FA971), Color(0xFF7C3AED),
  Color(0xFFD64545), Color(0xFF0E9AA7), Color(0xFFDB2777), Color(0xFF4F46E5),
];

/// Colore stabile dell'avatar ricavato dal nome (come nella versione precedente).
Color coloreAvatar(String nome) {
  if (nome.trim().isEmpty) return grigio500;
  var h = 0;
  for (final c in nome.toLowerCase().codeUnits) {
    h = (31 * h + c) & 0x7fffffff;
  }
  return _coloriAvatar[h % _coloriAvatar.length];
}

String dataBreve(DateTime? d) {
  if (d == null) return '';
  String due(int n) => n.toString().padLeft(2, '0');
  return '${due(d.day)}/${due(d.month)}/${d.year} ${due(d.hour)}:${due(d.minute)}';
}

/// Simbolo di tk-ftp: cartella bianca con le frecce su/giù (come l'icona dell'app).
Widget simboloFtp(double lato) => Stack(alignment: Alignment.center, children: [
      Icon(Icons.folder_rounded, color: bianco, size: lato * .66),
      Padding(
        padding: EdgeInsets.only(top: lato * .1),
        child: Icon(Icons.swap_vert_rounded, color: accentoScuro, size: lato * .32),
      ),
    ]);

const configFtp = ConfigTk(
  nome: 'tk-ftp',
  motto: 'I tuoi siti in tasca',
  descrizione: 'Client FTP, FTPS e SFTP',
  accento: accento,
  accentoScuro: accentoScuro,
  simbolo: simboloFtp,
  manifestUrl:
      'https://dl.dropboxusercontent.com/scl/fi/ev08712vvix2zr0fwzwt5/tkftp-version.json?rlkey=ofuk6ou13h0ahj1sfhetklhvi',
  altrove: ("C'è anche per Windows e Mac", 'https://pietrodefilippis.it/software/'),
);
