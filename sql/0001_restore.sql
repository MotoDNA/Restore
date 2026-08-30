-- ═══════════════════════════════════════════════════════════════
-- Re:Store — 가맹점 발주 · 출고 · 월정산
--
-- Re:Call(고객관리) · Re:Bind(제조공정)와 같은 데이터베이스, 같은 계정입니다.
-- 회사 격리·담당자 규칙은 0001_init 에서 만든 도우미 함수를 그대로 씁니다.
--   current_company_id()  지금 로그인한 사람의 회사
--   is_admin()            관리자인가
--   company_for_app(app)  그 서비스를 산 회사인가 (0019_apps)
--   touch_updated_at()    수정시각 자동 갱신
--
-- 설계 원칙 (앞의 두 앱과 같습니다)
--   1) 회사 격리는 앱이 아니라 데이터베이스가 강제합니다.
--   2) 지운 것은 표시만 합니다.
--   3) 가맹점(점주)은 계정이 없습니다. 이 표를 직접 열지 않습니다.
--      로그인하지 않은 사람에게는 어떤 권한도 주지 않고,
--      서버 함수(store-gate)가 링크의 열쇠와 핀을 확인한 뒤 대신 읽고 씁니다.
--
-- 이 앱만의 원칙이 하나 더 있습니다
--   4) 발주서에 적힌 품목명·규격·단가는 그때 그 값을 박아 둡니다.
--      품목표(supply_items)를 가리키기만 하면, 나중에 본사가 단가를 올렸을 때
--      지난달 발주서와 이미 끊어 준 정산서의 금액이 소리 없이 바뀝니다.
--      종이로 나간 숫자가 나중에 달라지는 것은 사고입니다.
-- ═══════════════════════════════════════════════════════════════

-- ───────────────── 가맹점 (점포) ─────────────────
create table public.stores (
  id           uuid primary key default gen_random_uuid(),
  company_id   uuid not null references public.companies(id) on delete restrict,  -- 가맹본부
  owner_id     uuid not null references public.profiles(id) on delete restrict,   -- 담당 슈퍼바이저
  shared_ids   uuid[] not null default '{}',

  code         text not null default '',   -- 점포코드 (본사 사내 번호)
  name         text not null default '',   -- 점포명  예) 강남역점
  boss         text not null default '',   -- 점주 이름
  phone        text not null default '',
  phone_digits text generated always as (regexp_replace(coalesce(phone,''), '[^0-9]', '', 'g')) stored,
  addr         text not null default '',

  -- 정산서 '공급받는자' 칸에 그대로 들어갑니다. 점포명과 사업자 상호가
  -- 다른 곳이 많습니다 (간판은 강남역점, 사업자는 (주)○○).
  biz_no       text not null default '',
  biz_name     text not null default '',
  biz_ceo      text not null default '',
  biz_type     text not null default '',   -- 업태
  biz_item     text not null default '',   -- 종목

  opened_on    date,
  status       text not null default 'open',    -- open 영업 · pause 휴업 · closed 폐점
  pay_term     text not null default 'month',   -- month 월정산 · each 건별정산

  -- 점주가 쓰는 링크
  share_token  text unique,
  share_on     boolean not null default true,
  pin          text not null default '',        -- 숫자 4자리. 링크만으로는 못 들어옵니다

  memo         text not null default '',        -- 내부 메모 (점주에게 안 보입니다)

  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),
  deleted      boolean not null default false,

  constraint stores_named     check (length(name) > 0),
  constraint stores_status    check (status in ('open','pause','closed')),
  constraint stores_payterm   check (pay_term in ('month','each')),
  constraint stores_pin_fmt   check (pin = '' or pin ~ '^[0-9]{4,8}$'),
  constraint stores_token_fmt check (share_token is null or share_token ~ '^[a-f0-9]{32,64}$')
);
create index stores_company_idx on public.stores(company_id) where not deleted;
create index stores_owner_idx   on public.stores(company_id, owner_id) where not deleted;
create index stores_shared_idx  on public.stores using gin (shared_ids);
create index stores_updated_idx on public.stores(company_id, updated_at);
create index stores_token_idx   on public.stores(share_token) where share_on and not deleted;
create unique index stores_code_uniq on public.stores(company_id, code) where not deleted and code <> '';

-- ───────────────── 본사가 파는 품목 ─────────────────
create table public.supply_items (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete restrict,

  code        text not null default '',      -- 품목코드
  name        text not null default '',
  spec        text not null default '',      -- 규격 · 용량
  unit        text not null default 'EA',
  category    text not null default '',      -- 분류 (식자재 · 포장재 · 비품 …)

  price       numeric(14,2) not null default 0,   -- 본사 공급가 (부가세 별도)
  taxfree     boolean not null default false,     -- 면세 품목인가 (농축수산물 등)

  moq         integer not null default 0,    -- 최소 발주 수량. 0 이면 제한 없음
  box_qty     integer,                       -- 한 박스에 몇 개. 비우면 낱개
  active      boolean not null default true, -- 끄면 점주 화면의 발주 목록에서 사라집니다
  sort        integer not null default 0,

  photo_path  text,
  memo        text not null default '',

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted     boolean not null default false,

  constraint items_named check (length(name) > 0),
  constraint items_price check (price >= 0),
  constraint items_moq   check (moq >= 0)
);
create index items_company_idx  on public.supply_items(company_id) where not deleted;
create index items_active_idx   on public.supply_items(company_id, sort) where active and not deleted;
create index items_updated_idx  on public.supply_items(company_id, updated_at);
create unique index items_code_uniq on public.supply_items(company_id, code) where not deleted and code <> '';

-- ───────────────── 발주서 한 장 ─────────────────
create table public.orders (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete restrict,
  store_id    uuid not null references public.stores(id) on delete restrict,

  no          text not null default '',        -- 발주번호  예) 20260830-003
  ordered_at  timestamptz not null default now(),
  want_on     date,                            -- 점주가 받고 싶은 날

  -- 접수 → 확정 → 출고 → 완료. 취소는 어디서든.
  status      text not null default 'placed',
  confirmed_on date,
  shipped_on   date,
  done_on      date,

  courier     text not null default '',        -- 택배사 · 배송 방법
  invoice_no  text not null default '',        -- 송장번호
  ship_memo   text not null default '',

  memo        text not null default '',        -- 점주가 적은 요청사항 (양쪽 다 봅니다)
  memo_hq     text not null default '',        -- 본사 내부 메모 (점주에게 안 보입니다)

  vat_rate    numeric(5,2) not null default 10,
  by_store    boolean not null default true,   -- 점주가 넣었나, 본사가 대신 넣었나

  -- 정산을 끊은 달. 채워지면 이 발주서는 잠깁니다.
  -- 정산서를 이미 보냈는데 뒤에서 수량이 바뀌면 종이와 숫자가 어긋납니다.
  billed_ym   text,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  deleted     boolean not null default false,

  constraint orders_status check (status in ('placed','confirmed','shipped','done','canceled')),
  constraint orders_ym_fmt check (billed_ym is null or billed_ym ~ '^[0-9]{4}-[0-9]{2}$')
);
create index orders_company_idx on public.orders(company_id) where not deleted;
create index orders_store_idx   on public.orders(store_id, ordered_at desc) where not deleted;
create index orders_updated_idx on public.orders(company_id, updated_at);
create index orders_open_idx    on public.orders(company_id, ordered_at)
  where not deleted and status in ('placed','confirmed');
create index orders_bill_idx    on public.orders(company_id, store_id, billed_ym) where not deleted;

-- ───────────────── 발주 줄 ─────────────────
-- 품목표를 가리키되(item_id), 이름·규격·단가는 그때 값을 박아 둡니다.
-- 위 원칙 4) 를 보세요.
create table public.order_lines (
  id          uuid primary key default gen_random_uuid(),
  company_id  uuid not null references public.companies(id) on delete restrict,
  order_id    uuid not null references public.orders(id) on delete cascade,
  item_id     uuid references public.supply_items(id) on delete set null,

  name        text not null default '',
  spec        text not null default '',
  unit        text not null default 'EA',
  price       numeric(14,2) not null default 0,
  taxfree     boolean not null default false,

  qty         integer not null default 0,   -- 점주가 주문한 수량
  ship_qty    integer,                      -- 실제로 나간 수량. 비어 있으면 아직 안 정함
  note        text not null default '',
  sort        integer not null default 0,

  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),

  constraint lines_qty  check (qty >= 0),
  constraint lines_ship check (ship_qty is null or ship_qty >= 0)
);
create index lines_order_idx   on public.order_lines(order_id, sort);
create index lines_company_idx on public.order_lines(company_id, updated_at);

-- ───────────────── 수정시각 자동 갱신 ─────────────────
create trigger stores_touch  before update on public.stores
  for each row execute function public.touch_updated_at();
create trigger items_touch   before update on public.supply_items
  for each row execute function public.touch_updated_at();
create trigger orders_touch  before update on public.orders
  for each row execute function public.touch_updated_at();
create trigger lines_touch   before update on public.order_lines
  for each row execute function public.touch_updated_at();

-- ═══════════════════════════════════════════════════════════════
-- 행 단위 접근 제어
-- 기본은 "아무것도 안 보임" 입니다.
-- 모든 규칙이 company_for_app('restore') 를 지납니다.
-- 그 서비스를 안 산 회사는 null 이 돌아오고, null 과의 비교는
-- 참이 되지 않으므로 표가 통째로 닫힙니다.
-- ═══════════════════════════════════════════════════════════════
alter table public.stores        enable row level security;
alter table public.supply_items  enable row level security;
alter table public.orders        enable row level security;
alter table public.order_lines   enable row level security;

alter table public.stores        force row level security;
alter table public.supply_items  force row level security;
alter table public.orders        force row level security;
alter table public.order_lines   force row level security;

-- ── 가맹점: 같은 회사 + (관리자거나 · 담당이거나 · 공유받았거나) ──
create policy stores_read on public.stores
  for select to authenticated
  using (
    company_id = public.company_for_app('restore')
    and (public.is_admin() or owner_id = auth.uid() or auth.uid() = any(shared_ids))
  );

create policy stores_insert on public.stores
  for insert to authenticated
  with check (
    company_id = public.company_for_app('restore')
    and (
      owner_id = auth.uid()
      or (public.is_admin() and exists (
            select 1 from public.profiles p
             where p.id = stores.owner_id and p.company_id = public.current_company_id()))
    )
  );

create policy stores_update on public.stores
  for update to authenticated
  using (
    company_id = public.company_for_app('restore')
    and (public.is_admin() or owner_id = auth.uid() or auth.uid() = any(shared_ids))
  )
  with check (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.profiles p
                 where p.id = stores.owner_id and p.company_id = public.current_company_id())
  );

create policy stores_delete on public.stores
  for delete to authenticated
  using (company_id = public.company_for_app('restore') and public.is_admin());

-- ── 품목표: 회사 사람이면 봅니다. 고치는 것은 관리자만. ──
-- 단가가 여기 있습니다. 아무나 고치면 그날 들어온 발주가 다 틀어집니다.
create policy items_read on public.supply_items
  for select to authenticated
  using (company_id = public.company_for_app('restore'));

create policy items_insert on public.supply_items
  for insert to authenticated
  with check (company_id = public.company_for_app('restore') and public.is_admin());

create policy items_update on public.supply_items
  for update to authenticated
  using  (company_id = public.company_for_app('restore') and public.is_admin())
  with check (company_id = public.company_for_app('restore'));

create policy items_delete on public.supply_items
  for delete to authenticated
  using (company_id = public.company_for_app('restore') and public.is_admin());

-- ── 발주서: 그 가맹점이 보이면 발주서도 보입니다 ──
create policy orders_read on public.orders
  for select to authenticated
  using (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.stores s where s.id = orders.store_id)
  );

create policy orders_insert on public.orders
  for insert to authenticated
  with check (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.stores s
                 where s.id = orders.store_id and s.company_id = public.current_company_id())
  );

-- 정산을 끊은 발주서(billed_ym 이 찬 것)는 관리자만 건드립니다.
create policy orders_update on public.orders
  for update to authenticated
  using (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.stores s where s.id = orders.store_id)
    and (billed_ym is null or public.is_admin())
  )
  with check (company_id = public.company_for_app('restore'));

create policy orders_delete on public.orders
  for delete to authenticated
  using (company_id = public.company_for_app('restore') and public.is_admin());

-- ── 발주 줄: 그 발주서가 보이면 줄도 보입니다 ──
create policy lines_read on public.order_lines
  for select to authenticated
  using (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.orders o where o.id = order_lines.order_id)
  );

create policy lines_insert on public.order_lines
  for insert to authenticated
  with check (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.orders o
                 where o.id = order_lines.order_id
                   and o.company_id = public.current_company_id()
                   and (o.billed_ym is null or public.is_admin()))
  );

create policy lines_update on public.order_lines
  for update to authenticated
  using (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.orders o
                 where o.id = order_lines.order_id
                   and (o.billed_ym is null or public.is_admin()))
  )
  with check (company_id = public.company_for_app('restore'));

create policy lines_delete on public.order_lines
  for delete to authenticated
  using (
    company_id = public.company_for_app('restore')
    and exists (select 1 from public.orders o
                 where o.id = order_lines.order_id
                   and (o.billed_ym is null or public.is_admin()))
  );

-- ═══════════════════════════════════════════════════════════════
-- 표를 쓸 수 있게 권한을 줍니다
--
-- ⚠ 빠뜨리기 쉽고, 빠뜨리면 증상이 엉뚱합니다 — 표도 있고 규칙도 맞는데
--   목록이 텅 비고 점주 링크는 "없는 주소입니다" 가 됩니다. 실제로 겪었습니다.
--   이 프로젝트는 Supabase 기본 권한에 기대지 않습니다. Re:Call·Re:Bind 의
--   표에도 모두 이렇게 일일이 붙어 있습니다.
--
--   권한은 바깥문, RLS 는 안쪽문입니다. 바깥문이 잠겨 있으면
--   안쪽 규칙을 볼 기회조차 없습니다.
-- ═══════════════════════════════════════════════════════════════
grant select, insert, update, delete on public.stores       to authenticated;
grant select, insert, update, delete on public.supply_items to authenticated;
grant select, insert, update, delete on public.orders       to authenticated;
grant select, insert, update, delete on public.order_lines  to authenticated;

grant all privileges on public.stores       to service_role;
grant all privileges on public.supply_items to service_role;
grant all privileges on public.orders       to service_role;
grant all privileges on public.order_lines  to service_role;

-- ═══════════════════════════════════════════════════════════════
-- 품목 사진 보관함
-- 경로가 {회사id}/{품목id}/… 라서 폴더 이름이 곧 권한입니다.
-- Re:Bind 의 works 보관함과 같은 방식입니다.
-- ═══════════════════════════════════════════════════════════════
insert into storage.buckets (id, name, public)
values ('supply', 'supply', false)
on conflict (id) do nothing;

create policy supply_read on storage.objects
  for select to authenticated
  using (
    bucket_id = 'supply'
    and (storage.foldername(name))[1] = public.company_for_app('restore')::text
  );

create policy supply_insert on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'supply'
    and (storage.foldername(name))[1] = public.company_for_app('restore')::text
  );

create policy supply_update on storage.objects
  for update to authenticated
  using (
    bucket_id = 'supply'
    and (storage.foldername(name))[1] = public.company_for_app('restore')::text
  );

create policy supply_delete on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'supply'
    and (storage.foldername(name))[1] = public.company_for_app('restore')::text
  );

-- ═══════════════════════════════════════════════════════════════
-- 화면이 저절로 새로 고쳐지도록 (실시간)
-- ═══════════════════════════════════════════════════════════════
alter publication supabase_realtime add table public.stores;
alter publication supabase_realtime add table public.supply_items;
alter publication supabase_realtime add table public.orders;
alter publication supabase_realtime add table public.order_lines;

-- ═══════════════════════════════════════════════════════════════
-- ⚠ 마지막 한 줄 — 이걸 안 하면 아무도 못 들어갑니다
--
-- 회사에 'restore' 를 사 준 표시를 해야 위 규칙들이 열립니다.
-- 0019_apps 의 원칙대로 기본값은 비어 있습니다.
-- 쓸 회사의 코드로 바꿔서 실행하세요.
-- ═══════════════════════════════════════════════════════════════
-- update public.companies
--    set apps = array(select distinct unnest(apps || '{restore}'))
--  where code = 'ACTIVA';
