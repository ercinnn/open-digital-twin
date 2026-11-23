-- =============================================================================
-- Open Digital Twin Platform - 021 Block slots inside the yard areas
--
--   * public.area_slots              numbered work places of an area (assembly hall
--                                    bays, paint cells, joining yard stool groups):
--                                    centre and size in yard plan coordinates
--                                    (metres, Blender x / y; viewer x = x, z = -y),
--                                    optional max load
--   * production_activities.slot_no  the slot a block row occupies in its area
--   * rules                          only block rows take a slot, the slot must exist
--                                    in the row's area and carry the block weight;
--                                    two rows cannot hold the same slot in
--                                    overlapping planned windows (exclusion
--                                    constraint, 23P01); moving a row to another
--                                    area clears its slot
--   * demo shipyard                  42 slots in areas 5-10 (also in seed.sql)
-- =============================================================================

create extension if not exists btree_gist with schema extensions;

create table if not exists public.area_slots (
    id              uuid primary key default gen_random_uuid(),
    project_id      uuid not null references public.projects (id) on delete cascade,
    component_id    uuid not null references public.components (id) on delete cascade,
    slot_no         smallint not null check (slot_no between 1 and 99),
    code            text not null check (length(trim(code)) > 0),
    center_x_m      numeric not null,
    center_y_m      numeric not null,
    size_x_m        numeric not null check (size_x_m > 0),
    size_y_m        numeric not null check (size_y_m > 0),
    max_load_t      numeric check (max_load_t is null or max_load_t > 0),
    notes           text,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now(),
    unique (component_id, slot_no),
    unique (project_id, code)
);

comment on table public.area_slots is
    'Work places (slots) of a yard area for blocks; centre / size in yard plan metres (viewer x = x, z = -y).';

create index if not exists area_slots_project_idx on public.area_slots (project_id, component_id, slot_no);

drop trigger if exists area_slots_set_updated_at on public.area_slots;
create trigger area_slots_set_updated_at
    before update on public.area_slots
    for each row execute function public.set_updated_at();

create or replace function public._check_area_slot()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if not exists (
        select 1 from public.components c where c.id = new.component_id and c.project_id = new.project_id
    ) then
        raise exception 'Area % does not belong to this project', new.component_id using errcode = 'check_violation';
    end if;
    new.code := upper(trim(new.code));
    return new;
end;
$$;

drop trigger if exists area_slots_check on public.area_slots;
create trigger area_slots_check
    before insert or update of project_id, component_id, code on public.area_slots
    for each row execute function public._check_area_slot();

select public._odt_secure_table('area_slots', false);

-- -----------------------------------------------------------------------------
-- Slot of a schedule row
-- -----------------------------------------------------------------------------
alter table public.production_activities
    add column if not exists slot_no smallint check (slot_no is null or slot_no between 1 and 99);

comment on column public.production_activities.slot_no is
    'Slot (area_slots.slot_no) of the row''s area the block occupies; null = no fixed place.';

create or replace function public._check_activity_slot()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_slot record;
    v_weight_t numeric;
begin
    -- A row moved to another area loses its slot unless a new one is given.
    if tg_op = 'UPDATE'
       and new.location_node_id is distinct from old.location_node_id
       and new.slot_no is not distinct from old.slot_no then
        new.slot_no := null;
    end if;
    if new.slot_no is null then
        return new;
    end if;

    if new.component_id is null then
        raise exception 'Only block rows take an area slot (%)', new.activity_code using errcode = 'check_violation';
    end if;

    select s.code, s.max_load_t, c.name as area_name
      into v_slot
      from public.components c
      join public.area_slots s on s.component_id = c.id and s.slot_no = new.slot_no
     where c.project_id = new.project_id
       and c.mesh_node_id = new.location_node_id;
    if not found then
        raise exception 'Area % has no slot %', coalesce(new.location_node_id, '(none)'), new.slot_no
            using errcode = 'check_violation';
    end if;

    if v_slot.max_load_t is not null then
        select b.weight_kg / 1000.0 into v_weight_t from public.components b where b.id = new.component_id;
        if v_weight_t is not null and v_weight_t > v_slot.max_load_t then
            raise exception 'Block % (% t) is heavier than slot % allows (% t)',
                new.activity_code, round(v_weight_t, 1), v_slot.code, v_slot.max_load_t
                using errcode = 'check_violation';
        end if;
    end if;
    return new;
end;
$$;

drop trigger if exists production_activities_slot_check on public.production_activities;
create trigger production_activities_slot_check
    before insert or update of slot_no, location_node_id, component_id, project_id
    on public.production_activities
    for each row execute function public._check_activity_slot();

alter table public.production_activities drop constraint if exists production_activities_slot_overlap;
alter table public.production_activities
    add constraint production_activities_slot_overlap exclude using gist (
        project_id with =,
        location_node_id with =,
        slot_no with =,
        daterange(planned_start, planned_end, '[)') with &&
    ) where (slot_no is not null);

-- -----------------------------------------------------------------------------
-- Demo shipyard: slots of areas 5-10 (plan coordinates of generate_sample_models.py)
-- -----------------------------------------------------------------------------
insert into public.area_slots
    (project_id, component_id, slot_no, code, center_x_m, center_y_m, size_x_m, size_y_m, max_load_t, notes)
select p.id, c.id, x.slot_no, x.code, x.cx, x.cy, x.sx, x.sy, x.max_t, x.notes
from public.projects p
cross join (values
    -- area node,                              no, code,     centre x, y,      size x, y,  max t, notes
    ('NODE_A05_CNC_CUTTING_SHOP',               1, 'A05-01', 565.0,  466.25,  44, 28,  null::numeric, 'Plasma table 1'),
    ('NODE_A05_CNC_CUTTING_SHOP',               2, 'A05-02', 615.0,  466.25,  44, 28,  null, 'Plasma table 2'),
    ('NODE_A05_CNC_CUTTING_SHOP',               3, 'A05-03', 565.0,  498.75,  44, 28,  null, 'Plasma table 3'),
    ('NODE_A05_CNC_CUTTING_SHOP',               4, 'A05-04', 615.0,  498.75,  44, 28,  null, 'Profile cutting line'),
    ('NODE_A06_BENDING_PRESS_SHOP',             1, 'A06-01', 670.0,  482.5,   26, 56,  null, '1000 t press'),
    ('NODE_A06_BENDING_PRESS_SHOP',             2, 'A06-02', 700.0,  482.5,   26, 56,  null, 'Plate rolls'),
    ('NODE_A06_BENDING_PRESS_SHOP',             3, 'A06-03', 730.0,  482.5,   26, 56,  null, 'Frame bender'),
    ('NODE_A07_PANEL_SUB_ASSEMBLY_LINE',        1, 'A07-01', 640.8,  357.5,   38, 30,  null, 'Panel line station 1'),
    ('NODE_A07_PANEL_SUB_ASSEMBLY_LINE',        2, 'A07-02', 682.5,  357.5,   38, 30,  null, 'Panel line station 2'),
    ('NODE_A07_PANEL_SUB_ASSEMBLY_LINE',        3, 'A07-03', 724.2,  357.5,   38, 30,  null, 'Panel line station 3'),
    ('NODE_A07_PANEL_SUB_ASSEMBLY_LINE',        4, 'A07-04', 640.8,  392.5,   38, 30,  null, 'Sub-assembly bay 1'),
    ('NODE_A07_PANEL_SUB_ASSEMBLY_LINE',        5, 'A07-05', 682.5,  392.5,   38, 30,  null, 'Sub-assembly bay 2'),
    ('NODE_A07_PANEL_SUB_ASSEMBLY_LINE',        6, 'A07-06', 724.2,  392.5,   38, 30,  null, 'Sub-assembly bay 3'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            1, 'A08-01', 460.0,  352.5,   36, 40,  200, 'Bay 1 (4 x 50 t cranes in tandem)'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            2, 'A08-02', 500.0,  352.5,   36, 40,  200, 'Bay 2'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            3, 'A08-03', 540.0,  352.5,   36, 40,  200, 'Bay 3'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            4, 'A08-04', 580.0,  352.5,   36, 40,  200, 'Bay 4'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            5, 'A08-05', 460.0,  397.5,   36, 40,  200, 'Bay 5'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            6, 'A08-06', 500.0,  397.5,   36, 40,  200, 'Bay 6'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            7, 'A08-07', 540.0,  397.5,   36, 40,  200, 'Bay 7'),
    ('NODE_A08_BLOCK_ASSEMBLY_HALL',            8, 'A08-08', 580.0,  397.5,   36, 40,  200, 'Bay 8'),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     1, 'A09-01', 262.0,  215.0,   50, 34,  null, 'Stool group row 1'),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     2, 'A09-02', 317.0,  215.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     3, 'A09-03', 372.0,  215.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     4, 'A09-04', 427.0,  215.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     5, 'A09-05', 482.0,  215.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     6, 'A09-06', 262.0,  253.0,   50, 34,  null, 'Stool group row 2'),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     7, 'A09-07', 317.0,  253.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     8, 'A09-08', 372.0,  253.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',     9, 'A09-09', 427.0,  253.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',    10, 'A09-10', 482.0,  253.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',    11, 'A09-11', 262.0,  291.0,   50, 34,  null, 'Stool group row 3'),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',    12, 'A09-12', 317.0,  291.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',    13, 'A09-13', 372.0,  291.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',    14, 'A09-14', 427.0,  291.0,   50, 34,  null, null),
    ('NODE_A09_OUTDOOR_BLOCK_JOINING_YARD',    15, 'A09-15', 482.0,  291.0,   50, 34,  null, null),
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL',      1, 'A10-01', 295.0,  355.0,   46, 36,  null, 'Blasting cell 1'),
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL',      2, 'A10-02', 345.0,  355.0,   46, 36,  null, 'Blasting cell 2'),
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL',      3, 'A10-03', 395.0,  355.0,   46, 36,  null, 'Blasting cell 3'),
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL',      4, 'A10-04', 295.0,  395.0,   46, 36,  null, 'Paint cell 1'),
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL',      5, 'A10-05', 345.0,  395.0,   46, 36,  null, 'Paint cell 2'),
    ('NODE_A10_BLOCK_BLASTING_PAINT_HALL',      6, 'A10-06', 395.0,  395.0,   46, 36,  null, 'Paint cell 3')
) as x(node, slot_no, code, cx, cy, sx, sy, max_t, notes)
join public.components c on c.project_id = p.id and c.mesh_node_id = x.node
where p.id = '33333333-3333-3333-3333-333333333333'
on conflict (component_id, slot_no) do nothing;
