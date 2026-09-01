-- ═══════════════════════════════════════════════════════════════
-- 핀을 틀린 횟수를 데이터베이스에 적습니다
--
-- 지금까지는 store-gate 함수의 **메모리**에 세고 있었습니다.
--   const bad = new Map<string, {n, at}>()
--
-- Edge Function 은 잠깐 쉬면 내려갔다 새로 뜹니다. 그때 센 것이 0 으로
-- 돌아갑니다. 여러 대가 동시에 돌면 각자 따로 셉니다. 표가 5000개를
-- 넘으면 통째로 비우기까지 했습니다.
--
-- 그래서 "10번 틀리면 10분 잠김" 이 실제로는 잘 안 걸렸습니다.
-- 네 자리 핀은 만 개뿐이라, 시간을 들이면 뚫립니다.
--
-- 여기에 적으면 함수가 몇 번을 새로 뜨든 잊지 않습니다.
--
-- ⚠ 이 표는 **service_role 만** 봅니다. 브라우저에서 닿으면
--   "몇 번 틀렸는지" 를 지워 버릴 수 있어 세는 뜻이 없어집니다.
-- ═══════════════════════════════════════════════════════════════
create table if not exists public.pin_tries (
  token text primary key,
  n     integer     not null default 0,
  at    timestamptz not null default now()
);

alter table public.pin_tries enable row level security;
alter table public.pin_tries force row level security;

-- 정책 없음 = 브라우저에서는 아무것도 못 합니다
revoke all on public.pin_tries from anon, authenticated;
grant all privileges on public.pin_tries to service_role;

comment on table public.pin_tries is
  '가맹점 발주 링크의 핀을 틀린 횟수. store-gate 만 씁니다. '
  '메모리에 세면 함수가 새로 뜰 때마다 잊어버려서 여기로 옮겼습니다.';

-- ── 한 번에 세고 결과를 돌려줍니다 ──
-- 읽고 나서 쓰면, 동시에 두 번 찔렀을 때 둘 다 "9번째" 로 읽고 지나갑니다.
-- 한 문장으로 올리고 올라간 값을 받아야 그 틈이 없습니다.
create or replace function public.pin_miss(p_token text)
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare c integer;
begin
  -- 오래된 것은 지나는 길에 치웁니다. 따로 청소하는 일을 만들지 않으려고요.
  delete from public.pin_tries where at < now() - interval '1 day';

  insert into public.pin_tries (token, n, at)
       values (p_token, 1, now())
  on conflict (token) do update
     set n  = case when now() - public.pin_tries.at > interval '10 minutes'
                   then 1 else public.pin_tries.n + 1 end,
         at = now()
  returning n into c;
  return c;
end $$;

revoke all on function public.pin_miss(text) from anon, authenticated, public;
grant execute on function public.pin_miss(text) to service_role;

comment on function public.pin_miss(text) is
  '핀을 틀렸다고 알리고 지금까지 몇 번인지 돌려줍니다. 10분이 지나면 다시 1부터.';
