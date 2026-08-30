-- ═══════════════════════════════════════════════════════════════
-- 구도로 통닭 — 회사 만들기 + 품목 예시
--
-- ⚠ 두 가지를 먼저 정하고 실행하세요.
--   1) 회사 코드는 A-Z 와 0-9 만, 4~12 글자입니다. 여기서는 GUDORO 를 씁니다.
--   2) 아래 품목과 단가는 **제가 지어낸 예시**입니다.
--      실제 공급 품목·단가는 사장님(또는 친구분)이 받아 와서 고쳐야 합니다.
--      틀린 단가로 정산서가 나가면 사고입니다. 반드시 확인하세요.
--
-- 계정(아이디·비밀번호)은 여기서 만들지 않습니다.
-- Re:Call 의 signup / admin-user 함수가 만듭니다 — 설치방법.md 3번을 보세요.
-- ═══════════════════════════════════════════════════════════════

-- ───────────────── 1. 회사 ─────────────────
insert into public.companies (code, name, apps)
values ('GUDORO', '구도로 통닭', '{restore}')
on conflict (code) do update
   set apps = array(select distinct unnest(public.companies.apps || '{restore}'));

-- ───────────────── 2. 품목 예시 ─────────────────
-- 면세(taxfree=true) 는 생닭·채소 같은 농축수산물입니다. 부가세가 안 붙습니다.
-- 튀김가루·소스·기름·포장재는 과세입니다.
-- 이미 같은 코드의 품목이 있으면 건드리지 않습니다.
insert into public.supply_items
  (company_id, code, name, spec, unit, category, price, taxfree, moq, box_qty, sort)
select c.id, v.code, v.name, v.spec, v.unit, v.category, v.price, v.taxfree, v.moq, v.box_qty, v.sort
  from public.companies c,
       (values
         ('CK-10','생닭 10호','10마리 / 박스','박스','식자재', 32000, true,  2,  10, 0),
         ('CK-09','생닭 9호','10마리 / 박스','박스','식자재', 30000, true,  2,  10, 1),
         ('PW-01','튀김가루','20kg','포','식자재',            41000, false, 0, null, 2),
         ('PW-02','염지제','10kg','포','식자재',              28000, false, 0, null, 3),
         ('OL-01','튀김유','18L','통','식자재',               42000, false, 0, null, 4),
         ('SC-01','후라이드 시즈닝','3kg','통','소스',         11000, false, 0,    6, 5),
         ('SC-02','양념 소스','3kg','통','소스',              12500, false, 0,    6, 6),
         ('SC-03','간장 소스','3kg','통','소스',              13000, false, 0,    6, 7),
         ('MU-01','치킨무','1kg x 10','박스','식자재',         14000, false, 0,   10, 8),
         ('BX-01','치킨박스 (로고)','200매','박스','포장재',    38000, false, 1,  200, 9),
         ('BX-02','배달봉투 (로고)','500매','박스','포장재',    22000, false, 1,  500,10),
         ('ET-01','위생장갑','100매 x 20','박스','비품',       18000, false, 0,   20,11)
       ) as v(code,name,spec,unit,category,price,taxfree,moq,box_qty,sort)
 where c.code = 'GUDORO'
   and not exists (select 1 from public.supply_items i
                    where i.company_id = c.id and i.code = v.code and not i.deleted);

-- ───────────────── 3. 확인 ─────────────────
select c.code, c.name, c.apps, count(i.id) as 품목수
  from public.companies c
  left join public.supply_items i on i.company_id = c.id and not i.deleted
 where c.code = 'GUDORO'
 group by c.code, c.name, c.apps;
