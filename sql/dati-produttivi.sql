-- =====================================================================
-- Dati produttivi · Parmigiano Reggiano (PR) e Grana Padano (GP)
-- 19/11/2026
--
-- Supabase → SQL Editor → New query → incolla questo script → Run.
-- Si può rieseguire senza problemi. Crea solo tabelle nuove (prefisso dp_):
-- non tocca il registro lotti, il magazzino, il DDT e le lavorazioni.
--
-- Accesso: solo l'utente Paolo (admin@lotti.local, stessa password del
-- registro lotti).
--
-- Risparmio: una riga per prodotto e per giornata, con tutte le righe
-- del giorno in "dati" (jsonb). Si salva solo quello che si inserisce;
-- tutti i calcoli li fa il browser.
-- =====================================================================

-- Lavorazioni: una riga per prodotto e giornata
create table if not exists public.dp_giornate (
  prodotto      text not null check (prodotto in ('PR', 'GP')),
  data          date not null,
  dati          jsonb not null default '[]'::jsonb,
  aggiornato_il timestamptz not null default now(),
  primary key (prodotto, data)
);

-- Lavaggi: una riga per prodotto e giornata; "altre" = forme lavate
-- per altri (CARPI per PR, CEREA per GP), inserite a mano
create table if not exists public.dp_lavaggi (
  prodotto      text not null check (prodotto in ('PR', 'GP')),
  data          date not null,
  dati          jsonb not null default '[]'::jsonb,
  altre         integer not null default 0,
  aggiornato_il timestamptz not null default now(),
  primary key (prodotto, data)
);

-- Codici articolo: matricola → codice
create table if not exists public.dp_codici (
  prodotto  text not null check (prodotto in ('PR', 'GP')),
  matricola text not null,
  codice    text not null default '',
  primary key (prodotto, matricola)
);

-- Impostazioni (parametri per prodotto, rintracciabilità Carpi, contatori)
create table if not exists public.dp_impostazioni (
  chiave        text primary key,
  valore        jsonb not null default '{}'::jsonb,
  aggiornato_il timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- Sicurezza: solo Paolo
-- ---------------------------------------------------------------------
do $$
declare t text;
begin
  foreach t in array array['dp_giornate', 'dp_lavaggi', 'dp_codici', 'dp_impostazioni'] loop
    execute format('alter table public.%I enable row level security', t);
    execute format('drop policy if exists %I on public.%I', t || '_paolo', t);
    execute format($p$create policy %I on public.%I for all to authenticated
      using (lower(coalesce((select auth.jwt()) ->> 'email', '')) = 'admin@lotti.local')
      with check (lower(coalesce((select auth.jwt()) ->> 'email', '')) = 'admin@lotti.local')$p$, t || '_paolo', t);
    execute format('revoke all on public.%I from anon', t);
    execute format('grant select, insert, update, delete on public.%I to authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------
-- Funzioni (risposte piccole: il lavoro lo fa il database)
-- ---------------------------------------------------------------------

-- Per ogni lotto: matricola, mese, anno e media del peso medio dei lavaggi
-- (media semplice dei pesi medi delle righe di lavaggio, come AVERAGEIF di Excel).
-- La ricerca è su TUTTI i lavaggi del prodotto.
create or replace function public.dp_lotti_info(p_prodotto text, p_lotti text[])
returns table(lotto text, matr text, mese integer, anno integer, media numeric, n_righe integer, n_forme integer)
language sql stable set search_path to 'public'
as $$
  select r.v->>'lotto',
         (array_agg(r.v->>'matr') filter (where coalesce(r.v->>'matr', '') <> ''))[1],
         ((array_agg((r.v->>'mese')::int) filter (where coalesce(r.v->>'mese', '') <> ''))[1]),
         ((array_agg((r.v->>'anno')::int) filter (where coalesce(r.v->>'anno', '') <> ''))[1]),
         avg((r.v->>'sporco')::numeric / nullif((r.v->>'forme')::numeric, 0)),
         count(*)::int,
         coalesce(sum((r.v->>'forme')::numeric), 0)::int
  from dp_lavaggi g
  cross join lateral jsonb_array_elements(g.dati) r(v)
  where g.prodotto = p_prodotto
    and r.v->>'lotto' = any(p_lotti)
  group by r.v->>'lotto'
$$;

-- Forme lavate per giorno (lavaggi + altre) in un periodo
create or replace function public.dp_forme_giorno(p_prodotto text, p_da date, p_a date)
returns table(data date, lavaggi integer, altre integer)
language sql stable set search_path to 'public'
as $$
  select g.data,
         coalesce((select sum((r.v->>'forme')::numeric) from jsonb_array_elements(g.dati) r(v)), 0)::int,
         g.altre
  from dp_lavaggi g
  where g.prodotto = p_prodotto and g.data between p_da and p_a
  order by g.data
$$;

-- Lotti già registrati nelle lavorazioni (per il controllo matricola/mese-anno)
create or replace function public.dp_lotti_lavorazioni(p_prodotto text, p_lotti text[], p_escludi date default null)
returns table(lotto text, matr text, mese integer, anno integer, data date, riga integer)
language sql stable set search_path to 'public'
as $$
  select distinct on (r.v->>'lotto', r.v->>'matr', r.v->>'mese', r.v->>'anno')
         r.v->>'lotto', r.v->>'matr',
         nullif(r.v->>'mese', '')::int, nullif(r.v->>'anno', '')::int,
         g.data, nullif(r.v->>'n', '')::int
  from dp_giornate g
  cross join lateral jsonb_array_elements(g.dati) r(v)
  where g.prodotto = p_prodotto
    and (p_escludi is null or g.data <> p_escludi)
    and r.v->>'lotto' = any(p_lotti)
  order by r.v->>'lotto', r.v->>'matr', r.v->>'mese', r.v->>'anno', g.data
$$;

grant execute on function public.dp_lotti_info(text, text[]) to authenticated;
grant execute on function public.dp_forme_giorno(text, date, date) to authenticated;
grant execute on function public.dp_lotti_lavorazioni(text, text[], date) to authenticated;
revoke execute on function public.dp_lotti_info(text, text[]) from anon, public;
revoke execute on function public.dp_forme_giorno(text, date, date) from anon, public;
revoke execute on function public.dp_lotti_lavorazioni(text, text[], date) from anon, public;

-- ---------------------------------------------------------------------
-- Parametri iniziali (modificabili dalla pagina Parametri del sito)
-- ---------------------------------------------------------------------
insert into public.dp_impostazioni (chiave, valore) values
  ('param_PR', '{"calo":0.391587048,"segatura":0.05,"croste":2.4,"pulitura":0.05,"piallatura":2.6,"limite_croste_g":500,"peso_min":35,"peso_max":45}'),
  ('param_GP', '{"calo":0.391587048,"segatura":0.05,"croste":2.4,"pulitura":0.05,"piallatura":2.6,"limite_croste_g":500,"peso_min":34,"peso_max":45,"piatti_pct":18}')
on conflict (chiave) do nothing;

-- Rintracciabilità Carpi: trova una lavorazione dal numero di riga
create or replace function public.dp_riga_lavorazione(p_prodotto text, p_n integer)
returns table(data date, riga jsonb)
language sql stable set search_path to 'public'
as $$
  select g.data, r.v
  from dp_giornate g
  cross join lateral jsonb_array_elements(g.dati) r(v)
  where g.prodotto = p_prodotto and r.v->>'n' = p_n::text
  limit 1
$$;
grant execute on function public.dp_riga_lavorazione(text, integer) to authenticated;
revoke execute on function public.dp_riga_lavorazione(text, integer) from anon, public;


-- Scheda consorzio: righe di lavorazione con numero tra p_da e p_a (qualunque data), max 300
create or replace function public.dp_righe_lavorazione(p_prodotto text, p_da integer, p_a integer)
returns table(data date, riga jsonb)
language sql stable set search_path to 'public'
as $$
  select g.data, r.v
  from dp_giornate g
  cross join lateral jsonb_array_elements(g.dati) r(v)
  where g.prodotto = p_prodotto and (r.v->>'n') ~ '^[0-9]+$'
    and (r.v->>'n')::int between least(p_da, p_a) and greatest(p_da, p_a)
  order by g.data, (r.v->>'n')::int
  limit 300
$$;
grant execute on function public.dp_righe_lavorazione(text, integer, integer) to authenticated;
revoke execute on function public.dp_righe_lavorazione(text, integer, integer) from anon, public;
