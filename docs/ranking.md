# 📰 커뮤니티 실시간 랭킹

트래픽이 늘수록 조회·반응 집계가 DB 병목이 되고, 오래된 인기글이 피드를 영원히 점유하는 "불멸의 인기글" 문제가 생긴다. **캐시 계층 + 수학적 점수 설계**로 풀었다.

## 핵심 설계
- **조회 중복 제거 — HyperLogLog** — `PFADD`로 게시글당 **고정 메모리**(±0.81% 오차)에 유니크 조회를 집계 (메모리 단편화 원천 차단).
- **계층형 읽기** — 실시간 인기글 **Top-1000은 Redis ZSET에서 즉시 서빙**, 그 이하 깊은 페이지네이션은 MySQL `trending_score`로 폴백.
- **마이크로배치** — 점수 갱신을 요청마다 DB에 반영하지 않고 **Set 버퍼에 모아 10초 주기로 일괄 반영** → DB 락·지연 스파이크 제거.
- **트렌딩 점수** — 로그 스케일 참여도 + 시간 감쇠 + 베이지안(라플라스) 스무딩으로 메가히트 한 건이 생태계를 지배하는 문제를 완화.

---

## 사용자 액션별 흐름

모든 쓰기성 액션은 **요청 스레드에서 DB를 직접 때리지 않는다.** 조회는 Redis 버퍼 + 마이크로배치로, 좋아요·댓글·신고는 BullMQ 워커로 위임하고 라우터는 즉시 응답한다. (성능 근거 → [write-path-bench](https://github.com/pill27211/write-path-bench): 처리량 **4.03×↑**, p99 **-64%**)

### 🖱️ 조회 — 라우터는 즉시 응답, 반영은 뒤에서
`GET /get_post_info`. 오늘 이미 본 유저면 아무것도 하지 않고, 첫 조회일 때만 Redis에 누적 + 랭킹 갱신 대상으로 표시만 남긴다.
```js
// HyperLogLog로 당일 유니크 조회 판정 — 게시글당 고정 메모리
const is_new = await redis.pfadd(`post_touch_hll:${postId}:${date}`, userId);
if (is_new === 1) {
  await redis.incr(`post_touch_count:${postId}`);   // DB 대신 Redis 누적 (새벽 배치가 반영)
  await redis.sadd('dirty_posts:ranking', postId);  // 랭킹 갱신 대상만 버퍼링 (마이크로배치)
}
```
→ 클릭 100만 번이 와도 DB write는 **0회**.

### ❤️ 좋아요 · 💬 댓글 — 큐에 넣고 즉시 응답
좋아요는 큐잉만 하고, 댓글은 **핵심 데이터(INSERT)만 동기로 보장**한 뒤 부가 작업(카운트·알림·랭킹)을 워커로 넘긴다. 댓글은 랭킹 계산 시 도배 방지를 위해 **유니크 작성자 Set**을 따로 쌓는다.
```js
// 댓글: 본문은 동기 INSERT로 보장
await functions.query('INSERT INTO post_comments(user_id, post_id, content) VALUES (?,?,?)', ...);
// 랭킹 점수는 comment_count가 아니라 '고유 작성자 수'로 계산 → 한 명이 100개 도배해도 +1
await redis.sadd(`post_unique_commenters:${postId}`, userId);
await post_queue.add('process_new_comment', { post_id, user_id, content }); // 나머지는 워커로
```
워커(`postWorker`)가 `comment_count`/`like_count`를 증분하고, 알림을 보낸 뒤 `updateTrendingRank`로 **점수를 즉시 재계산**한다.

### 🚨 신고 — 멱등 집계 + 즉시 강등
동일 유저의 중복 신고는 UNIQUE 제약으로 막고, `report_count`는 증분이 아니라 **`COUNT(*)` 재계산**으로 맞춘다(워커 크래시에도 안 꼬이는 멱등 동기화). 이후 페널티가 반영된 점수로 즉시 강등.
```js
await funcs.query(
  `INSERT IGNORE INTO post_reports (post_id, user_id, reason, ...) VALUES (?,?,?, ...)`, ...);
await funcs.query( // 멱등: 누적값을 신뢰하지 않고 매번 실측으로 덮어씀
  `UPDATE user_posts SET report_count = (SELECT COUNT(*) FROM post_reports WHERE post_id = ?) WHERE post_id = ?`, ...);
await updateTrendingRank(funcs, redis, postId); // 페널티 적용 → 랭킹 강등
```

---

## 트렌딩 점수 산식
로그 스케일 참여도(메가히트 억제) + 선형 시간 감쇠(12시간마다 리셋되며 뒤집으려면 10배의 참여 필요) + 신고 페널티.
```js
function calculatePopularScore(like, comment, touch, report, created_at) {
  const engagement = like * 3 + comment * 5 + touch * 1;

  // 신고 페널티 — 베이지안 라플라스 스무딩(α=100)으로 신규글 '좌표찍기 테러' 방어
  // 악성 신고 비율 15% 도달 시 페널티 1.0(완전 노출 차단)이 되도록 6.666을 곱함
  const report_ratio = report / (touch + 100);
  const penalty = Math.min(1.0, report_ratio * 6.666);
  let net = Math.max(1, engagement * (1 - penalty));

  let order = Math.log10(net);
  if (net < 3) order -= 1.0;              // Cold-start 페널티: 순수 새 글의 무조건 최상단 진입 방지(12h 샌드박스)

  const seconds = Math.floor(new Date(created_at).getTime() / 1000);
  return order + (seconds - 1704067200) / 43200; // 43200초 = 12시간 감쇠 주기
}
```
`updateTrendingRank`가 이 점수로 ZSET을 갱신하고 Top-1000만 남긴다.
```js
await redis.zadd(`ranking:popular_posts:0`, new_score, postId);        // 전체
await redis.zremrangebyrank(`ranking:popular_posts:0`, 0, -1001);       // 메모리: Top-1000 초과 방출
if (label_index > 0) await redis.zadd(`ranking:popular_posts:${label_index}`, new_score, postId); // 카테고리별
```

## 마이크로배치 (10초 주기)
조회 폭주를 이벤트마다 처리하지 않고, 버퍼에 모인 dirty 글을 **10초에 한 번, 최대 100개**만 갱신한다. 다중 워커 중복 실행은 `SET NX EX` 분산 락으로 막는다.
```js
const lock = await redis.set('lock:dirty_posts_batch', '1', 'EX', 15, 'NX');
if (!lock) return; // 다른 인스턴스가 처리 중 → 스킵
const ids = await redis.spop('dirty_posts:ranking', 100); // 쌓인 걸 한 번에 꺼냄
for (const id of ids) await updateTrendingRank(funcs, redis, id);
// finally에서 무조건 락 해제 (좀비 락 방지)
```

## 심야 동기화 (04:00)
Redis에만 있던 버퍼 조회수를 DB에 영구화하고, **실시간과 동일한 산식**으로 `trending_score` 컬럼을 갱신한다. 이 컬럼이 Top-1000 밖(깊은 페이지네이션·캐시 미스)의 폴백 정렬 기준이 된다.
- **논블로킹 순회** — `KEYS` 대신 `SCAN` 커서로 이벤트 루프 블로킹 회피.
- **청크 쓰기** — 100개 단위로 끊어 트랜잭션 락 경합 최소화.
- **산식 SSOT** — 실시간(`postWorker`)과 심야(`dailyWorker`)의 점수 계산은 **동일**해야 한다. 과거 심야 배치가 신고 페널티를 `touch>=20` 게이트 + 스무딩 없는 단순 비율로 다르게 계산해 동기화 직후 점수가 미세하게 튀던 문제를 발견, 실시간 산식(라플라스 스무딩 α=100)으로 **통일**했다.

---

> 설계 상세(수식 유도·트레이드오프) → **[실시간 랭킹 시스템 — ZSET과 마이크로 배치](https://yeohaenghage.kr/backend/post_ranking/)**
> 동기 vs 비동기 쓰기 경로 성능 → **[write-path-bench](https://github.com/pill27211/write-path-bench)** (처리량 **4.03×↑**, p99 **-64%**)
