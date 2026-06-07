-- Run this in the Supabase SQL editor to enable online multiplayer.

create table if not exists public.online_game_sessions (
  id          uuid        primary key default gen_random_uuid(),
  room_code   char(6)     unique not null,
  host_id     uuid        references auth.users(id) on delete cascade,
  guest_id    uuid        references auth.users(id) on delete cascade,
  status      text        not null default 'waiting',   -- waiting | playing | finished
  host_state  jsonb,      -- { commandPoints, initialCP, units[], armyName, armyBgColor, armyImageB64, playerColor, roundDiceRolls }
  guest_state jsonb,      -- same shape
  shared      jsonb,      -- { round, tokenBag, activePlayer, pendingAction }
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Row-level security
alter table public.online_game_sessions enable row level security;

-- Host and guest can access their own session; any authenticated user can read waiting sessions to join
create policy "read own or waiting"
  on public.online_game_sessions for select to authenticated
  using (
    auth.uid() = host_id
    or auth.uid() = guest_id
    or status = 'waiting'
  );

create policy "host can create"
  on public.online_game_sessions for insert to authenticated
  with check (auth.uid() = host_id);

create policy "participants can update"
  on public.online_game_sessions for update to authenticated
  using (auth.uid() = host_id or auth.uid() = guest_id);

-- Enable Realtime for this table
-- (also toggle "Realtime" on in the Supabase Table Editor for this table)
alter publication supabase_realtime add table public.online_game_sessions;
