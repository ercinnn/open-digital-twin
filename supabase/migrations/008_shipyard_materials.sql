-- =============================================================================
-- Open Digital Twin Platform - 008 Material stock & traceability
--
--   * public.material_items         stock per item (plates, profiles, pipes, equipment,
--                                   consumables) stored at a yard area component
--   * public.material_trace_events  history of a physical piece identified by a tag
--                                   (QR code / RFID / hard-stamped heat number):
--                                   received -> blasted -> cut -> assembled -> installed
-- Tags are free text so barcode scanners in keyboard-wedge mode, RFID gateways or
-- manual entry all work the same way.
-- =============================================================================

create table if not exists public.material_items (
    id                      uuid primary key default gen_random_uuid(),
    project_id              uuid not null references public.projects (id) on delete cascade,
    item_code               text not null,
    description             text not null,
    material_type           text not null
                            check (material_type in ('plate', 'profile', 'pipe', 'equipment', 'outfitting', 'consumable', 'paint')),
    grade                   text,
    dimensions              text,
    unit                    text not null default 't' check (unit in ('t', 'kg', 'pcs', 'm', 'l', 'set')),
    quantity_on_hand        numeric not null default 0 check (quantity_on_hand >= 0),
    quantity_reserved       numeric not null default 0 check (quantity_reserved >= 0),
    reorder_level           numeric not null default 0 check (reorder_level >= 0),
    location_component_id   uuid references public.components (id) on delete set null,
    hull_id                 uuid references public.hulls (id) on delete set null,
    heat_number             text,
    certificate_no          text,
    supplier                text,
    updated_at              timestamptz not null default now(),
    unique (project_id, item_code)
);

comment on column public.material_items.hull_id is 'Hull the stock is reserved / purchased for (null = general stock).';

create index if not exists material_items_project_idx on public.material_items (project_id, material_type);

drop trigger if exists material_items_set_updated_at on public.material_items;
create trigger material_items_set_updated_at
    before update on public.material_items
    for each row execute function public.set_updated_at();

create table if not exists public.material_trace_events (
    id              uuid primary key default gen_random_uuid(),
    project_id      uuid not null references public.projects (id) on delete cascade,
    item_id         uuid references public.material_items (id) on delete set null,
    tag_code        text not null check (length(trim(tag_code)) > 0),
    event_type      text not null
                    check (event_type in ('received', 'inspected', 'blasted', 'cut', 'bent', 'assembled',
                                          'installed', 'issued', 'returned', 'scrapped')),
    component_id    uuid references public.components (id) on delete set null,
    quantity        numeric,
    recorded_at     timestamptz not null default now(),
    recorded_by     uuid default auth.uid(),
    notes           text
);

comment on column public.material_trace_events.component_id is 'Where it happened: yard area, or the block the piece was built into.';

create index if not exists material_trace_events_tag_idx on public.material_trace_events (project_id, upper(tag_code), recorded_at);
create index if not exists material_trace_events_item_idx on public.material_trace_events (item_id, recorded_at desc);

select public._odt_secure_table('material_items', false);
select public._odt_secure_table('material_trace_events', false);
