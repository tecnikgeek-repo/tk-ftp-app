<!-- README generato da Dropbox/CLAUDE/dev/agpl-rollout/readme/genera_readme_app.py: modificare lì -->
<div align="center">

<img src="docs/vetrina.png" alt="tk-ftp: I tuoi siti in tasca." width="100%">

<br><br>

<a href="https://pietrodefilippis.it/scarica-app/tk-ftp/"><img alt="Scarica l'app" src="https://img.shields.io/badge/%E2%AC%87%20%20Scarica-gratis%20per%20Android-e39a2e?style=for-the-badge&logo=android&logoColor=white"></a> &nbsp; <a href="https://pietrodefilippis.it/donazione/"><img alt="Offrimi un caffè" src="https://img.shields.io/badge/%E2%98%95%20%20Offrimi%20un%20caff%C3%A8-facoltativo-f59e0b?style=for-the-badge"></a>

<br><br>

<a href="COPYING"><img alt="Licenza AGPL-3.0" src="https://img.shields.io/badge/licenza-AGPL--3.0-16a34a?style=for-the-badge"></a> <img alt="Android" src="https://img.shields.io/badge/Android-telefono%20%C2%B7%20tablet-3DDC84?style=for-the-badge&logo=android&logoColor=white"> <img alt="Versione" src="https://img.shields.io/github/v/tag/tecnikgeek-repo/tk-ftp-app?label=versione&style=for-the-badge&color=e39a2e"> <img alt="Zero pubblicità" src="https://img.shields.io/badge/pubblicit%C3%A0-zero-0f172a?style=for-the-badge">

</div>

---

## ✨ Cosa fa

<table>
<tr>
<td width="50%" valign="top">

### 🗂️&nbsp; Siti in gruppi
Tutti i tuoi siti in ordine, ognuno col suo logo.

</td>
<td width="50%" valign="top">

### ⬆️&nbsp; Carica e scarica
File e cartelle, dal telefono al server e ritorno.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### ✏️&nbsp; Modifica al volo
Correggi i file di testo direttamente sul server.

</td>
<td width="50%" valign="top">

### 📥&nbsp; Importa ed esporta
I siti salvati in altri programmi FTP, in un tocco.

</td>
</tr>
<tr>
<td width="50%" valign="top">

### 💻&nbsp; Condivisi col computer
Gli stessi siti di tk-ftp per Windows e Mac, con le password cifrate da una frase segreta.

</td>
<td width="50%" valign="top">

### 🛡️&nbsp; Server verificati
Ti avvisa se il certificato o la chiave del server cambiano.

</td>
</tr>
</table>

## 📱 Com'è fatta

<div align="center">

<table align="center">
<tr>
<td align="center" valign="top"><img src="docs/schermata-1.png" width="200" alt="Siti"><br><sub><b>Siti</b></sub></td>
<td align="center" valign="top"><img src="docs/schermata-2.png" width="200" alt="Sito SFTP"><br><sub><b>Sito SFTP</b></sub></td>
<td align="center" valign="top"><img src="docs/schermata-3.png" width="200" alt="Sito FTPS"><br><sub><b>Sito FTPS</b></sub></td>
</tr>
<tr>
<td align="center" valign="top"><img src="docs/schermata-4.png" width="200" alt="Condiviso col computer"><br><sub><b>Condiviso col computer</b></sub></td>
</tr>
</table>

</div>

## 🔒 I tuoi dati

- **Privacy:** siti e impostazioni restano sul telefono; password e chiavi SSH nella cassaforte cifrata del sistema (Keystore su Android, Portachiavi su iPhone). L'app si collega solo ai server che aggiungi tu, ai siti web dei tuoi siti per i loghi (si spegne in Impostazioni) e a Dropbox per gli aggiornamenti. Le statistiche anonime (una volta al giorno: nome, versione, sistema e un codice casuale) partono solo se dici sì nel benvenuto o in Informazioni.

Nessuna pubblicità, nessun account da creare, nessun abbonamento: tutte le funzioni sono gratis, per tutti.

## 📥 Installazione

- **Android** — [scarica l'app](https://pietrodefilippis.it/scarica-app/tk-ftp/) da pietrodefilippis.it e aprila: Android chiede una volta il permesso di installare app da questa origine. Gli aggiornamenti arrivano da soli, l'app te li propone. A breve anche su Google Play.
- **Piattaforme:** Android e iPhone. C'è anche per Windows e Mac: [tk-ftp per computer](https://pietrodefilippis.it/software/).

<details>
<summary><b>🛠️ Compilare dal codice sorgente</b></summary>

<br>

Serve [Flutter](https://flutter.dev) (versione indicata in `.github/workflows/android.yml`):

```bash
flutter pub get
flutter test
flutter build apk --release
```

Senza la variabile `ANDROID_KEYSTORE` l'APK si firma con la chiave di debug di Flutter.

</details>

## 📜 Licenza

**tk-ftp** è software libero: © 2026 Pietro De Filippis (TecnikGeek), licenza
**[GNU Affero General Public License v3.0](COPYING)**. Puoi usarlo, studiarlo, modificarlo e condividerlo; è
fornito **così com'è, senza alcuna garanzia**.

> Il nome **tk-ftp** e il logo non sono coperti dalla licenza (AGPL, sezione 7): una versione modificata deve avere un nome diverso.

---

<div align="center">

**Ti è utile?** Tutte le funzioni sono gratis per tutti. Se vuoi, un caffè aiuta a migliorarla e a crearne altre.

<a href="https://pietrodefilippis.it/donazione/"><img alt="Offrimi un caffè" src="https://img.shields.io/badge/%E2%98%95%20%20Offrimi%20un%20caff%C3%A8-pietrodefilippis.it-f59e0b?style=for-the-badge"></a>

<sub>Creata da <a href="https://pietrodefilippis.it">Pietro De Filippis · TecnikGeek</a> — Webmaster & UX/UI Designer</sub>

</div>
