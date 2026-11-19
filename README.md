# Dati produttivi

Sito per gestire i dati produttivi di **Parmigiano Reggiano** e **Grana Padano** (lavaggi, lavorazioni, polpa, registrazione AS400, prelievo magazzino, totale lavaggi, invio OCQ mensile, rintracciabilità Carpi, scheda consorzio).

- Un solo sito (`index.html`) con selettore Parmigiano / Grana Padano, pubblicato con GitHub Pages.
- Dati su Supabase (stesso progetto del registro lotti, tabelle `dp_*`), accesso solo per l'utente Paolo.
- Si salva una riga per prodotto e per giornata; tutti i calcoli (kg lavorati, croste, prodotto finito, sfridi, stagionatura…) li fa il browser.
- `?demo` nell'indirizzo apre una modalità di prova che salva solo nel browser.

## Installazione
1. Supabase → SQL Editor: eseguire `sql/dati-produttivi.sql` (già applicato al progetto).
2. GitHub → Settings → Pages → *Deploy from a branch* → `main` / root.
3. Aprire il sito, accedere con la password di Paolo.

Nessun dato è contenuto in questo repository.
