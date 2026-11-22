-- =============================================================================
-- Open Digital Twin Platform - 019 Sea trial and delivery checklists
--
--   * public.handover_checklist_items  checklist of a hull's sea trials or
--     delivery row: trials (speed, endurance, crash stop, manoeuvres, steering,
--     anchoring, ...), certificates, documents and handover items. Status
--     open -> done, or waived with a reason (notes).
-- Rules:
--   * an item belongs to a hull-level `sea_trials` / `delivery` row of the same
--     project; the hull follows the row; one item per row and code.
--   * the row cannot be reported finished (actual_end) while a required item of
--     its checklist is open; delivery also needs a checklist and every sea
--     trials row of the hull finished.
--   * the hull row follows the handover: sea trials started -> `sea_trials`,
--     delivery finished -> `delivered` and no yard location, delivery reopened
--     -> back at the delivery row's area (`sea_trials`).
-- =============================================================================

create table if not exists public.handover_checklist_items (
    id              uuid primary key default gen_random_uuid(),
    project_id      uuid not null references public.projects (id) on delete cascade,
    hull_id         uuid references public.hulls (id) on delete cascade,
    activity_id     uuid not null references public.production_activities (id) on delete cascade,
    item_code       text not null,
    title           text not null,
    category        text not null default 'trial'
                    check (category in ('trial', 'certificate', 'document', 'handover')),
    required        boolean not null default true,
    status          text not null default 'open' check (status in ('open', 'done', 'waived')),
    completed_at    timestamptz,
    completed_by    text,
    notes           text,
    sort_order      integer not null default 0,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    unique (activity_id, item_code),
    check (status <> 'waived' or nullif(btrim(notes), '') is not null)
);

comment on table public.handover_checklist_items is
    'Sea trial / delivery checklist items of a hull-level schedule row (open, done, waived with a reason).';

create index if not exists handover_checklist_items_project_idx
    on public.handover_checklist_items (project_id, activity_id, sort_order);

drop trigger if exists handover_checklist_items_set_updated_at on public.handover_checklist_items;
create trigger handover_checklist_items_set_updated_at
    before update on public.handover_checklist_items
    for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- Item rules: hull-level sea trials / delivery row, completion time
-- -----------------------------------------------------------------------------
create or replace function public._check_checklist_item()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_row record;
begin
    select a.project_id, a.hull_id, a.component_id, a.stage, a.activity_code
      into v_row
      from public.production_activities a
     where a.id = new.activity_id;
    if v_row.project_id is distinct from new.project_id then
        raise exception 'Checklist item %: the schedule row does not belong to this project', new.item_code
            using errcode = 'check_violation';
    end if;
    if v_row.component_id is not null or v_row.hull_id is null or v_row.stage not in ('sea_trials', 'delivery') then
        raise exception 'Checklist item %: % is not a sea trials or delivery row of a hull', new.item_code, v_row.activity_code
            using errcode = 'check_violation';
    end if;
    new.hull_id := v_row.hull_id;

    if new.status = 'open' then
        new.completed_at := null;
        new.completed_by := null;
    elsif tg_op = 'INSERT' or old.status is distinct from new.status then
        new.completed_at := coalesce(new.completed_at, now());
    end if;
    return new;
end;
$$;

drop trigger if exists handover_checklist_items_check on public.handover_checklist_items;
create trigger handover_checklist_items_check
    before insert or update on public.handover_checklist_items
    for each row execute function public._check_checklist_item();

-- -----------------------------------------------------------------------------
-- Sea trials / delivery finished only with a complete checklist
-- -----------------------------------------------------------------------------
create or replace function public._check_handover_ready()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_items integer;
    v_open  integer;
    v_codes text;
begin
    if new.stage not in ('sea_trials', 'delivery') or new.hull_id is null or new.component_id is not null
       or new.actual_end is null or old.actual_end is not null then
        return new;
    end if;

    select count(*),
           count(*) filter (where c.required and c.status = 'open'),
           string_agg(c.item_code, ', ' order by c.sort_order, c.item_code) filter (where c.required and c.status = 'open')
      into v_items, v_open, v_codes
      from public.handover_checklist_items c
     where c.activity_id = new.id;
    if v_open > 0 then
        raise exception '% cannot be finished - % required checklist item(s) open: %', new.activity_code, v_open, v_codes
            using errcode = 'check_violation';
    end if;

    if new.stage = 'delivery' then
        if v_items = 0 then
            raise exception '% cannot be finished without a delivery checklist - create it first (Production: tap the delivery bar)',
                new.activity_code
                using errcode = 'check_violation';
        end if;
        select string_agg(a.activity_code, ', ' order by a.planned_start)
          into v_codes
          from public.production_activities a
         where a.hull_id = new.hull_id
           and a.stage = 'sea_trials'
           and a.component_id is null
           and a.actual_end is null;
        if v_codes is not null then
            raise exception '% cannot be finished before the sea trials: % not finished', new.activity_code, v_codes
                using errcode = 'check_violation';
        end if;
    end if;
    return new;
end;
$$;

-- Update only: the seed inserts finished rows before their checklists.
drop trigger if exists production_activities_handover_ready on public.production_activities;
create trigger production_activities_handover_ready
    before update of actual_end on public.production_activities
    for each row execute function public._check_handover_ready();

-- -----------------------------------------------------------------------------
-- Hull status follows sea trials and delivery
-- -----------------------------------------------------------------------------
create or replace function public._hull_follows_handover()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if new.hull_id is null or new.component_id is not null then
        return null;
    end if;
    if new.stage = 'sea_trials' and new.actual_start is not null
       and (tg_op = 'INSERT' or old.actual_start is null) then
        update public.hulls h
           set status = 'sea_trials'
         where h.id = new.hull_id and h.status = 'afloat_outfitting';
    elsif new.stage = 'delivery' then
        if new.actual_end is not null and (tg_op = 'INSERT' or old.actual_end is null) then
            update public.hulls h
               set status = 'delivered', location_node_id = null
             where h.id = new.hull_id;
        elsif tg_op = 'UPDATE' and old.actual_end is not null and new.actual_end is null then
            update public.hulls h
               set status = 'sea_trials', location_node_id = coalesce(new.location_node_id, h.location_node_id)
             where h.id = new.hull_id and h.status = 'delivered';
        end if;
    end if;
    return null;
end;
$$;

drop trigger if exists production_activities_hull_handover on public.production_activities;
create trigger production_activities_hull_handover
    after insert or update of actual_start, actual_end on public.production_activities
    for each row execute function public._hull_follows_handover();

select public._odt_secure_table('handover_checklist_items', false);
