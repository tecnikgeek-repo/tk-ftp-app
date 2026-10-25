// Siti salvati sul telefono: elenco in shared_preferences, password cifrate (Keystore/Portachiavi).
// (La versione precedente aveva un altro pacchetto: i siti si portano con Esporta/Importa FileZilla.)
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'loghi.dart';
import 'modelli.dart';

const nativo = MethodChannel('tkftp/nativo');
const cassaforte = FlutterSecureStorage(iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device));

/// Identità di un sito tra telefono e computer (FileZilla non ha un id): come `Site.key()` di tk-ftp per computer.
String chiaveSito(Sito s) => '${s.host.trim().toLowerCase()}|${s.porta}|${s.utente.trim()}|${nomeProtocollo(s.protocollo)}';

class Archivio {
  Archivio._(this._pref);
  final SharedPreferences _pref;
  List<Sito> siti = [];

  static Future<Archivio> apri() async {
    final a = Archivio._(await SharedPreferences.getInstance());
    await a._carica();
    return a;
  }

  Future<void> _carica() async {
    final testo = _pref.getString('siti') ?? '[]';
    try {
      final lista = (jsonDecode(testo) as List).map((e) => Sito.daJson(Map<String, Object?>.from(e as Map))).toList();
      for (final s in lista) {
        s.password = await cassaforte.read(key: 'pw:${s.id}') ?? '';
        s.chiave = await cassaforte.read(key: 'chiave:${s.id}') ?? '';
      }
      siti = lista;
    } catch (_) {
      siti = [];
    }
  }

  Future<void> _salvaTutti() async {
    await _pref.setString('siti', jsonEncode(siti.map((s) => s.aJson()).toList()));
    for (final s in siti) {
      await cassaforte.write(key: 'pw:${s.id}', value: s.password);
      if (s.chiave.isEmpty) {
        await cassaforte.delete(key: 'chiave:${s.id}');
      } else {
        await cassaforte.write(key: 'chiave:${s.id}', value: s.chiave);
      }
    }
  }

  SharedPreferences get preferenze => _pref;

  Future<void> salva(Sito sito) async {
    final i = siti.indexWhere((s) => s.id == sito.id);
    if (i >= 0) {
      siti[i] = sito;
    } else {
      siti.add(sito);
    }
    await _salvaTutti();
  }

  Future<void> elimina(Sito sito) async {
    siti.removeWhere((s) => s.id == sito.id);
    await cassaforte.delete(key: 'pw:${sito.id}');
    await cassaforte.delete(key: 'chiave:${sito.id}');
    await Loghi.istanza.dimentica(sito.id);
    await _salvaTutti();
  }

  /// Importa siti (FileZilla): sostituisce tutto o aggiunge solo quelli nuovi (stesso host, utente e nome = doppione).
  Future<int> importa(List<Sito> nuovi, {required bool sostituisci}) async {
    var aggiunti = 0;
    if (sostituisci) {
      for (final s in siti) {
        await cassaforte.delete(key: 'pw:${s.id}');
        await cassaforte.delete(key: 'chiave:${s.id}');
      }
      siti = [...nuovi];
      aggiunti = nuovi.length;
    } else {
      for (final n in nuovi) {
        final doppio = siti.any((s) => s.host == n.host && s.utente == n.utente && s.nome == n.nome);
        if (!doppio) {
          siti.add(n);
          aggiunti++;
        }
      }
    }
    await _salvaTutti();
    return aggiunti;
  }

  /// Unisce i siti del file condiviso col computer, come fa tk-ftp per computer: lo stesso sito
  /// (indirizzo, porta, utente, protocollo) si aggiorna, gli altri si aggiungono; nessuno si cancella.
  /// La chiave privata scelta sul telefono resta. Ritorna (aggiunti, aggiornati).
  Future<(int, int)> unisci(List<Sito> arrivati) async {
    var aggiunti = 0, aggiornati = 0;
    for (final n in arrivati) {
      final i = siti.indexWhere((s) => chiaveSito(s) == chiaveSito(n));
      if (i < 0) {
        siti.add(n);
        aggiunti++;
        continue;
      }
      final s = siti[i];
      final prima = jsonEncode(s.aJson(conPassword: true));
      if (n.nome.isNotEmpty) s.nome = n.nome;
      if (n.gruppo.isNotEmpty) s.gruppo = n.gruppo;
      s.accesso = n.accesso;
      if (n.fileChiave.isNotEmpty) s.fileChiave = n.fileChiave;
      if (n.cartellaRemota.isNotEmpty) s.cartellaRemota = n.cartellaRemota;
      if (n.cartellaLocale.isNotEmpty) s.cartellaLocale = n.cartellaLocale;
      s.passivo = n.passivo;
      if (n.note.isNotEmpty) s.note = n.note;
      if (n.codiceFz.isNotEmpty) s.codiceFz = n.codiceFz;
      if (n.sitoWeb.isNotEmpty) s.sitoWeb = n.sitoWeb;
      if (n.password.isNotEmpty) s.password = n.password;
      if (jsonEncode(s.aJson(conPassword: true)) != prima) aggiornati++;
    }
    await _salvaTutti();
    return (aggiunti, aggiornati);
  }

  List<String> get gruppi => (siti.map((s) => s.gruppo).where((g) => g.isNotEmpty).toSet().toList())..sort();

  Future<void> rinominaGruppo(String vecchio, String nuovo) async {
    for (final s in siti.where((s) => s.gruppo == vecchio)) {
      s.gruppo = nuovo;
    }
    await _salvaTutti();
  }

  Future<void> eliminaGruppo(String gruppo, {required bool conSiti}) async {
    if (conSiti) {
      for (final s in siti.where((s) => s.gruppo == gruppo).toList()) {
        await elimina(s);
      }
    } else {
      for (final s in siti.where((s) => s.gruppo == gruppo)) {
        s.gruppo = '';
      }
      await _salvaTutti();
    }
  }
}
