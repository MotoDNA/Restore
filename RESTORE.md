# Re:Store — 한 장으로 보는 전부

가맹점이 **링크만 열어** 발주하고, 본사는 들어온 것을 한 화면에서 확정·출고합니다.
한 달이 지나면 쌓인 숫자가 **그대로 정산서**가 됩니다.

이 문서는 **지금 상태**만 적습니다. "언제 무엇을 왜 그렇게 했는가"는
[진행상황.md](진행상황.md)에, 설치는 [설치방법.md](설치방법.md)에 있습니다.

*기준 2026-08-30*

---

## 1. 어디에 있나

| | |
|---|---|
| 운영 | **https://dnalabs.kr/store** (권장) · https://restore.dnalabs.kr/ (옛 주소, 살아 있음) |
| 저장소 | https://github.com/MotoDNA/Restore — GitHub Pages, `main` push 후 1~2분 |
| 폴더 | `~/Desktop/Restore` |
| 첫 고객 | **구도로통닭** — 회사 코드 `9DORO` |

**옛 주소를 끄지 마세요.** 점주 발주 링크(`?t=`)가 그 주소로 나가고,
`dnalabs.kr/store` 는 거기서 내용을 **가져다 비추는 것**(Vercel rewrite)이라
끄면 새 주소도 함께 멈춥니다.

---

## 2. 형제 서비스 셋

DNA Labs 서비스가 셋이고 **같은 Supabase 프로젝트·같은 계정 목록**을 씁니다.

| 서비스 | 하는 일 | 새 주소 | 옛 주소 | 폴더 |
|---|---|---|---|---|
| Re:Bind | 프로젝트별 공정 관리 | `dnalabs.kr/bind` | `rebind.dnalabs.kr` | `~/Desktop/Rebind` |
| Re:Call | 고객관리 | `dnalabs.kr/call` | `recall.dnalabs.kr` | `~/Desktop/network-dna` |
| **Re:Store** | **가맹점 발주·정산** | `dnalabs.kr/store` | `restore.dnalabs.kr` | `~/Desktop/Restore` |

**Re:Store 가 막내입니다.** `0001_init.sql`(Re:Call)에서 만든 도우미 함수를 그대로 씁니다.

```
current_company_id()   지금 로그인한 사람의 회사
is_admin()             관리자인가
company_for_app(app)   그 서비스를 산 회사인가   ← ~/Desktop/Rebind/sql/0019_apps.sql
```

⚠ **셋이 얽혀 있어 하나만 보고 고치면 다른 쪽이 멈추는 것 셋**
1. `ALLOWED_ORIGIN` (6장) — **한 번 저절로 되돌아간 적이 있습니다**
2. `companies.apps` (5장)
3. 로그인 화면의 서비스 토글 — 세 앱이 같은 차례·같은 문구

---

## 3. 파일 구조

```
store.html            앱 전부. 파일 하나입니다 (2,665줄)
                      본사 화면과 점주 화면이 같은 파일입니다.
                      주소에 ?t=토큰 이 붙으면 점주 화면으로 갈립니다.
index.html            store.html 로 넘겨 주기만 합니다 (?t= 를 실어서)
sql/
  0001_restore.sql    표 넷과 접근 규칙 (407줄)
  0002_company.sql    회사에 Re:Store 를 열어 주고 품목을 채웁니다
  0003_grants.sql     표 권한 — 0001 에서 빠뜨렸던 것
supabase/functions/
  store-gate/         ★ 가맹점 문지기 (--no-verify-jwt)
  _shared/cors.ts     세 앱이 같은 파일을 씁니다
manifest.webmanifest · icon-*.png     홈 화면 설치용
```

### 화면 다섯

| 탭 | id | |
|---|---|---|
| 발주 | `p-orders` | 들어온 발주 · 확정 · 출고 |
| 점포 | `p-stores` | 가맹점 목록 · 발주 링크 · 핀 |
| 품목 | `p-items` | 공급 품목 · 단가 · 면세/과세 |
| 정산 | `p-bill` | 월정산 |
| 설정 | `p-set` | 계정·팀원 |

점주 화면은 `#pub` — **계정 없이 링크 + 핀 4자리**로 들어옵니다.

---

## 4. 데이터 모양

| 표 | |
|---|---|
| `stores` | 가맹점. `code` `name` `boss` `phone`/`phone_digits` `addr` `biz_*`(사업자 정보) `opened_on` `status` `pay_term` **`share_token` `share_on` `pin`** `memo` |
| `supply_items` | 공급 품목. `code` `name` `spec` `unit` `category` `price` **`taxfree`** `moq` `box_qty` `active` `sort` `photo_path` |
| `orders` | 발주. `store_id` `no` `ordered_at` `want_on` `status` `confirmed_on` `shipped_on` `done_on` `courier` `invoice_no` `ship_memo` `memo` **`memo_hq`** `vat_rate` **`by_store`** `billed_ym` |
| `order_lines` | 발주 줄. `order_id` `item_id` `name` `spec` `unit` **`price`** `taxfree` `qty` **`ship_qty`** `note` `sort` |

- **`taxfree`** — 면세/과세 구분. 외식 납품은 육류·농산물이 면세라 정산서가 갈립니다
- **`memo_hq`** — 본사 내부 메모. **점주에게 안 나갑니다**
- **`by_store`** — 점주가 넣은 발주인지, 본사가 대신 넣은 것인지
- **`ship_qty`** — 실제로 보낸 수량. 주문과 다를 수 있고 정산은 이것으로 합니다
- **`price`가 `order_lines` 에도 있는 이유** — 단가는 나중에 바뀝니다. 그때 이 발주에
  얼마로 넣었는지가 남아 있어야 정산서가 정직해집니다

지금 자료: 점포 1 · 품목 12 · 발주 1 · 발주줄 2 (시험점 `T-001`)

보관함: **`supply`**(비공개) — 품목 사진.

---

## 5. 누가 무엇을 볼 수 있나

### 회사 단위 — 어느 서비스를 샀나 (`companies.apps`)

```
apps text[]   {rebind} · {recall} · {restore} · 여러 개 가능
```

**비어 있으면 아무 데도 못 들어갑니다.** 새 회사를 만들 때 꼭 함께 넣으세요.

지금: `ACTIVA {rebind,recall}` · `BKT {rebind}` · **`9DORO {restore}`**

**화면이 아니라 데이터베이스가 막습니다.**
`company_for_app('restore')` 가 산 서비스면 회사 id, 아니면 null 을 돌려주고
정책이 그것과 비교합니다. null 과의 비교는 참이 되지 않아 그대로 닫힙니다.

| Re:Store 의 표 | `stores` · `supply_items` · `orders` · `order_lines` |
|---|---|
| 공용 | `companies` · `profiles` · `company_settings` · `audit_log` |

### 점주 — 계정이 없습니다

가맹점 점주는 **링크(토큰 32자) + 핀 4자리**로 들어옵니다.
`store-gate` 함수가 문지기입니다.

---

## 6. 접속과 서버

```
Project ref  izrtclsqhsgkuwsffifn
회사코드 9DORO / admin   ← 구도로통닭
```

```bash
cd ~/Desktop/Rebind          # supabase CLI 가 link 된 폴더
supabase db query --linked "select ..."
cd ~/Desktop/Restore
supabase functions deploy store-gate --no-verify-jwt --project-ref izrtclsqhsgkuwsffifn
```

`--no-verify-jwt` 를 빼면 **점주가 링크를 열 수 없습니다.**

### ⚠ ALLOWED_ORIGIN — 가장 자주 어긋나는 것

**네 주소가 함께 쓰는 값 하나입니다.** 실제로 세 번 어긋났습니다 —
한 번은 값이 안 들어갔고, 한 번은 저절로 되돌아갔고,
한 번은 `restore` 를 넣으면서 `dnalabs.kr` 이 빠졌습니다.
**틀려도 조용합니다** — 화면은 뜨고 로그인도 되는데 서버 함수만 막힙니다.

```bash
supabase secrets set ALLOWED_ORIGIN="https://rebind.dnalabs.kr,https://recall.dnalabs.kr,https://restore.dnalabs.kr,https://dnalabs.kr" \
  --project-ref izrtclsqhsgkuwsffifn
```

바꾼 뒤 **함수를 모두 다시 배포**해야 반영됩니다 —
`store-gate`(여기) · `share-view` `read-order`(Re:Bind) ·
`read-card` `admin-user` `signup` `subscription`(Re:Call).

**넣고 끝내지 말고 되읽어 확인하세요.**

```bash
curl -s -o /dev/null -D - -X OPTIONS \
  https://izrtclsqhsgkuwsffifn.supabase.co/functions/v1/store-gate \
  -H "Origin: https://dnalabs.kr" -H "Access-Control-Request-Method: POST" \
  | grep -i access-control-allow-origin
# → 부른 주소가 그대로 돌아오면 통과
```

### `store-gate` — 문지기가 조심하는 것 셋

Re:Bind 의 `share-view` 와 같은 자리지만 하는 일이 하나 더 많습니다.
share-view 는 **읽어 주기만** 했는데, 여기는 점주가 발주를 **씁니다.**

**1. 단가는 절대 브라우저에서 받지 않습니다.**
점주 화면이 보내는 것은 "무슨 품목 · 몇 개" 뿐입니다. 값은 이 함수가 품목표에서
직접 꺼내 붙입니다. 단가를 받아 쓰면 브라우저를 조작해 1원짜리 발주를 넣을 수 있습니다.

**2. 링크만으로는 못 들어옵니다. 핀 4자리를 함께 받습니다.**
링크는 카톡으로 돌아다니고, 점주는 폰을 바꾸고, 직원은 그만둡니다.
읽기만 하는 Re:Bind 링크와 달리 **여기는 돈이 오가므로** 한 겹 더 둡니다.

**3. 핀 틀린 횟수를 셉니다.** 4자리는 만 번이면 다 해 봅니다.
토큰(32자)까지 맞아야 하니 현실적으로 어렵지만, 늦춰 두면 더 좋습니다.

돌려주는 것은 **그 점포가 봐야 할 것뿐**입니다.
본사 내부 메모(`memo_hq`) · 다른 점포 · 담당자 id 는 나가지 않습니다.

---

## 7. 결제 — Re:Store 는 아직 붙어 있지 않습니다

**Re:Store 를 파는 요금제가 없습니다.** 결제 얼개는 Re:Call 이 갖고 있고
(`catalog.json` · `subscriptions` · `signup`/`subscription` 함수),
그 요금제는 전부 **Re:Call 용**입니다.

| 지금 있는 요금제 | Personal · Business 5 · Business 20 · Business 49 · Enterprise — **모두 Re:Call** |
|---|---|
| `9DORO` 는 어떻게 쓰고 있나 | `companies.apps = {restore}` 를 **손으로 넣었습니다.** `subscriptions` 에 줄이 없습니다 |
| 결제 표 상태 | `subscriptions` · `billing_methods` · `signup_attempts` **전부 비어 있습니다** |
| PG | **계약 전.** `web/pg.js` 가 스텁이라 실제 돈이 안 움직입니다 |

Re:Store 를 팔려면 정해야 할 것 —

1. **요금 단위** — 점포 수인가, 발주 건수인가, 정액인가
2. **`catalog.json` 에 어떻게 담을 것인가** — 지금 `plans` 는 Re:Call 전용 구조
   (`seatMin`/`seatMax`/`cardDailyLimit`)라 그대로 못 씁니다
3. **`subscriptions` 를 서비스별로 넓히기** — 지금은 `company_id` 가 기본키라
   **회사당 한 줄**입니다. 한 회사가 Re:Call 과 Re:Store 를 같이 사면 담을 데가 없습니다.
   `(company_id, product)` 로 넓혀야 합니다
4. **`companies.apps` 와 잇기** — 결제가 성사되면 `apps` 에 그 서비스를 더하도록

자세한 결제 현황은 **Re:Call 저장소의 `RECALL.md` 7장**에 있습니다
(`~/Desktop/network-dna/RECALL.md`).

---

## 8. 로그인 화면

세 서비스 토글. 세 앱이 **같은 차례·같은 문구**를 씁니다.

```js
const APPS     = ['rebind','recall','restore'];
const ONE_ROOF = {rebind:'/bind', recall:'/call', restore:'/store'};
const underOneRoof = ONE_ROOF[APP_KEY] === location.pathname.replace(/\/+$/,'');
```

서비스가 늘면 **세 파일에서 이 표에 한 줄씩** 더합니다.

| `dnalabs.kr/store` | 로그인 칸이 그대로. 여기서 로그인하고 그쪽으로 넘어갑니다 |
|---|---|
| `restore.dnalabs.kr` | 칸을 감추고 이동 단추만 — **엉뚱한 앱에 비밀번호를 치면 안 됩니다** |

**로그인 정보는 세 서비스가 똑같습니다.** 보관 자리도 셋 다 `ndna-auth` 라
한 지붕(`dnalabs.kr/*`)에서는 한 번 로그인하면 산 것이 다 열립니다.

- 안 산 것을 고르고 로그인하면 → 토글을 되돌리고 "○○ 를 쓰는 회사가 아닙니다"
- 산 것이 옆에 있으면 → 내쫓지 않고 그리로 보내고 이유를 알려 줍니다
- 고른 것은 기기에 남습니다(`localStorage['dnalabs-app']`)

칸의 예시 글자도 셋이 같습니다 — `예: ABCDEF` / `예: gdhong`.
한동안 Re:Store 만 `예: GUDORO / 예: admin` 을 썼습니다. 회사 코드 하나를
그대로 적어 둔 것이라, 같은 화면에서 토글만 눌렀는데 예시가 달라져 눈에 걸렸습니다.
Re:Call 에만 있던 안내줄("회사에서 받은 코드와 아이디로 들어옵니다")도 뺐습니다 —
토글할 때마다 제목과 칸 사이가 벌어졌다 좁아졌고, 아래 꼬리말이 같은 말을 합니다.

---

## 9. 고칠 때 지키는 것

**1. 문법 검사만으로는 부족합니다.** 한 파일이라 초기화 순서 오류(TDZ)는 안 걸러집니다.

```bash
python3 -c "
import io,re
s=io.open('store.html',encoding='utf-8').read()
io.open('/tmp/app.js','w',encoding='utf-8').write(re.findall(r'<script>(.*?)</script>',s,re.S)[-1])
" && node --check /tmp/app.js
```

**2. 반드시 브라우저로 열어 보고 콘솔까지 봅니다.**
한 지붕 동작을 볼 때는 `/bind`·`/call`·`/store` 를 한 주소에서 내려 주는
작은 서버를 띄웁니다(그래야 `underOneRoof` 가 켜집니다).

**3. 점주 화면은 시크릿 창에서 확인합니다.** 로그인이 남아 있으면 본사 화면이 뜹니다.

**4. 올린 뒤에도 열어 봅니다.** GitHub Pages 1~2분, **브라우저가 옛 파일을
한동안 보여 줍니다** — 안 바뀐 것 같으면 주소 뒤에 `?v=2`.

**5. 파이썬으로 고칩니다.** `assert old in s` 로 자리를 확인하고 `replace(old,new,1)`.

---

## 10. 배포

| 무엇 | 어떻게 |
|---|---|
| 앱 | `git push` → GitHub Pages 1~2분 |
| 서버 함수 | `supabase functions deploy store-gate --no-verify-jwt --project-ref izrtclsqhsgkuwsffifn` |
| SQL | `supabase db query --linked -f sql/000N_….sql` |
| rewrite (`/store`) | `cd ~/Desktop/network-dna && npx vercel --prod --scope chhanj40-5991s-projects` |
| 로고 | `python3 ~/Desktop/Rebind/make-logo.py` → 세 앱에 함께. **저장소 셋을 각각 커밋** |

`dnalabs.kr/store` 는 rewrite 라 **GitHub Pages 만 반영되면 함께 바뀝니다.**

---

## 11. ⚠ 알고 있는 구멍

### 1. 직원에게 금액이 "화면에서만" 가려집니다

지금은 화면이 안 그릴 뿐이고 **데이터베이스는 직원에게도 단가를 내보냅니다.**
개발자 도구를 열면 보입니다.

Re:Bind 도 처음에 똑같았고, 나중에 금액을 딴 표(`project_money`)로 빼서
진짜로 막았습니다. **여기도 같은 일을 해야 합니다.**
급하지 않은 이유는 지금 쓰는 회사에 직원 계정이 없기 때문입니다 —
**직원 계정을 만들기 전에 먼저 하세요.**

### 2. 핀이 데이터베이스에 그대로 들어 있습니다

암호로 바꿔 두지 않았습니다. 본사가 "이 점포 핀이 뭐였지"를 볼 수 있어야 해서입니다.
그 대신 틀린 횟수를 세서 늦춥니다. 점포가 수백 개로 늘면 다시 생각해야 합니다.

### 3. 세 앱이 `ALLOWED_ORIGIN` 값 하나를 함께 씁니다 (6장)

---

## 12. 함정 모음

| | |
|---|---|
| `word-break:keep-all` | 혼자 두면 띄어쓰기 없는 긴 것(주소·링크)에 가로 스크롤이 생깁니다. `overflow-wrap:break-word` 를 **꼭 같이**. 낡은 `word-break:break-word` 는 keep-all 을 무너뜨리니 쓰지 마세요 |
| `ALLOWED_ORIGIN` | 넷을 다 적고 **되읽어 확인**. 틀려도 조용합니다 |
| `store-gate` 배포 | `--no-verify-jwt` 를 빼면 점주가 못 들어옵니다 |
| 단가 | **점주 화면이 보낸 값을 절대 믿지 마세요.** 서버가 품목표에서 꺼냅니다 |
| `memo_hq` | 점주에게 나가면 안 됩니다 |
| 회사 만드는 순서 | `setup-admin.sh`(Re:Call)가 **이미 있는 회사 코드를 거부**합니다. 회사를 SQL 로 먼저 만들면 계정을 못 만듭니다 — **계정 먼저, `0002_company.sql` 은 나중** |
| 표 권한 | `0001` 에서 `grant` 를 빠뜨려 표는 있는데 아무도 못 읽었습니다. 새 표를 만들면 `0003_grants.sql` 처럼 권한도 함께 |
| 새 회사 | `apps` 를 꼭 함께 넣으세요 |
| 면세/과세 | `taxfree` 를 잘못 넣으면 정산서가 통째로 틀립니다. 품목을 받을 때 특히 확인 |

---

## 13. 아직 안 한 것

- **금액을 딴 표로 빼기** (구멍 1). **직원 계정을 만들기 전에**
- **구도로통닭 실제 품목·단가** — 지금 12개는 시험용. **면세/과세 구분이 특히 중요**
- **발주 마감시간** — 외식은 "몇 시까지 넣은 것은 내일 출고" 가 있습니다. 지금 없습니다
- **점포 등급별 단가** — 같은 품목을 점포마다 다르게 주는 곳이 있습니다. 지금은 한 값
- **로열티 정산** — 매출의 몇 %를 따로 청구하는 구조. 지금은 물품 대금만
- **Re:Store 요금제** (7장) — 파는 방법 자체가 아직 없습니다

---

## 14. 말투

한국어로 씁니다. **무엇을 했는지가 아니라 왜 그렇게 했는지**를 적습니다.
과장하지 않고, 안 된 것은 안 됐다고 적습니다.
사용자는 개발자가 아닙니다 — 전문 용어는 한 줄로 풀어 줍니다.
