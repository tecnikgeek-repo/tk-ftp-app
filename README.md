# tk-ftp per Android e iPhone

Client FTP, FTPS e SFTP sul telefono: i tuoi siti in tasca, con gruppi e loghi, carica e scarica, modifica al
volo dei file, importa ed esporta i siti di altri programmi FTP, siti condivisi con tk-ftp per computer (password cifrate con una
frase segreta). Tutte le funzioni sono gratis, per tutti.

- **Piattaforme:** Android (APK) e iPhone. C'è anche per Windows e Mac: [tk-ftp per computer](https://pietrodefilippis.it/software/).
- **Licenza:** software libero sotto [GNU AGPL-3.0](COPYING), fornito così com'è, senza alcuna garanzia.
- **Privacy:** siti e impostazioni restano sul telefono; password e chiavi SSH nella cassaforte cifrata del sistema
  (Keystore su Android, Portachiavi su iPhone). L'app si collega solo ai server che aggiungi tu, ai siti web dei
  tuoi siti per i loghi (si spegne in Impostazioni) e a Dropbox per gli aggiornamenti. Le statistiche anonime (una
  volta al giorno: nome, versione, sistema e un codice casuale) partono solo se dici sì nel benvenuto o in
  Informazioni.

## Compilare dal sorgente

Serve [Flutter](https://flutter.dev) (versione indicata in `.github/workflows/android.yml`):

```
flutter pub get
flutter test
flutter build apk --release
```

Senza la variabile `ANDROID_KEYSTORE` l'APK si firma con la chiave di debug di Flutter.

Il nome «tk-ftp» e il logo non sono coperti dalla licenza (AGPL sez. 7): una versione modificata deve avere un
nome diverso.

© 2026 Pietro De Filippis (TecnikGeek) — [pietrodefilippis.it](https://pietrodefilippis.it)
