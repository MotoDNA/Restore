// 브라우저가 이 함수를 부를 수 있는지 정하는 곳입니다.
//
// ALLOWED_ORIGIN 에 허용할 주소를 적습니다. 쉼표로 여러 개 적을 수 있습니다.
//   supabase secrets set ALLOWED_ORIGIN="https://rebind.dnalabs.kr,https://recall.dnalabs.kr" \
//     --project-ref izrtclsqhsgkuwsffifn
//
// ⚠ 이 값은 Re:Bind 와 Re:Call 이 함께 쓰는 하나뿐인 값입니다.
//   두 앱이 같은 Supabase 프로젝트를 쓰기 때문입니다.
//   한쪽 주소만 적어 돌리면 그 순간 다른 쪽 앱이 멈춥니다.
//   고칠 때는 늘 두 주소를 함께 적으세요. 지우는 것도 함께 생각하세요.
//
//   그리고 이 값을 바꾸면 네 함수를 모두 다시 배포해야 반영됩니다 —
//     share-view · read-order   (Re:Bind)
//     read-card  · admin-user   (Re:Call)
//
// 비워 두면 어디서든 부를 수 있습니다. 설치 중에만 그렇게 두세요.
//
// 이것만으로 보안이 되지는 않습니다. 브라우저에게 주는 안내일 뿐이고,
// 실제 차단은 함수 안의 로그인 확인과 데이터베이스 규칙이 합니다.
// 다만 열어 둘 이유가 없으므로 운영 전에는 잠급니다.

const ALLOWED = (Deno.env.get('ALLOWED_ORIGIN') ?? '')
  .split(',').map((s) => s.trim()).filter(Boolean);

export function corsFor(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? '';
  // 목록이 비어 있으면 모두 허용, 아니면 부른 곳이 목록에 있을 때만 그 주소를 돌려줍니다.
  // 목록에 없으면 첫 번째 주소를 적어 보내 브라우저가 막도록 둡니다.
  const allow = ALLOWED.length === 0 ? '*'
              : (ALLOWED.includes(origin) ? origin : ALLOWED[0]);
  return {
    'Access-Control-Allow-Origin': allow,
    // 부른 곳에 따라 답이 달라지므로 중간 서버가 잘못 캐시하지 않도록 알립니다
    'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-setup-secret',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

/* 요청 하나에 쓸 cors 와 json 을 만들어 줍니다.
   함수 맨 앞에서 한 번 꺼내 쓰면 됩니다:
     const { cors, json } = mkJson(req); */
export function mkJson(req: Request) {
  const cors = corsFor(req);
  return {
    cors,
    json: (body: unknown, status = 200) =>
      new Response(JSON.stringify(body), {
        status,
        headers: { ...cors, 'Content-Type': 'application/json' },
      }),
  };
}
