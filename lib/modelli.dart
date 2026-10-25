// Siti e file remoti: stessi campi della versione Kotlin (così i dati passano senza perdite).
import 'dart:math';

enum Protocollo { ftp, ftps, sftp }

/// Tipi di accesso come in FileZilla (`<Logontype>`): 1 normale, 0 anonimo, 2 chiedi, 5 file chiave (solo SFTP).
enum Accesso { normale, anonimo, chiedi, chiave }

const _nomiProtocollo = {Protocollo.ftp: 'FTP', Protocollo.ftps: 'FTPS', Protocollo.sftp: 'SFTP'};
const _nomiAccesso = {
  Accesso.normale: 'NORMAL',
  Accesso.anonimo: 'ANONYMOUS',
  Accesso.chiedi: 'ASK',
  Accesso.chiave: 'KEY',
};

String nomeProtocollo(Protocollo p) => _nomiProtocollo[p]!;

String nuovoId() {
  final r = Random.secure();
  String h(int n) => List.generate(n, (_) => r.nextInt(16).toRadixString(16)).join();
  return '${h(8)}-${h(4)}-4${h(3)}-${(8 + r.nextInt(4)).toRadixString(16)}${h(3)}-${h(12)}';
}

class Sito {
  Sito({
    String? id,
    this.nome = '',
    this.host = '',
    this.porta = 21,
    this.protocollo = Protocollo.ftp,
    this.accesso = Accesso.normale,
    this.utente = '',
    this.password = '',
    this.cartellaRemota = '/',
    this.cartellaLocale = '',
    this.passivo = true,
    this.note = '',
    this.gruppo = '',
    this.fileChiave = '',
    this.nomeChiave = '',
    this.chiave = '',
    this.codiceFz = '',
    this.sitoWeb = '',
  }) : id = id ?? nuovoId();

  final String id;
  String nome, host, utente, password, cartellaRemota, cartellaLocale, note, gruppo;
  int porta;
  Protocollo protocollo;
  Accesso accesso;
  bool passivo;

  /// Percorso del file chiave scritto da FileZilla / tk-ftp per computer (`<Keyfile>`): si conserva per l'esportazione.
  String fileChiave;

  /// Nome del file chiave scelto sul telefono (solo da mostrare).
  String nomeChiave;

  /// Contenuto della chiave privata scelta sul telefono: sta nella cassaforte, mai nel JSON.
  String chiave;

  /// Numero `<Protocol>` di FileZilla da cui viene il sito («0» FTP con TLS se disponibile, «6» solo in chiaro,
  /// «4» FTPS esplicito, «3» FTPS implicito, «1» SFTP): così riesportando non si perde la variante.
  String codiceFz;

  /// «Sito web (per il logo)»: vuoto = ricavato da indirizzo e nome (`<TkWebsite>` nei file, come il computer).
  String sitoWeb;

  /// FTPS con TLS implicito: dichiarato da FileZilla (3) o porta 990.
  bool get tlsImplicito => protocollo == Protocollo.ftps && (codiceFz == '3' || porta == 990);

  String get nomeVisibile => nome.trim().isEmpty ? host : nome;

  int portaPredefinita() => protocollo == Protocollo.sftp ? 22 : 21;

  Sito copia() => Sito.daJson(aJson(conPassword: true))..chiave = chiave;

  /// Stesse chiavi della versione Kotlin (SharedPreferences «tk_ftp_sites» → «sites_json»).
  Map<String, Object?> aJson({bool conPassword = false}) => {
        'id': id,
        'name': nome,
        'host': host,
        'port': porta,
        'protocol': _nomiProtocollo[protocollo],
        'logonType': _nomiAccesso[accesso],
        'username': utente,
        if (conPassword) 'password': password,
        'remotePath': cartellaRemota,
        'localPath': cartellaLocale,
        'passiveMode': passivo,
        'notes': note,
        'groupName': gruppo,
        if (fileChiave.isNotEmpty) 'keyFile': fileChiave,
        if (nomeChiave.isNotEmpty) 'keyName': nomeChiave,
        if (codiceFz.isNotEmpty) 'fzProtocol': codiceFz,
        if (sitoWeb.isNotEmpty) 'website': sitoWeb,
      };

  factory Sito.daJson(Map<String, Object?> j) {
    Protocollo prot = Protocollo.ftp;
    _nomiProtocollo.forEach((k, v) {
      if (v == j['protocol']) prot = k;
    });
    Accesso acc = Accesso.normale;
    _nomiAccesso.forEach((k, v) {
      if (v == j['logonType']) acc = k;
    });
    return Sito(
      id: (j['id'] as String?)?.isNotEmpty == true ? j['id'] as String : null,
      nome: '${j['name'] ?? ''}',
      host: '${j['host'] ?? ''}',
      porta: (j['port'] as num?)?.toInt() ?? 21,
      protocollo: prot,
      accesso: acc,
      utente: '${j['username'] ?? ''}',
      password: '${j['password'] ?? ''}',
      cartellaRemota: '${j['remotePath'] ?? '/'}',
      cartellaLocale: '${j['localPath'] ?? ''}',
      passivo: j['passiveMode'] as bool? ?? true,
      note: '${j['notes'] ?? ''}',
      gruppo: '${j['groupName'] ?? ''}',
      fileChiave: '${j['keyFile'] ?? ''}',
      nomeChiave: '${j['keyName'] ?? ''}',
      codiceFz: '${j['fzProtocol'] ?? ''}',
      sitoWeb: '${j['website'] ?? ''}',
    );
  }
}

class FileRemoto {
  FileRemoto({required this.nome, required this.percorso, required this.cartella, this.dimensione = 0, this.modificato});

  final String nome, percorso;
  final bool cartella;
  final int dimensione;
  final DateTime? modificato;

  String get estensione => nome.contains('.') ? nome.substring(nome.lastIndexOf('.') + 1).toLowerCase() : '';

  bool get testoModificabile => !cartella && _testo.contains(estensione);

  bool get immagine => !cartella && const {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'}.contains(estensione);

  String get dimensioneLeggibile => cartella ? '' : dimensioneUmana(dimensione);
}

String dimensioneUmana(int n) {
  if (n < 1024) return '$n B';
  if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(n < 10240 ? 1 : 0)} KB';
  if (n < 1024 * 1024 * 1024) return '${(n / 1048576).toStringAsFixed(1)} MB';
  return '${(n / 1073741824).toStringAsFixed(1)} GB';
}

const _testo = {
  'html', 'htm', 'php', 'phtml', 'css', 'scss', 'less', 'js', 'mjs', 'ts', 'jsx', 'tsx', 'json', 'xml', 'svg', 'txt',
  'md', 'markdown', 'ini', 'conf', 'cfg', 'env', 'htaccess', 'sql', 'csv', 'tsv', 'log', 'yml', 'yaml', 'toml',
  'properties', 'gradle', 'sh', 'py', 'java', 'kt', 'rb', 'go', 'c', 'cpp', 'h', 'vue',
};

/// Unisce cartella e nome come fa il server ("/a" + "b" → "/a/b").
String unisci(String cartella, String nome) => cartella.endsWith('/') ? '$cartella$nome' : '$cartella/$nome';

String cartellaSuperiore(String p) {
  final t = p.length > 1 && p.endsWith('/') ? p.substring(0, p.length - 1) : p;
  final i = t.lastIndexOf('/');
  return i <= 0 ? '/' : t.substring(0, i);
}
