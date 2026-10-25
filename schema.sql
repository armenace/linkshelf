-- =====================================================================
-- Linkshelf database setup
-- Paste this whole file into Supabase: SQL Editor -> New query -> Run.
-- Safe to run more than once.
-- =====================================================================

-- ---------- Tables ----------

-- One profile per user. "id" is the same id Supabase Auth gives the user.
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  username     text not null unique
               check (username ~ '^[a-z0-9_]{3,24}$'),
  display_name text not null default ''
               check (char_length(display_name) <= 60),
  bio          text not null default ''
               check (char_length(bio) <= 160),
  theme        text not null default 'cobalt'
               check (theme in ('cobalt', 'paper', 'night', 'lemon', 'mint')),
  created_at   timestamptz not null default now()
);

-- Each link belongs to one profile.
create table if not exists public.links (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references public.profiles (id) on delete cascade,
  title      text not null check (char_length(title) between 1 and 80),
  -- Only real web links. Blocks "javascript:" and other tricks.
  url        text not null check (url ~* '^https?://[^\s]+$' and char_length(url) <= 500),
  position   integer not null default 0,
  clicks     integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists links_user_position_idx on public.links (user_id, position);

-- ---------- Row Level Security (who can do what) ----------
-- Everyone can READ profiles and links (they're public pages).
-- Only the owner can CREATE, CHANGE or DELETE their own rows.

alter table public.profiles enable row level security;
alter table public.links    enable row level security;

drop policy if exists "Profiles are public"            on public.profiles;
drop policy if exists "Users create their own profile" on public.profiles;
drop policy if exists "Users edit their own profile"   on public.profiles;
drop policy if exists "Users delete their own profile" on public.profiles;

create policy "Profiles are public"
  on public.profiles for select
  using (true);

create policy "Users create their own profile"
  on public.profiles for insert to authenticated
  with check ((select auth.uid()) = id);

create policy "Users edit their own profile"
  on public.profiles for update to authenticated
  using ((select auth.uid()) = id)
  with check ((select auth.uid()) = id);

create policy "Users delete their own profile"
  on public.profiles for delete to authenticated
  using ((select auth.uid()) = id);

drop policy if exists "Links are public"            on public.links;
drop policy if exists "Users add their own links"    on public.links;
drop policy if exists "Users edit their own links"   on public.links;
drop policy if exists "Users delete their own links" on public.links;

create policy "Links are public"
  on public.links for select
  using (true);

create policy "Users add their own links"
  on public.links for insert to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users edit their own links"
  on public.links for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users delete their own links"
  on public.links for delete to authenticated
  using ((select auth.uid()) = user_id);

-- Owners can't fake their own click counts: clicks only change through
-- the counter function below. (Column-level privilege, on top of RLS.)
revoke update on public.links from anon, authenticated;
grant  update (title, url, position) on public.links to authenticated;

-- ---------- Click counter ----------
-- Visitors aren't signed in, so they can't update links directly.
-- This function adds exactly +1 to one link and nothing else.

create or replace function public.increment_click(link_id uuid)
returns void
language sql
security definer
set search_path = ''
as $$
  update public.links set clicks = clicks + 1 where id = link_id;
$$;

revoke all on function public.increment_click(uuid) from public;
grant execute on function public.increment_click(uuid) to anon, authenticated;
