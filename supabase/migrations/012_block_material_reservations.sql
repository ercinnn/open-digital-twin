-- =============================================================================
-- Open Digital Twin Platform - 012 Material reservations per hull block
--
--   * public.material_reservations  stock reserved for a block (or another component)
--                                   of a hull: item, quantity, needed-by date.
--                                   status reserved -> issued (material handed out
--                                   to the shop; stock on hand goes down, a trace
--                                   event `issued` records the block).
--   * material_items.quantity_block_reserved  sum of the open (`reserved`) block
--                                   reservations of an item, always recalculated
--                                   by the database. quantity_reserved stays the
--                                   manual reservation outside the blocks.
--                                   Free stock = on hand - reserved - block reserved
--                                   (negative = shortage to order; allowed).
-- =============================================================================

alter table public.material_items
    add column if not exists quantity_block_reserved numeric not null default 0
        check (quantity_block_reserved >= 0);

comment on column public.material_items.quantity_reserved is
    'Manual reservation (not tied to a block). Block reservations: quantity_block_reserved.';
comment on column public.material_items.quantity_block_reserved is
    'Sum of open material_reservations of the item (maintained by the database).';

create table if not exists public.material_reservations (
    id              uuid primary key default gen_random_uuid(),
    project_id      uuid not null references public.projects (id) on delete cascade,
    item_id         uuid not null references public.material_items (id) on delete cascade,
    component_id    uuid not null references public.components (id) on delete cascade,
    hull_id         uuid references public.hulls (id) on delete set null,
    quantity        numeric not null check (quantity > 0),
    needed_by       date,
    status          text not null default 'reserved' check (status in ('reserved', 'issued')),
    issued_at       timestamptz,
    notes           text,
    created_at      timestamptz not null default now(),
    updated_at      timestamptz not null default now()
);

comment on column public.material_reservations.component_id is 'Block (NODE_<HULL>_BLOCK_*) the material is for.';
comment on column public.material_reservations.needed_by is 'Start of the first shop stage of the block (cutting).';

create index if not exists material_reservations_project_idx on public.material_reservations (project_id, status);
create index if not exists material_reservations_item_idx on public.material_reservations (item_id) where status = 'reserved';
create index if not exists material_reservations_component_idx on public.material_reservations (component_id);
-- One open reservation per item and block (raise its quantity instead of adding a second one).
create unique index if not exists material_reservations_open_uniq
    on public.material_reservations (item_id, component_id) where status = 'reserved';

drop trigger if exists material_reservations_set_updated_at on public.material_reservations;
create trigger material_reservations_set_updated_at
    before update on public.material_reservations
    for each row execute function public.set_updated_at();

-- -----------------------------------------------------------------------------
-- material_items: block reservations are always the sum of the open reservations
-- -----------------------------------------------------------------------------
create or replace function public._material_item_block_reserved()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.quantity_block_reserved := coalesce(
        (select sum(r.quantity)
           from public.material_reservations r
          where r.item_id = new.id and r.status = 'reserved'),
        0);
    return new;
end;
$$;

drop trigger if exists material_items_block_reserved on public.material_items;
create trigger material_items_block_reserved
    before insert or update on public.material_items
    for each row execute function public._material_item_block_reserved();

-- -----------------------------------------------------------------------------
-- Reservation rules: same project, hull from the block, issue = stock goes out
-- -----------------------------------------------------------------------------
create or replace function public._check_material_reservation()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    v_item record;
    v_component record;
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

    -- The hull follows the block (metadata.hull_no) unless given.
    if new.hull_id is null and v_component.metadata ->> 'hull_no' is not null then
        select h.id into new.hull_id
          from public.hulls h
         where h.project_id = new.project_id and h.hull_no = v_component.metadata ->> 'hull_no';
    end if;

    if tg_op = 'UPDATE' and old.status = 'issued' then
        if new.status <> 'issued' then
            raise exception 'Reservation of % for % is already issued and cannot be reopened', v_item.item_code, v_component.name
                using errcode = 'check_violation';
        end if;
        if new.quantity <> old.quantity or new.item_id <> old.item_id or new.component_id <> old.component_id then
            raise exception 'Reservation of % for % is already issued: item, block and quantity are fixed', v_item.item_code, v_component.name
                using errcode = 'check_violation';
        end if;
        return new;
    end if;

    if new.status = 'issued' then
        if v_item.quantity_on_hand < new.quantity then
            raise exception 'Only % % of % on hand - receive stock before issuing % % for %',
                v_item.quantity_on_hand, v_item.unit, v_item.item_code, new.quantity, v_item.unit, v_component.name
                using errcode = 'check_violation';
        end if;
        new.issued_at := coalesce(new.issued_at, now());
        update public.material_items
           set quantity_on_hand = quantity_on_hand - new.quantity
         where id = new.item_id;
        insert into public.material_trace_events (project_id, item_id, tag_code, event_type, component_id, quantity, notes)
        values (new.project_id, new.item_id, coalesce(v_item.heat_number, v_item.item_code), 'issued',
                new.component_id, new.quantity, 'Issued for ' || v_component.name);
    else
        new.issued_at := null;
    end if;
    return new;
end;
$$;

drop trigger if exists material_reservations_check on public.material_reservations;
create trigger material_reservations_check
    before insert or update on public.material_reservations
    for each row execute function public._check_material_reservation();

-- After any change: recalculate quantity_block_reserved of the affected items.
create or replace function public._material_reservation_totals()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    update public.material_items
       set quantity_block_reserved = 0   -- value is recalculated by material_items_block_reserved
     where id in (
        select x from unnest(array[
            case when tg_op <> 'INSERT' then old.item_id end,
            case when tg_op <> 'DELETE' then new.item_id end]) as x
        where x is not null);
    return null;
end;
$$;

drop trigger if exists material_reservations_totals on public.material_reservations;
create trigger material_reservations_totals
    after insert or update or delete on public.material_reservations
    for each row execute function public._material_reservation_totals();

select public._odt_secure_table('material_reservations', false);
