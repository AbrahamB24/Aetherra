-- Run this in the Supabase SQL editor to set up Row Level Security
-- for all user-facing tables. Safe to run multiple times (uses IF NOT EXISTS / OR REPLACE).

-- ── profiles ────────────────────────────────────────────────────────────────
alter table public.profiles enable row level security;

drop policy if exists "users can read own profile"    on public.profiles;
drop policy if exists "users can update own profile"  on public.profiles;
drop policy if exists "users can insert own profile"  on public.profiles;

create policy "users can read own profile"
  on public.profiles for select to authenticated
  using (id = auth.uid());

create policy "users can update own profile"
  on public.profiles for update to authenticated
  using (id = auth.uid());

create policy "users can insert own profile"
  on public.profiles for insert to authenticated
  with check (id = auth.uid());


-- ── army_lists ───────────────────────────────────────────────────────────────
alter table public.army_lists enable row level security;

drop policy if exists "users can read own armies"    on public.army_lists;
drop policy if exists "users can insert own armies"  on public.army_lists;
drop policy if exists "users can update own armies"  on public.army_lists;
drop policy if exists "users can delete own armies"  on public.army_lists;

create policy "users can read own armies"
  on public.army_lists for select to authenticated
  using (user_id = auth.uid());

create policy "users can insert own armies"
  on public.army_lists for insert to authenticated
  with check (user_id = auth.uid());

create policy "users can update own armies"
  on public.army_lists for update to authenticated
  using (user_id = auth.uid());

create policy "users can delete own armies"
  on public.army_lists for delete to authenticated
  using (user_id = auth.uid());


-- ── game_sessions ────────────────────────────────────────────────────────────
alter table public.game_sessions enable row level security;

drop policy if exists "users can read own saves"    on public.game_sessions;
drop policy if exists "users can insert own saves"  on public.game_sessions;
drop policy if exists "users can update own saves"  on public.game_sessions;
drop policy if exists "users can delete own saves"  on public.game_sessions;

create policy "users can read own saves"
  on public.game_sessions for select to authenticated
  using (user_id = auth.uid());

create policy "users can insert own saves"
  on public.game_sessions for insert to authenticated
  with check (user_id = auth.uid());

create policy "users can update own saves"
  on public.game_sessions for update to authenticated
  using (user_id = auth.uid());

create policy "users can delete own saves"
  on public.game_sessions for delete to authenticated
  using (user_id = auth.uid());


-- ── user_factions / user_units / user_abilities (Workshop) ──────────────────
alter table public.user_factions  enable row level security;
alter table public.user_units     enable row level security;
alter table public.user_abilities enable row level security;

drop policy if exists "users can manage own factions"   on public.user_factions;
drop policy if exists "users can manage own units"      on public.user_units;
drop policy if exists "users can manage own abilities"  on public.user_abilities;

create policy "users can manage own factions"
  on public.user_factions for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "users can manage own units"
  on public.user_units for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy "users can manage own abilities"
  on public.user_abilities for all to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());


-- ── shared_armies ────────────────────────────────────────────────────────────
-- Anyone authenticated can read (needed for army import via code).
-- Only the creator can insert or delete their own shared army.
alter table public.shared_armies enable row level security;

drop policy if exists "anyone can read shared armies"    on public.shared_armies;
drop policy if exists "creators can insert shared army"  on public.shared_armies;
drop policy if exists "creators can delete shared army"  on public.shared_armies;

create policy "anyone can read shared armies"
  on public.shared_armies for select to authenticated
  using (true);

create policy "creators can insert shared army"
  on public.shared_armies for insert to authenticated
  with check (created_by = auth.uid());

create policy "creators can delete shared army"
  on public.shared_armies for delete to authenticated
  using (created_by = auth.uid());


-- ── custom_units / custom_factions / custom_abilities / game_config ──────────
-- Global game data: all authenticated users can read; only service_role / admin writes.
-- (Writes happen only through the Dev screen which runs as service_role or a trusted admin account.)
alter table public.custom_units     enable row level security;
alter table public.custom_factions  enable row level security;
alter table public.custom_abilities enable row level security;
alter table public.game_config      enable row level security;

drop policy if exists "read custom_units"     on public.custom_units;
drop policy if exists "read custom_factions"  on public.custom_factions;
drop policy if exists "read custom_abilities" on public.custom_abilities;
drop policy if exists "read game_config"      on public.game_config;

create policy "read custom_units"
  on public.custom_units for select to authenticated using (true);

create policy "read custom_factions"
  on public.custom_factions for select to authenticated using (true);

create policy "read custom_abilities"
  on public.custom_abilities for select to authenticated using (true);

create policy "read game_config"
  on public.game_config for select to authenticated using (true);

-- Developers (profiles.role = 'developer') can write global game data.
drop policy if exists "developers can write custom_units"     on public.custom_units;
drop policy if exists "developers can write custom_factions"  on public.custom_factions;
drop policy if exists "developers can write custom_abilities" on public.custom_abilities;
drop policy if exists "developers can write game_config"      on public.game_config;

create policy "developers can write custom_units"
  on public.custom_units for all to authenticated
  using     (exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'))
  with check(exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'));

create policy "developers can write custom_factions"
  on public.custom_factions for all to authenticated
  using     (exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'))
  with check(exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'));

create policy "developers can write custom_abilities"
  on public.custom_abilities for all to authenticated
  using     (exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'))
  with check(exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'));

create policy "developers can write game_config"
  on public.game_config for all to authenticated
  using     (exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'))
  with check(exists (select 1 from public.profiles where id = auth.uid() and role = 'developer'));
