-- C3 Check Control - initial Supabase schema
-- Schema only: no C3 task data is imported or changed by this migration.
-- The existing index.html and Excel source remain the authoritative pre-migration baseline.

create extension if not exists pgcrypto;

create table public.check_packages (
  id uuid primary key default gen_random_uuid(),
  check_name text not null,
  aircraft_registration text,
  source_filename text,
  source_hash text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.tasks (
  id uuid primary key default gen_random_uuid(),
  check_package_id uuid not null references public.check_packages(id) on delete cascade,
  task_id text not null,
  description text,
  section text,
  skill text,
  est_hours numeric(10,2) not null default 0,
  used_hours numeric(10,2) not null default 0,
  sign_stamp text,
  task_date date,
  task_received date,
  status text,
  mpd_task_no text,
  unscheduled boolean not null default false,
  remarks text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index tasks_package_task_id_uq on public.tasks (check_package_id, task_id);
create index tasks_package_idx on public.tasks (check_package_id);
create index tasks_status_idx on public.tasks (check_package_id, status);
create index tasks_unscheduled_idx on public.tasks (check_package_id, unscheduled);
create index tasks_skill_idx on public.tasks (check_package_id, skill);
create index tasks_task_date_idx on public.tasks (check_package_id, task_date);

-- Immutable source representation for lossless migration verification.
create table public.task_source_snapshot (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  source_format text not null,
  source_payload jsonb not null,
  captured_at timestamptz not null default now()
);
create unique index task_source_snapshot_task_uq on public.task_source_snapshot (task_id);

-- Operational audit history; populated when application persistence is implemented.
create table public.task_history (
  id uuid primary key default gen_random_uuid(),
  task_id uuid not null references public.tasks(id) on delete cascade,
  changed_by uuid,
  changed_at timestamptz not null default now(),
  action text not null,
  old_values jsonb,
  new_values jsonb
);
create index task_history_task_idx on public.task_history (task_id, changed_at desc);

-- Backup metadata; existing Backup/Restore will be connected later.
create table public.backup_records (
  id uuid primary key default gen_random_uuid(),
  created_by uuid,
  created_at timestamptz not null default now(),
  check_package_id uuid not null references public.check_packages(id) on delete cascade,
  format text not null,
  metadata jsonb not null default '{}'::jsonb
);
create index backup_records_package_idx on public.backup_records (check_package_id, created_at desc);

-- Calculated progress summaries for existing KPI/progress requirements.
create view public.task_progress_summary as
select
  t.check_package_id,
  count(*)::bigint as total_tasks,
  count(*) filter (where t.unscheduled)::bigint as unscheduled_tasks,
  count(*) filter (where not t.unscheduled)::bigint as scheduled_tasks,
  count(*) filter (where upper(coalesce(t.status, '')) in ('CLOSED', 'C3 COMPLETE'))::bigint as closed_tasks,
  coalesce(sum(t.est_hours), 0)::numeric(12,2) as estimated_hours,
  coalesce(sum(t.used_hours), 0)::numeric(12,2) as used_hours,
  coalesce(sum(t.est_hours) filter (where t.unscheduled), 0)::numeric(12,2) as unscheduled_estimated_hours,
  coalesce(sum(t.used_hours) filter (where t.unscheduled), 0)::numeric(12,2) as unscheduled_used_hours
from public.tasks t
group by t.check_package_id;

create view public.task_progress_by_skill as
select
  t.check_package_id,
  coalesce(nullif(trim(t.skill), ''), 'UNASSIGNED') as skill,
  count(*)::bigint as task_count,
  coalesce(sum(t.est_hours), 0)::numeric(12,2) as estimated_hours,
  coalesce(sum(t.used_hours), 0)::numeric(12,2) as used_hours
from public.tasks t
group by t.check_package_id, coalesce(nullif(trim(t.skill), ''), 'UNASSIGNED');

-- RLS is enabled before any Data API exposure. Policies are added with Auth later.
alter table public.check_packages enable row level security;
alter table public.tasks enable row level security;
alter table public.task_source_snapshot enable row level security;
alter table public.task_history enable row level security;
alter table public.backup_records enable row level security;

comment on table public.check_packages is 'C3 check/work-package metadata; schema only until authorised data migration.';
comment on table public.tasks is 'Scheduled and unscheduled C3 operational tasks; schema only until authorised data migration.';
comment on table public.task_source_snapshot is 'Immutable source representation retained for lossless migration verification.';
comment on view public.task_progress_summary is 'Calculated task and man-hour progress for C3 KPI/progress tracking.';
comment on view public.task_progress_by_skill is 'Calculated estimated-versus-used man-hours by skill for C3 progress graphs.';
