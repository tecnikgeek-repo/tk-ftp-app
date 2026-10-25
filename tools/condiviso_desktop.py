"""Compatibilità del file condiviso (tk-ftp-siti.xml) con tk-ftp per computer, usando il SUO codice (tkftp/filezilla.py).

  python tools/condiviso_desktop.py genera   <cartella tk-ftp-desktop> test/dati/condiviso-desktop.xml
      scrive il file come lo scrive il computer (password cifrate con FRASE) -> lo legge test/condiviso_test.dart
  python tools/condiviso_desktop.py verifica <cartella tk-ftp-desktop> build/condiviso-app.xml
      legge col codice del computer il file scritto dall'app nei test e controlla siti, tipi di accesso e password

Sul PC di Pietro il Python del venv è bloccato da Smart App Control: lanciarlo col Python base di uv
(le librerie del venv del computer si aggiungono da sole).
"""
import sys

FRASE = "Frase di prova è €"

SITI = [  # name, host, port, protocol, logon, user, password, keyfile, remote_dir, group, passive, website
    ("Solo in chiaro", "ftp.chiaro.it", 21, "ftp-plain", "normal", "mario", "pässwörd €1", "", "/www/public", "1. Clienti", True, "www.chiaro.it"),
    ("Implicito", "ftps.implicito.it", 990, "ftps-implicit", "normal", "anna", 'x"<&>y', "", "/httpdocs", "1. Clienti/Napoli", False, ""),
    ("Con chiave", "sftp.chiave.it", 65100, "sftp", "key", "root", "", r"C:\Users\TecnikGeek\.ssh\id_ed25519", "/var/www", "2. Server", True, "https://chiave.it/negozio"),
    ("Chiedi", "ftp.chiedi.it", 21, "ftp", "ask", "luigi", "", "", "", "", True, ""),
    ("Anonimo", "ftp.anonimo.it", 21, "ftp", "anonymous", "", "", "", "/pub", "", True, ""),
    ("Esplicito", "ftps.esplicito.it", 21, "ftps", "normal", "sara", "segreta", "", "/", "", True, "esplicito.it"),
]


def siti(Site):
    out = []
    for n, h, p, pr, lo, u, pw, kf, rd, g, pa, web in SITI:
        s = Site(name=n, host=h, port=p, protocol=pr, logon=lo, user=u, keyfile=kf, remote_dir=rd, group=g, passive=pa,
                 website=web)
        s.password = pw
        out.append(s)
    return out


def main():
    modo, desktop, file = sys.argv[1:4]
    import os
    sys.path.insert(0, desktop)
    sys.path.insert(1, os.path.join(desktop, ".venv", "Lib", "site-packages"))  # Windows
    sys.path.extend(__import__("glob").glob(os.path.join(desktop, ".venv", "lib", "python3*", "site-packages")))
    from tkftp import filezilla
    from tkftp.sites import Site
    if modo == "genera":
        lista = siti(Site)
        filezilla.write_file(file, lista, {s.id: s.password for s in lista}, phrase=FRASE)
        print("scritto", file)
        return
    res = filezilla.read_file(file, FRASE)
    assert res.encrypted and not res.wrong_phrase, "frase non accettata dal computer"
    assert filezilla.read_file(file, "sbagliata").wrong_phrase, "frase sbagliata non riconosciuta"
    letti = {s.host: s for s in res.sites}
    errori = []
    for n, h, p, pr, lo, u, pw, kf, rd, g, pa, web in SITI:
        s = letti.get(h)
        if s is None:
            errori.append(f"{h}: manca")
            continue
        atteso = (n, p, pr, lo, u, pw, kf, rd or "/", g, pa, web)  # cartella vuota = radice
        trovato = (s.name, s.port, s.protocol, s.logon, s.user, s.password, s.keyfile, s.remote_dir or "/", s.group, s.passive, s.website)
        if atteso != trovato:
            errori.append(f"{h}: atteso {atteso}\n      trovato {trovato}")
    extra = set(letti) - {x[1] for x in SITI}
    if extra:
        errori.append(f"siti in più: {extra}")
    if errori:
        print("DIFFERENZE:\n  " + "\n  ".join(errori))
        sys.exit(1)
    print(f"OK: {len(res.sites)} siti letti dal codice del computer, password decifrate, accessi e cartelle uguali")


if __name__ == "__main__":
    main()
