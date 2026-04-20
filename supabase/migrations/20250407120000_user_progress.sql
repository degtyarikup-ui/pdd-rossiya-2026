-- Прогресс приложения ПДД: один ряд на пользователя (Supabase Auth).
-- Выполните в SQL Editor проекта Supabase, если не используете CLI migrate.

create table if not exists public.user_progress (
  user_id uuid primary key references auth.users (id) on delete cascade,
  question_progress_ab jsonb not null default '{}'::jsonb,
  question_progress_cd jsonb not null default '{}'::jsonb,
  ticket_progress_ab jsonb not null default '{}'::jsonb,
  ticket_progress_cd jsonb not null default '{}'::jsonb,
  favorites_ab jsonb not null default '[]'::jsonb,
  favorites_cd jsonb not null default '[]'::jsonb,
  exam_results_ab jsonb not null default '[]'::jsonb,
  exam_results_cd jsonb not null default '[]'::jsonb,
  app_settings jsonb not null default '{}'::jsonb,
  updated_at_ms bigint not null default 0
);

comment on table public.user_progress is 'Синхронизируемый прогресс билетов ПДД (клиент: last-write-wins по updated_at_ms).';

alter table public.user_progress enable row level security;

create policy "user_progress_select_own"
  on public.user_progress for select
  using (auth.uid() = user_id);

create policy "user_progress_insert_own"
  on public.user_progress for insert
  with check (auth.uid() = user_id);

create policy "user_progress_update_own"
  on public.user_progress for update
  using (auth.uid() = user_id);
