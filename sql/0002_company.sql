-- ═══════════════════════════════════════════════════════════════
-- 회사에 Re:Store 를 열어 주고, 품목을 채웁니다
--
-- ⚠ 순서가 있습니다. 회사와 관리자 계정은 **이 파일보다 먼저** 만들어야 합니다.
--   Re:Call 의 setup-admin.sh (bootstrap) 가 회사와 계정을 함께 만듭니다.
--   그 함수는 **이미 있는 회사 코드를 거부**합니다. 그래서 회사를 SQL 로 먼저
--   만들어 두면 계정을 못 만들게 됩니다. 계정 먼저, 이 파일은 나중입니다.
--
-- ⚠ 아래 품목과 단가는 **지어낸 예시**입니다.
--   실제 공급 품목·단가는 받아 와서 고쳐야 합니다.
--   틀린 단가로 정산서가 나가면 사고입니다. 반드시 확인하세요.
--   ※ 실제 단가표를 이 저장소에 커밋하지 마세요. 공개 저장소입니다.
--     단가는 앱의 '품목' 탭(데이터베이스)에만 둡니다.
--
-- 쓰는 법: 아래 :code 자리의 회사 코드만 바꿔서 통째로 실행합니다.
-- ═══════════════════════════════════════════════════════════════
do $$
declare
  target_code text := '9DORO';   -- ← 여기만 바꾸세요
  cid uuid;
  n int;
begin
  select id into cid from public.companies where code = target_code;
  if cid is null then
    raise exception '% 회사가 없습니다. setup-admin.sh 로 회사와 관리자를 먼저 만드세요.', target_code;
  end if;

  -- ── 1) 이 회사가 Re:Store 를 쓸 수 있게 ──
  -- 이게 없으면 로그인은 되는데 화면이 텅 빕니다 (company_for_app 이 null 을 돌려줍니다).
  update public.companies
     set apps = array(select distinct unnest(apps || '{restore}'))
   where id = cid;

  -- ── 2) 품목 (이미 같은 코드가 있으면 건드리지 않습니다) ──
  insert into public.supply_items
    (company_id, code, name, spec, unit, category, price, taxfree, moq, box_qty, sort)
  select cid, v.code, v.name, v.spec, v.unit, v.category, v.price, v.taxfree, v.moq, v.box_qty, v.sort
    from (values
      -- 면세 = 생닭·채소 같은 농축수산물. 부가세가 안 붙습니다.
      ('CK-10','생닭 10호','10마리 / 박스','박스','식자재', 32000, true,  2,  10, 0),
      ('CK-09','생닭 9호','10마리 / 박스','박스','식자재',  30000, true,  2,  10, 1),
      -- 아래는 모두 과세
      ('PW-01','튀김가루','20kg','포','식자재',             41000, false, 0, null, 2),
      ('PW-02','염지제','10kg','포','식자재',               28000, false, 0, null, 3),
      ('OL-01','튀김유','18L','통','식자재',                42000, false, 0, null, 4),
      ('SC-01','후라이드 시즈닝','3kg','통','소스',          11000, false, 0,    6, 5),
      ('SC-02','양념 소스','3kg','통','소스',               12500, false, 0,    6, 6),
      ('SC-03','간장 소스','3kg','통','소스',               13000, false, 0,    6, 7),
      ('MU-01','치킨무','1kg x 10','박스','식자재',          14000, false, 0,   10, 8),
      ('BX-01','치킨박스 (로고)','200매','박스','포장재',     38000, false, 1,  200, 9),
      ('BX-02','배달봉투 (로고)','500매','박스','포장재',     22000, false, 1,  500,10),
      ('ET-01','위생장갑','100매 x 20','박스','비품',        18000, false, 0,   20,11)
    ) as v(code,name,spec,unit,category,price,taxfree,moq,box_qty,sort)
   where not exists (select 1 from public.supply_items i
                      where i.company_id = cid and i.code = v.code and not i.deleted);
  get diagnostics n = row_count;
  raise notice '% : Re:Store 열림. 품목 % 개 새로 넣음.', target_code, n;
end $$;

-- ───────────────── 확인 ─────────────────
select c.code, c.name, c.apps,
       (select count(*) from public.supply_items i where i.company_id=c.id and not i.deleted) as 품목,
       (select count(*) from public.profiles   p where p.company_id=c.id) as 계정,
       (select count(*) from public.stores     s where s.company_id=c.id and not s.deleted) as 점포
  from public.companies c
 where c.code in ('9DORO','GUDORO')
 order by c.code;
