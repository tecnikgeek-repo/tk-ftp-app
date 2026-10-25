// Password cifrate del file condiviso col computer (tk-ftp-siti.xml): STESSO schema di tk-ftp per computer
// (tkftp/filezilla.py), verificato nei due sensi in test/condiviso_test.dart.
//   <TkFtp versione="1" cifratura="pbkdf2-sha256+aes-256-gcm" iterazioni="200000" sale="B64" controllo="B64"/>
//   chiave = PBKDF2-HMAC-SHA256(frase segreta UTF-8, sale di 16 byte, iterazioni, 32 byte)
//   <TkPass> e controllo = base64( nonce 12 byte ‖ testo cifrato ‖ tag GCM 16 byte ), AES-256-GCM senza AAD
//   controllo = cifratura della parola «tk-ftp»: se si decifra, la frase è giusta.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

const cifraturaTk = 'pbkdf2-sha256+aes-256-gcm';
const iterazioniTk = 200000;
const parolaControllo = 'tk-ftp';

final _caso = Random.secure();

Uint8List byteCasuali(int n) => Uint8List.fromList(List.generate(n, (_) => _caso.nextInt(256)));

/// Chiave AES-256 dalla frase segreta (lenta apposta: 200.000 giri, va chiamata fuori dal thread dello schermo).
Uint8List derivaChiave(String frase, Uint8List sale, [int iterazioni = iterazioniTk]) {
  final d = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))..init(Pbkdf2Parameters(sale, iterazioni, 32));
  return d.process(Uint8List.fromList(utf8.encode(frase)));
}

GCMBlockCipher _gcm(bool cifra, Uint8List chiave, Uint8List nonce) =>
    GCMBlockCipher(AESEngine())..init(cifra, AEADParameters(KeyParameter(chiave), 128, nonce, Uint8List(0)));

/// base64(nonce ‖ cifrato ‖ tag).
String sigilla(Uint8List chiave, List<int> dati) {
  final nonce = byteCasuali(12);
  final cifrato = _gcm(true, chiave, nonce).process(Uint8List.fromList(dati));
  return base64.encode([...nonce, ...cifrato]);
}

/// Decifra un blocco di [sigilla]; null se la chiave è sbagliata o il blocco è rovinato.
Uint8List? apriSigillo(Uint8List chiave, String blocco) {
  try {
    final grezzo = base64.decode(blocco.trim());
    if (grezzo.length < 12 + 16) return null;
    return _gcm(false, chiave, Uint8List.sublistView(grezzo, 0, 12)).process(Uint8List.sublistView(grezzo, 12));
  } catch (_) {
    return null;
  }
}
