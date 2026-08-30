// 가맹점 문지기 — 점주는 계정이 없습니다.
//
// Re:Bind 의 share-view 와 같은 자리에 있지만, 하는 일이 하나 더 많습니다.
// share-view 는 읽어 주기만 했습니다. 여기는 점주가 발주를 **씁니다**.
// 그래서 조심할 것이 세 가지 더 있습니다.
//
//   1) 단가는 절대 브라우저에서 받지 않습니다.
//      점주 화면이 보낸 것은 "무슨 품목 · 몇 개" 뿐입니다.
//      값은 이 함수가 품목표에서 직접 꺼내 붙입니다.
//      단가를 받아 쓰면, 브라우저를 조작해 1원짜리 발주를 넣을 수 있습니다.
//
//   2) 링크만으로는 못 들어옵니다. 핀 4자리를 함께 받습니다.
//      링크는 카톡으로 돌아다니고, 점주는 폰을 바꾸고, 직원은 그만둡니다.
//      읽기만 하는 Re:Bind 링크와 달리 여기는 돈이 오가므로 한 겹 더 둡니다.
//
//   3) 핀 틀린 횟수를 셉니다. 4자리는 만 번이면 다 해 봅니다.
//      토큰(32자)까지 맞아야 하니 현실적으로 어렵지만, 늦춰 두면 더 좋습니다.
//
// 돌려주는 것은 그 점포가 봐야 할 것뿐입니다.
// 본사 내부 메모(memo_hq) · 다른 점포 · 담당자 id 는 나가지 않습니다.
//
// 배포:
//   supabase functions deploy store-gate --no-verify-jwt --project-ref izrtclsqhsgkuwsffifn
//   (--no-verify-jwt 를 빼면 점주가 열 수 없습니다)
import { createClient } from 'jsr:@supabase/supabase-js@2';
import { mkJson } from '../_shared/cors.ts';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const SERVICE = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const admin = createClient(URL_, SERVICE, { auth: { persistSession: false } });

const TOKEN_RE = /^[a-f0-9]{32,64}$/;
const PHOTO_TTL = 60 * 60;
const MAX_LINES = 200;          // 발주서 한 장에 담을 수 있는 줄 수
const MAX_QTY = 1_000_000;

// ───────── 너무 자주 부르는 것을 늦춥니다 ─────────
// 서버 한 대 안에서만 세는 것이라 완벽하지 않습니다. 늦추는 것이 목적입니다.
const hits = new Map<string, { n: number; at: number }>();
function tooMany(ip: string, cap = 60): boolean {
  const now = Date.now();
  const cur = hits.get(ip);
  if (!cur || now - cur.at > 60_000) { hits.set(ip, { n: 1, at: now }); return false; }
  cur.n++;
  if (hits.size > 5000) hits.clear();
  return cur.n > cap;
}

// ───────── 핀을 틀린 횟수 ─────────
// 점포별로 셉니다. 한 점포 링크에 매달려도 다른 점포는 멀쩡합니다.
const bad = new Map<string, { n: number; at: number }>();
function pinBlocked(token: string): boolean {
  const cur = bad.get(token);
  if (!cur) return false;
  if (Date.now() - cur.at > 10 * 60_000) { bad.delete(token); return false; }
  return cur.n >= 10;
}
function pinMissed(token: string) {
  const cur = bad.get(token);
  if (!cur || Date.now() - cur.at > 10 * 60_000) { bad.set(token, { n: 1, at: Date.now() }); return; }
  cur.n++; cur.at = Date.now();
  if (bad.size > 5000) bad.clear();
}

// 같은 길이만큼 비교합니다. 빨리 틀리는 것으로 자릿수를 알아내지 못하게.
function sameSecret(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

const NOPE = { ok: false, error: '없는 주소입니다.' };

Deno.serve(async (req) => {
  const { cors, json } = mkJson(req);
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'POST 만 받습니다.' }, 405);

  const ip = req.headers.get('x-forwarded-for')?.split(',')[0]?.trim() ?? 'unknown';
  if (tooMany(ip)) return json({ ok: false, error: '잠시 뒤에 다시 열어 주세요.' }, 429);

  let body: { token?: string; pin?: string; action?: string; order?: unknown };
  try { body = await req.json(); } catch { return json({ ok: false, error: '잘못된 요청입니다.' }, 400); }

  const token = String(body.token ?? '').trim().toLowerCase();
  const pin = String(body.pin ?? '').trim();
  const action = String(body.action ?? 'open');
  if (!TOKEN_RE.test(token)) return json(NOPE, 404);

  // ───────── 점포 찾기 ─────────
  const { data: s } = await admin
    .from('stores')
    .select('id, company_id, code, name, boss, phone, addr, biz_no, biz_name, ' +
            'status, pay_term, pin, share_on, deleted')
    .eq('share_token', token)
    .maybeSingle();

  // 없는 토큰과 꺼 둔 링크를 같은 말로 돌려줍니다. 있는지 없는지도 알려 주지 않습니다.
  if (!s || s.deleted || !s.share_on) return json(NOPE, 404);

  // 산 서비스인지도 봅니다. 구독이 끊기면 점주 링크도 함께 닫혀야 합니다.
  const { data: co } = await admin
    .from('companies').select('name, apps, disabled').eq('id', s.company_id).maybeSingle();
  if (!co || co.disabled || !(co.apps ?? []).includes('restore')) return json(NOPE, 404);

  // ───────── 핀 확인 ─────────
  if (s.pin) {
    if (pinBlocked(token)) return json({ ok: false, error: '잠시 뒤에 다시 해 주세요.', needPin: true }, 429);
    if (!pin) return json({ ok: false, error: '핀을 넣어 주세요.', needPin: true }, 401);
    if (!sameSecret(pin, s.pin)) { pinMissed(token); return json({ ok: false, error: '핀이 다릅니다.', needPin: true }, 401); }
  }
  bad.delete(token);

  const closed = s.status === 'closed';

  // ───────── 발주 넣기 ─────────
  if (action === 'place') {
    if (closed) return json({ ok: false, error: '폐점 처리된 점포입니다. 본사로 연락해 주세요.' }, 403);
    if (tooMany('place:' + token, 20)) return json({ ok: false, error: '잠시 뒤에 다시 해 주세요.' }, 429);

    const o = (body.order ?? {}) as { lines?: { itemId?: string; qty?: number; note?: string }[]; wantOn?: string; memo?: string };
    const raw = Array.isArray(o.lines) ? o.lines.slice(0, MAX_LINES) : [];
    const want = raw
      .map((l) => ({ itemId: String(l.itemId ?? ''), qty: Math.floor(Number(l.qty) || 0), note: String(l.note ?? '').slice(0, 200) }))
      .filter((l) => l.itemId && l.qty > 0 && l.qty <= MAX_QTY);
    if (!want.length) return json({ ok: false, error: '발주할 품목을 골라 주세요.' }, 400);

    // 값은 우리가 꺼냅니다. 브라우저가 보낸 단가는 쳐다보지도 않습니다.
    const { data: items } = await admin
      .from('supply_items')
      .select('id, code, name, spec, unit, price, taxfree, moq, active, deleted')
      .eq('company_id', s.company_id)
      .in('id', want.map((l) => l.itemId));

    const byId = new Map((items ?? []).map((i) => [i.id, i]));
    const lines: Record<string, unknown>[] = [];
    for (const [n, l] of want.entries()) {
      const it = byId.get(l.itemId);
      if (!it || it.deleted || !it.active) continue;      // 조용히 버립니다 — 없는 품목입니다
      if (it.moq > 0 && l.qty < it.moq) {
        return json({ ok: false, error: `${it.name} 은(는) 최소 ${it.moq}개부터 발주할 수 있습니다.` }, 400);
      }
      lines.push({
        company_id: s.company_id, item_id: it.id,
        name: it.name, spec: it.spec, unit: it.unit,
        price: it.price, taxfree: it.taxfree,
        qty: l.qty, note: l.note, sort: n,
      });
    }
    if (!lines.length) return json({ ok: false, error: '지금 발주할 수 있는 품목이 없습니다.' }, 400);

    // 발주번호 — 그 회사의 그날 몇 번째인가
    const today = new Date().toISOString().slice(0, 10);
    const { count } = await admin
      .from('orders').select('id', { count: 'exact', head: true })
      .eq('company_id', s.company_id)
      .gte('ordered_at', today + 'T00:00:00Z');
    const no = today.replace(/-/g, '') + '-' + String((count ?? 0) + 1).padStart(3, '0');

    const wantOn = /^\d{4}-\d{2}-\d{2}$/.test(String(o.wantOn ?? '')) ? String(o.wantOn) : null;

    const { data: ord, error: e1 } = await admin
      .from('orders')
      .insert({
        company_id: s.company_id, store_id: s.id, no,
        want_on: wantOn, memo: String(o.memo ?? '').slice(0, 1000),
        status: 'placed', by_store: true,
      })
      .select('id, no, ordered_at').single();
    if (e1 || !ord) return json({ ok: false, error: '발주를 넣지 못했습니다. 다시 해 주세요.' }, 500);

    const { error: e2 } = await admin.from('order_lines')
      .insert(lines.map((l) => ({ ...l, order_id: ord.id })));
    if (e2) {
      // 줄이 안 들어갔으면 빈 발주서를 남기지 않습니다
      await admin.from('orders').delete().eq('id', ord.id);
      return json({ ok: false, error: '발주를 넣지 못했습니다. 다시 해 주세요.' }, 500);
    }

    return json({ ok: true, orderId: ord.id, no: ord.no, at: ord.ordered_at });
  }

  // ───────── 발주 취소 ─────────
  // 본사가 확정하기 전(placed)까지만. 그 뒤에는 전화로 하는 편이 낫습니다.
  if (action === 'cancel') {
    const id = String((body.order as { id?: string } | undefined)?.id ?? '');
    if (!id) return json({ ok: false, error: '잘못된 요청입니다.' }, 400);
    const { data: ord } = await admin
      .from('orders').select('id, status, store_id, deleted').eq('id', id).maybeSingle();
    if (!ord || ord.deleted || ord.store_id !== s.id) return json(NOPE, 404);
    if (ord.status !== 'placed') return json({ ok: false, error: '이미 본사가 확인한 발주입니다. 본사로 연락해 주세요.' }, 409);
    await admin.from('orders').update({ status: 'canceled' }).eq('id', ord.id);
    return json({ ok: true });
  }

  // ───────── 열어 보기 (기본) ─────────
  const [{ data: items }, { data: orders }] = await Promise.all([
    admin.from('supply_items')
      .select('id, code, name, spec, unit, price, taxfree, category, moq, box_qty, photo_path, sort')
      .eq('company_id', s.company_id).eq('deleted', false).eq('active', true)
      .order('sort', { ascending: true }).order('name', { ascending: true }),
    admin.from('orders')
      // memo_hq 는 고르지 않습니다. 본사 내부 메모입니다.
      .select('id, no, ordered_at, want_on, status, confirmed_on, shipped_on, done_on, ' +
              'courier, invoice_no, ship_memo, memo, vat_rate, ' +
              'order_lines(id, name, spec, unit, price, taxfree, qty, ship_qty, note, sort)')
      .eq('store_id', s.id).eq('deleted', false)
      .order('ordered_at', { ascending: false })
      .limit(60),
  ]);

  // 품목 사진은 한 시간짜리 주소로만 나갑니다
  const paths = (items ?? []).map((i) => i.photo_path).filter(Boolean) as string[];
  const photo: Record<string, string> = {};
  if (paths.length) {
    const { data: signed } = await admin.storage.from('supply').createSignedUrls(paths, PHOTO_TTL);
    for (const r of signed ?? []) if (r.path && r.signedUrl) photo[r.path] = r.signedUrl;
  }

  return json({
    ok: true,
    hq: { name: co.name },
    store: {
      code: s.code, name: s.name, boss: s.boss, phone: s.phone, addr: s.addr,
      bizNo: s.biz_no, bizName: s.biz_name, status: s.status, payTerm: s.pay_term,
      canOrder: s.status === 'open',
    },
    items: (items ?? []).map((i) => ({
      id: i.id, code: i.code, name: i.name, spec: i.spec, unit: i.unit,
      price: Number(i.price), taxfree: i.taxfree, category: i.category,
      moq: i.moq, boxQty: i.box_qty,
      photo: i.photo_path ? (photo[i.photo_path] ?? null) : null,
    })),
    orders: (orders ?? []).map((o) => ({
      id: o.id, no: o.no, at: o.ordered_at, wantOn: o.want_on, status: o.status,
      confirmedOn: o.confirmed_on, shippedOn: o.shipped_on, doneOn: o.done_on,
      courier: o.courier, invoiceNo: o.invoice_no, shipMemo: o.ship_memo,
      memo: o.memo, vatRate: Number(o.vat_rate),
      lines: (o.order_lines ?? [])
        .sort((a: { sort: number }, b: { sort: number }) => a.sort - b.sort)
        .map((l: Record<string, unknown>) => ({
          name: l.name, spec: l.spec, unit: l.unit,
          price: Number(l.price), taxfree: l.taxfree,
          qty: l.qty, shipQty: l.ship_qty, note: l.note,
        })),
    })),
  });
});
