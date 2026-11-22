-- =============================================================================
-- Open Digital Twin Platform - 018 Materials, inspections and permits of the
-- afloat outfitting work packages
--
--   * material_reservations.activity_id  schedule row the material is for (an
--     afloat outfitting work package). The reservation's component is then the
--     row's yard area (outfitting quay), the hull follows the row. One open
--     reservation per item, component and row (blocks: per item and block, as
--     before).
--   * A work package row cannot be reported finished (actual_end) while one of
--     its material reservations is still `reserved`: the material is issued
--     before the package is done.
--   * A `lifting` permit of an afloat outfitting row can only become `active`
--     while a quay crane lift of that row overlaps the permit window (as for
--     block erection, 015).
--   * Demo shipyard (project 3, when present): outfitting stock items in the
--     general warehouse (cables, valves, insulation, top coat, gratings).
-- ITP points of the packages are planned by the app (Quality "Plan"); the
-- hold points block the package rows like every other row (013).
-- =============================================================================

alter table public.material_reservations
    add column if not exists activity_id uuid references public.production_activities (id) on delete set null;

comment on column public.material_reservations.activity_id is
    'Schedule row the material is for (afloat outfitting work package); null = the block of component_id.';
comment on column public.material_reservations.component_id is
    'Block (NODE_<HULL>_BLOCK_*) the material is for, or the yard area of the work package row (activity_id).';

create index if not exists material_reservations_activity_idx
    on public.material_reservations (activity_id) where activity_id is not null;

drop index if exists public.material_reservations_open_uniq;
create unique index if not exists material_reservations_open_uniq
    on public.material_reservations (item_id, component_id, coalesce(activity_id, '00000000-0000-0000-0000-000000000000'::uuid))
    where status = 'reserved';

-- -----------------------------------------------------------------------------
-- Reservation rules (012) + the work package row
-- -----------------------------------------------------------------------------
create or replace function public._check_material_reservation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_item record;
    v_component record;
    v_row record;
    v_target text;
begin
    select i.project_id, i.item_code, i.unit, i.quantity_on_hand, i.heat_number
      into v_item
      from public.material_items i
     where i.id = new.item_id;
    select c.project_id, c.name, c.metadata
      into v_component
      from public.components c
     where c.id = new.component_id;

    if v_item.project_id is distinct from new.project_id
       or v_component.project_id is distinct from new.project_id then
        raise exception 'Stock item and block must belong to this project'
            using errcode = 'check_violation';
    end if;
    v_target := v_component.name;

    if new.activity_id is not null then
        select a.project_id, a.hull_id, a.component_id, a.name
          into v_row
          from public.production_activities a
         where a.id = new.activity_id;
        if v_row.project_id is distinct from new.project_id then
            raise exception 'The schedule row of the reservation does not belong to this project'
                using errcode = 'check_violation';
        end if;
        if v_row.component_id is not null and v_row.component_id <> new.component_id then
            raise exception 'Reservation of %: % is the work of another block', v_item.item_code, v_row.name
                using errcode = 'check_violation';
        end if;
        v_target := v_row.name;
        if new.hull_id is null then
            new.hull_id := v_row.hull_id;
        end if;
    end if;

    -- The hull follows the block (metadata.hull_no) unless given.
    if new.hull_id is null and v_component.metadata ->> 'hull_no' is not null then
        select h.id into new.hull_id
          from public.hulls h
         where h.project_id = new.project_id and h.hull_no = v_component.metadata ->> 'hull_no';
    end if;

    if tg_op = 'UPDATE' and old.status = 'issued' then
        if new.status <> 'issued' then
            raise exception 'Reservation of % for % is already issued and cannot be reopened', v_item.item_code, v_target
                using errcode = 'check_violation';
        end if;
        if new.quantity <> old.quantity or new.item_id <> old.item_id or new.component_id <> old.component_id
           or new.activity_id is distinct from old.activity_id then
            raise exception 'Reservation of % for % is already issued: item, target and quantity are fixed', v_item.item_code, v_target
                using errcode = 'check_violation';
        end if;
        return new;
    end if;

    if new.status = 'issued' then
        if v_item.quantity_on_hand < new.quantity then
            raise exception 'Only % % of % on hand - receive stock before issuing % % for %',
                v_item.quantity_on_hand, v_item.unit, v_item.item_code, new.quantity, v_item.unit, v_target
                using errcode = 'check_violation';
        end if;
        new.issued_at := coalesce(new.issued_at, now());
        update public.material_items
           set quantity_on_hand = quantity_on_hand - new.quantity
         where id = new.item_id;
        insert into public.material_trace_events (project_id, item_id, tag_code, event_type, component_id, quantity, notes)
        values (new.project_id, new.item_id, coalesce(v_item.heat_number, v_item.item_code), 'issued',
                new.component_id, new.quantity, 'Issued for ' || v_target);
    else
        new.issued_at := null;
    end if;
    return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Work package rows: material issued before the package is finished
-- -----------------------------------------------------------------------------
create or replace function public._check_package_materials()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_open  integer;
    v_codes text;
begin
    if new.work_package is null or new.actual_end is null
       or (tg_op = 'UPDATE' and old.actual_end is not null) then
        return new;
    end if;
    select count(*), string_agg(i.item_code, ', ' order by i.item_code)
      into v_open, v_codes
      from public.material_reservations r
      join public.material_items i on i.id = r.item_id
     where r.activity_id = new.id
       and r.status = 'reserved';
    if v_open > 0 then
        raise exception '% cannot be finished - % material reservation(s) not issued yet: %',
            new.activity_code, v_open, v_codes
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

drop trigger if exists production_activities_package_materials on public.production_activities;
create trigger production_activities_package_materials
    before insert or update of actual_end on public.production_activities
    for each row execute function public._check_package_materials();

-- -----------------------------------------------------------------------------
-- Permits on schedule rows (015): lifting needs a booked lift also at the quay
-- -----------------------------------------------------------------------------
create or replace function public._check_work_permit_link()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_row record;
    v_hull_no text;
begin
    if new.hull_id is null then
        select c.metadata ->> 'hull_no' into v_hull_no from public.components c where c.id = new.component_id;
        if v_hull_no is not null then
            select h.id into new.hull_id
              from public.hulls h
             where h.project_id = new.project_id and h.hull_no = v_hull_no;
        end if;
    end if;

    if new.activity_id is null then
        return new;
    end if;

    select a.project_id, a.component_id, a.hull_id, a.stage, a.name
      into v_row
      from public.production_activities a
     where a.id = new.activity_id;
    if v_row.project_id is distinct from new.project_id then
        raise exception 'Permit %: the schedule row does not belong to this project', new.permit_no
            using errcode = 'check_violation';
    end if;
    if v_row.component_id is not null and v_row.component_id <> new.component_id then
        raise exception 'Permit %: % is the work of another block', new.permit_no, v_row.name
            using errcode = 'check_violation';
    end if;
    -- Hull-level rows (work packages): the hull follows the row.
    if new.hull_id is null then
        new.hull_id := v_row.hull_id;
    end if;

    if new.status = 'active'
       and (tg_op = 'INSERT' or old.status is distinct from 'active')
       and new.permit_type = 'lifting'
       and v_row.stage in ('erection', 'outfitting')
       and not exists (
            select 1
              from public.resource_bookings b
             where b.activity_id = new.activity_id
               and b.status in ('planned', 'confirmed', 'in_progress')
               and b.starts_at < new.valid_to
               and b.ends_at > new.valid_from) then
        raise exception 'Permit %: no crane lift is booked for % inside the permit window - book the lift first (Resources)',
            new.permit_no, v_row.name
            using errcode = 'check_violation';
    end if;
    return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Demo shipyard: outfitting stock in the general warehouse
-- -----------------------------------------------------------------------------
insert into public.material_items
    (project_id, item_code, description, material_type, grade, dimensions, unit, quantity_on_hand, quantity_reserved,
     reorder_level, location_component_id, certificate_no, supplier)
select p.id, x.code, x.descr, x.mtype, x.grade, x.dims, x.unit, x.on_hand, 0, x.reorder, c.id, x.cert, x.supplier
from public.projects p
cross join (values
    ('CABLE-PWR-3X95',  'Power cable 3 x 95 mm2 (halogen-free)',  'equipment',  'IEC 60092-353', 'drums of 500 m',  'm',   6000, 2500, 'NODE_A02_GENERAL_WAREHOUSE', 'TA-2026-CAB-02',  'Demo Cable Works'),
    ('CABLE-SIG-4X1.5', 'Signal cable 4 x 1.5 mm2 (screened)',    'equipment',  'IEC 60092-376', 'drums of 1000 m', 'm',  18000, 8000, 'NODE_A02_GENERAL_WAREHOUSE', 'TA-2026-CAB-05',  'Demo Cable Works'),
    ('VALVE-BF-DN150',  'Butterfly valve DN150 PN16',             'equipment',  'GGG40',         'DN150',           'pcs',   60,   20, 'NODE_A02_GENERAL_WAREHOUSE', 'EN10204-3.1-V-212', 'Demo Valve Co'),
    ('INSUL-MW-A60',    'Mineral wool A-60 slabs 50 mm',          'outfitting', 'A-60',          '1200 x 600 x 50 mm', 'pcs', 2400, 1000, 'NODE_A02_GENERAL_WAREHOUSE', 'MED-B-2026-0411', 'Demo Insulation'),
    ('PAINT-PU-TOP',    'Polyurethane top coat (topsides, deck)', 'paint',      'PU',            '20 l kits',       'l',   1400,  800, 'NODE_A02_GENERAL_WAREHOUSE', 'TA-2026-COAT-12', 'Demo Coatings'),
    ('OUT-GRATING-STD', 'Steel gratings (galvanized, 1 x 1 m)',   'outfitting', 'S235',          '1000 x 1000 mm',  'pcs',  300,  100, 'NODE_A15_OUTFITTING_LIGHT_STEEL_SHOP', null, 'In-house')
) as x(code, descr, mtype, grade, dims, unit, on_hand, reorder, location, cert, supplier)
left join public.components c on c.project_id = p.id and c.mesh_node_id = x.location
where p.id = '33333333-3333-3333-3333-333333333333'
on conflict (project_id, item_code) do nothing;
