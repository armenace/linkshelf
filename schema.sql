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

-- Names nobody can claim, so no one can pose as the site or its staff.
-- (Added with ALTER so it also reaches databases created by an older version of this file.)
alter table public.profiles drop constraint if exists profiles_username_not_reserved;
alter table public.profiles add constraint profiles_username_not_reserved
  check (username not in (
    'admin', 'administrator', 'root', 'support', 'help', 'linkshelf', 'official', 'staff',
    'moderator', 'mod', 'security', 'abuse', 'team', 'system', 'api', 'www', 'mail',
    'login', 'signin', 'signup', 'settings', 'account', 'about', 'terms', 'privacy', 'null', 'undefined'
  ));

-- When someone changes their username, the old one is kept for them, so links they
-- already shared redirect to the new name instead of being claimed by a stranger.
create table if not exists public.username_history (
  username   text primary key,
  user_id    uuid not null references public.profiles (id) on delete cascade,
  retired_at timestamptz not null default now()
);

-- Who clicked which link in the last hour, so one visitor counts once per link per hour.
-- Stores a hash of the visitor's IP address, never the address itself.
create table if not exists public.click_log (
  link_id    uuid not null references public.links (id) on delete cascade,
  visitor    text not null,
  clicked_at timestamptz not null default now(),
  primary key (link_id, visitor)
);
create index if not exists click_log_clicked_at_idx on public.click_log (clicked_at);

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
-- the counter function below, not when a link is created or edited.
-- (Column-level privileges, on top of RLS.)
revoke insert, update on public.links from anon, authenticated;
grant  insert (user_id, title, url, position) on public.links to authenticated;
grant  update (title, url, position) on public.links to authenticated;

-- Old usernames are public (so old links can redirect) but only the trigger below writes them.
alter table public.username_history enable row level security;
drop policy if exists "Old usernames are public" on public.username_history;
create policy "Old usernames are public"
  on public.username_history for select
  using (true);
revoke insert, update, delete on public.username_history from anon, authenticated;

-- The click log is private: no policies, and no access for website visitors at all.
alter table public.click_log enable row level security;
revoke all on public.click_log from anon, authenticated;

-- ---------- Click counter ----------
-- Visitors aren't signed in, so they can't update links directly.
-- This function adds at most +1 per visitor per link per hour, and nothing else.

create or replace function public.increment_click(link_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  ip text := split_part(current_setting('request.headers', true)::json ->> 'x-forwarded-for', ',', 1);
  added integer;
begin
  if not exists (select 1 from public.links l where l.id = increment_click.link_id) then
    return;
  end if;

  delete from public.click_log where clicked_at < now() - interval '1 hour';

  if coalesce(ip, '') = '' then
    added := 1;   -- no address to go by (not a normal web request): just count it
  else
    insert into public.click_log (link_id, visitor)
    values (increment_click.link_id, md5(ip || increment_click.link_id::text))
    on conflict do nothing;
    get diagnostics added = row_count;
  end if;

  if added > 0 then
    update public.links l set clicks = l.clicks + 1 where l.id = increment_click.link_id;
  end if;
end;
$$;

revoke all on function public.increment_click(uuid) from public, anon, authenticated;
grant execute on function public.increment_click(uuid) to anon, authenticated;

-- ---------- Username changes ----------
-- Runs on every new profile and every username change:
--  - refuses a name that is another person's old username (reported like a taken name),
--  - remembers your old name for you, keeping your 3 most recent old names.

create or replace function public.guard_username()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if exists (select 1 from public.username_history h
             where h.username = new.username and h.user_id <> new.id) then
    raise exception 'username "%" is taken', new.username using errcode = '23505';
  end if;

  if tg_op = 'UPDATE' and new.username <> old.username then
    delete from public.username_history where username = new.username;   -- taking back your own old name
    insert into public.username_history (username, user_id) values (old.username, old.id)
      on conflict (username) do update set user_id = excluded.user_id, retired_at = now();
    delete from public.username_history h
      where h.user_id = old.id
        and h.username not in (select h2.username from public.username_history h2
                               where h2.user_id = old.id order by h2.retired_at desc limit 3);
  end if;
  return new;
end;
$$;

revoke all on function public.guard_username() from public, anon, authenticated;

drop trigger if exists profiles_guard_username on public.profiles;
create trigger profiles_guard_username
  before insert or update of username on public.profiles
  for each row execute function public.guard_username();

-- ---------- Delete my account ----------
-- Lets a signed-in user delete their own login. Their profile, links,
-- old usernames and click log are removed with it (on delete cascade).

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in' using errcode = '42501';
  end if;
  delete from auth.users where id = auth.uid();
end;
$$;

revoke all on function public.delete_my_account() from public, anon, authenticated;
grant execute on function public.delete_my_account() to authenticated;
