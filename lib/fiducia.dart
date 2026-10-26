// Server riconosciuti: impronta del certificato FTPS e della chiave SFTP accettate dall'utente, come
// chiavi-server.json di tk-ftp per computer. La prima volta si chiede; se poi l'impronta cambia, la connessione
// si ferma e si chiede di nuovo (può essere un rinnovo, ma anche qualcuno in mezzo che vuole la password).
// I certificati FTPS validi (firmati da un'autorità) passano da soli, come sul computer.
// Copyright (C) 2026 Pietro De Filippis (TecnikGeek) — AGPL-3.0-or-later, vedi COPYING
import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum TipoFiducia { certificato, chiave }

String _id(TipoFiducia tipo, String host, int porta) =>
    '${tipo == TipoFiducia.certificato ? 'ftps' : 'ssh'}|${host.trim().toLowerCase()}:$porta';

/// Impronta SHA-256 di un certificato (DER) in esadecimale a coppie: «AB:CD:…».
String improntaCertificato(Uint8List der) =>
    SHA256Digest().process(der).map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(':');

class Fiducia {
  static const _chiave = 'server_fidati';

  static Future<Map<String, String>> _tutte() async {
    final p = await SharedPreferences.getInstance();
    try {
      return Map<String, String>.from(jsonDecode(p.getString(_chiave) ?? '{}') as Map);
    } catch (_) {
      return {};
    }
  }

  /// Impronta accettata per quel server, null se non è mai stato accettato.
  static Future<String?> impronta(TipoFiducia tipo, String host, int porta) async =>
      (await _tutte())[_id(tipo, host, porta)];

  static Future<void> ricorda(TipoFiducia tipo, String host, int porta, String impronta) async {
    final tutte = await _tutte()..[_id(tipo, host, porta)] = impronta;
    await (await SharedPreferences.getInstance()).setString(_chiave, jsonEncode(tutte));
  }
}

/// La connessione si è fermata: il server non è ancora fidato (o la sua impronta è cambiata).
class DomandaFiducia implements Exception {
  DomandaFiducia(this.tipo, this.host, this.porta, this.impronta, this.vecchia);
  final TipoFiducia tipo;
  final String host;
  final int porta;
  final String impronta;

  /// Impronta accettata in passato: se c'è, il server è CAMBIATO.
  final String? vecchia;

  @override
  String toString() => 'Server non verificato: $host:$porta';
}
