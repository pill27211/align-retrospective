# 📰 커뮤니티 실시간 랭킹

트래픽이 늘수록 조회·반응 집계가 DB 병목이 되고, 오래된 인기글이 피드를 영원히 점유하는 "불멸의 인기글" 문제가 생긴다. **캐시 계층 + 수학적 점수 설계**로 풀었다.

## 핵심 설계
- **조회 중복 제거 — HyperLogLog** — `PFADD`로 게시글당 **고정 메모리**에 유니크 조회를 집계 (메모리 단편화 원천 차단).
- **계층형 읽기** — 실시간 인기글 **Top-1000은 Redis ZSET에서 즉시 서빙**, 그 이하 깊은 페이지네이션은 MySQL `trending_score`로 폴백.
- **마이크로배치** — 점수 갱신을 요청마다 DB에 반영하지 않고 **Set 버퍼에 모아 주기적으로 일괄 반영** → DB 락·지연 스파이크 제거.
- **트렌딩 점수** — 로그 스케일 참여도 + 시간 감쇠 + 베이지안(라플라스) 스무딩으로 메가히트 한 건이 생태계를 지배하는 문제를 완화.

### 조회 집계 (라우터는 즉시 응답, 반영은 뒤에서)
```js
// HyperLogLog로 유니크 조회 집계 — 게시글당 고정 메모리
const is_new = await redis.pfadd(`post_touch_hll:${postId}:${date}`, userId);
if (is_new === 1) {
  await redis.incr(`post_touch_count:${postId}`);  // DB 대신 Redis 누적 (새벽 배치가 반영)
  await redis.sadd('dirty_posts:ranking', postId);  // 랭킹 갱신 대상만 버퍼링 (마이크로배치)
}
```

> 설계 상세 → **[실시간 랭킹 시스템 — ZSET과 마이크로 배치](https://yeohaenghage.kr/backend/post_ranking/)**
> 동기 vs 비동기 쓰기 경로 성능 → **[write-path-bench](https://github.com/pill27211/write-path-bench)** (처리량 **4.03×↑**, p99 **-64%**)
