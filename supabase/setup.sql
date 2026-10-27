-- compareme: answers, question suggestions, votes and community questions.
-- Run once in your Supabase project: SQL Editor -> New query -> paste -> Run.
-- Safe to run again. All tables are prefixed cm_ so they can share a project
-- with other apps.

-- ---------------------------------------------------------------------------
-- Answers: one row per signed-in person.
-- ---------------------------------------------------------------------------
create table if not exists public.cm_responses (
  user_id    uuid        primary key default auth.uid() references auth.users (id) on delete cascade,
  demo       jsonb       not null default '{}'::jsonb,
  answers    jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint cm_responses_shape check (jsonb_typeof(demo) = 'object' and jsonb_typeof(answers) = 'object'),
  constraint cm_responses_size  check (pg_column_size(demo) + pg_column_size(answers) < 16000)
);
alter table public.cm_responses enable row level security;

drop policy if exists "Read own answers"   on public.cm_responses;
drop policy if exists "Insert own answers" on public.cm_responses;
drop policy if exists "Update own answers" on public.cm_responses;
drop policy if exists "Delete own answers" on public.cm_responses;
create policy "Read own answers"   on public.cm_responses for select to authenticated using (auth.uid() = user_id);
create policy "Insert own answers" on public.cm_responses for insert to authenticated with check (auth.uid() = user_id);
create policy "Update own answers" on public.cm_responses for update to authenticated using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "Delete own answers" on public.cm_responses for delete to authenticated using (auth.uid() = user_id);

-- The crowd: everyone else's answers, with no user ids, names or emails.
create or replace function public.cm_get_crowd()
returns table (demo jsonb, answers jsonb)
language sql stable security definer set search_path = public as $$
  select r.demo, r.answers
  from public.cm_responses r
  where r.user_id is distinct from auth.uid()
  order by r.updated_at desc
  limit 5000;
$$;
grant execute on function public.cm_get_crowd() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Admins: who can add suggestions to the survey. Nobody can read or change
-- this table through the API; add yourself with the statement at the bottom.
-- ---------------------------------------------------------------------------
create table if not exists public.cm_admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);
alter table public.cm_admins enable row level security;

-- Admins by email: anyone signed in with one of these (verified) addresses is an admin.
create table if not exists public.cm_admin_emails (
  email text primary key check (email = lower(email))
);
alter table public.cm_admin_emails enable row level security;
insert into public.cm_admin_emails (email) values ('robbiestells@gmail.com') on conflict do nothing;

create or replace function public.cm_is_admin()
returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.cm_admins where user_id = auth.uid())
      or exists (select 1 from public.cm_admin_emails where email = lower(coalesce(auth.jwt() ->> 'email', '')));
$$;
grant execute on function public.cm_is_admin() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Suggested questions and votes.
-- ---------------------------------------------------------------------------
create table if not exists public.cm_suggestions (
  id         uuid        primary key default gen_random_uuid(),
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  text       text        not null check (char_length(text) between 8 and 140),
  type       text        not null check (type in ('num', 'one', 'many')),
  unit       text        check (unit is null or char_length(unit) <= 20),
  options    jsonb       check (options is null or (jsonb_typeof(options) = 'array' and jsonb_array_length(options) <= 10)),
  status     text        not null default 'open' check (status in ('open', 'added', 'dismissed')),
  created_at timestamptz not null default now()
);
alter table public.cm_suggestions enable row level security;

drop policy if exists "Insert own suggestions"     on public.cm_suggestions;
drop policy if exists "Delete own open suggestions" on public.cm_suggestions;
drop policy if exists "Admins update suggestions"  on public.cm_suggestions;
drop policy if exists "Read own or admin"          on public.cm_suggestions;
create policy "Insert own suggestions"      on public.cm_suggestions for insert to authenticated with check (auth.uid() = user_id and status = 'open');
create policy "Delete own open suggestions" on public.cm_suggestions for delete to authenticated using (auth.uid() = user_id and status = 'open');
create policy "Admins update suggestions"   on public.cm_suggestions for update to authenticated using (public.cm_is_admin()) with check (public.cm_is_admin());
create policy "Read own or admin"           on public.cm_suggestions for select to authenticated using (auth.uid() = user_id or public.cm_is_admin());

-- At most 20 suggestions per person.
create or replace function public.cm_suggestion_limit()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.cm_suggestions where user_id = new.user_id) >= 20 then
    raise exception 'Suggestion limit reached';
  end if;
  return new;
end $$;
drop trigger if exists cm_suggestion_limit on public.cm_suggestions;
create trigger cm_suggestion_limit before insert on public.cm_suggestions
  for each row execute function public.cm_suggestion_limit();

create table if not exists public.cm_votes (
  suggestion_id uuid not null references public.cm_suggestions (id) on delete cascade,
  user_id       uuid not null default auth.uid() references auth.users (id) on delete cascade,
  primary key (suggestion_id, user_id)
);
alter table public.cm_votes enable row level security;

drop policy if exists "Read own votes"   on public.cm_votes;
drop policy if exists "Insert own votes" on public.cm_votes;
drop policy if exists "Delete own votes" on public.cm_votes;
create policy "Read own votes"   on public.cm_votes for select to authenticated using (auth.uid() = user_id);
create policy "Insert own votes" on public.cm_votes for insert to authenticated with check (auth.uid() = user_id);
create policy "Delete own votes" on public.cm_votes for delete to authenticated using (auth.uid() = user_id);

-- The suggestion board: vote counts plus whether each one is yours or has
-- your vote. Never returns who suggested or voted.
create or replace function public.cm_get_suggestions()
returns table (id uuid, text text, type text, unit text, options jsonb, status text,
               created_at timestamptz, votes integer, mine boolean, voted boolean)
language sql stable security definer set search_path = public as $$
  select s.id, s.text, s.type, s.unit, s.options, s.status, s.created_at,
         (select count(*) from public.cm_votes v where v.suggestion_id = s.id)::integer,
         coalesce(s.user_id = auth.uid(), false),
         exists (select 1 from public.cm_votes v where v.suggestion_id = s.id and v.user_id = auth.uid())
  from public.cm_suggestions s
  where s.status <> 'dismissed'
  order by 8 desc, s.created_at desc
  limit 300;
$$;
grant execute on function public.cm_get_suggestions() to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Community questions that made it into the survey. Everyone reads them;
-- only admins change them.
-- ---------------------------------------------------------------------------
create table if not exists public.cm_questions (
  id              text        primary key check (id ~ '^c_[a-z0-9]{4,16}$'),
  label           text        not null check (char_length(label) between 1 and 140),
  type            text        not null check (type in ('num', 'one', 'many')),
  unit            text        check (unit is null or char_length(unit) <= 20),
  options         jsonb       check (options is null or jsonb_typeof(options) = 'array'),
  from_suggestion uuid        references public.cm_suggestions (id) on delete set null,
  created_at      timestamptz not null default now()
);
alter table public.cm_questions enable row level security;

-- Section each community question appears under (picked by an admin when approving).
alter table public.cm_questions add column if not exists cat text not null default 'Community';
alter table public.cm_questions drop constraint if exists cm_questions_cat;
alter table public.cm_questions add constraint cm_questions_cat check (cat in ('Money', 'Work', 'Lifestyle', 'Fun', 'Community'));

drop policy if exists "Anyone reads questions" on public.cm_questions;
drop policy if exists "Admins write questions" on public.cm_questions;
create policy "Anyone reads questions" on public.cm_questions for select to anon, authenticated using (true);
create policy "Admins write questions" on public.cm_questions for all to authenticated using (public.cm_is_admin()) with check (public.cm_is_admin());

-- ---------------------------------------------------------------------------
-- Admin view: every suggestion, including dismissed ones, with vote counts and
-- whether it's live in the survey. Returns nothing for non-admins. Never
-- returns who suggested or voted.
-- ---------------------------------------------------------------------------
drop function if exists public.cm_admin_suggestions();
create or replace function public.cm_admin_suggestions()
returns table (id uuid, text text, type text, unit text, options jsonb, status text,
               created_at timestamptz, votes integer, question_id text, question_cat text)
language sql stable security definer set search_path = public as $$
  select s.id, s.text, s.type, s.unit, s.options, s.status, s.created_at,
         (select count(*) from public.cm_votes v where v.suggestion_id = s.id)::integer,
         (select q.id from public.cm_questions q where q.from_suggestion = s.id limit 1),
         (select q.cat from public.cm_questions q where q.from_suggestion = s.id limit 1)
  from public.cm_suggestions s
  where public.cm_is_admin()
  order by s.created_at desc
  limit 1000;
$$;
grant execute on function public.cm_admin_suggestions() to authenticated;

-- ---------------------------------------------------------------------------
-- More admins: add their email here (lowercase), or by user id:
--   insert into public.cm_admin_emails (email) values ('someone@example.com') on conflict do nothing;
-- ---------------------------------------------------------------------------
