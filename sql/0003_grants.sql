-- ═══════════════════════════════════════════════════════════════
-- 표를 쓸 수 있게 권한을 줍니다 — 빠뜨렸던 것
--
-- 이 프로젝트는 Supabase 의 기본 권한에 기대지 않습니다.
-- 0001_init(Re:Call) 과 0003_works(Re:Bind) 를 보면 표마다
-- authenticated 와 service_role 에게 일일이 권한을 주고 있습니다.
-- 0001_restore.sql 에 이걸 빠뜨려서, 표는 있는데 아무도 못 읽었습니다.
--   · 문지기(store-gate, service_role) → 점포를 못 찾아 "없는 주소입니다"
--   · 본사 화면(authenticated)        → 목록이 통째로 비어 보임
--
-- 행 단위 규칙(RLS)은 이것과 별개입니다. 권한은 바깥문, RLS 는 안쪽문입니다.
-- 바깥문이 잠겨 있으면 안쪽 규칙을 볼 기회조차 없습니다.
--
-- 여러 번 실행해도 안전합니다.
-- ═══════════════════════════════════════════════════════════════

-- 로그인한 사람 — 어느 줄이 보이는지는 RLS 가 정합니다
grant select, insert, update, delete on public.stores       to authenticated;
grant select, insert, update, delete on public.supply_items to authenticated;
grant select, insert, update, delete on public.orders       to authenticated;
grant select, insert, update, delete on public.order_lines  to authenticated;

-- 서버 함수(store-gate) — RLS 를 지나지 않으므로 문지기 코드가 스스로 가립니다
grant all privileges on public.stores       to service_role;
grant all privileges on public.supply_items to service_role;
grant all privileges on public.orders       to service_role;
grant all privileges on public.order_lines  to service_role;

-- ───────────────── 확인 ─────────────────
select table_name as 표,
       string_agg(distinct grantee, ', ' order by grantee) as "권한 받은 쪽"
  from information_schema.role_table_grants
 where table_schema='public'
   and table_name in ('stores','supply_items','orders','order_lines')
   and grantee in ('authenticated','service_role','anon')
 group by table_name
 order by table_name;
