# 🏠 예약 · 결제 · 정산

게스트하우스 예약부터 결제 승인, 호스트 정산까지 — **"틀리면 안 되는" 금전 도메인**. 정합성을 트랜잭션·락·멱등성으로 방어했다.

## 핵심 설계
- **단일 트랜잭션 처리** — 결제 승인은 하나의 DB 트랜잭션에서 처리하고 실패 시 전체 롤백.
- **결제 멱등성** — Toss 승인 콜백이 중복 도착해도 Redis 락으로 단 한 번만 반영.
- **금액 위변조 검증** — 클라이언트가 보낸 결제 금액을 신뢰하지 않고 서버 저장 금액과 대조.
- **동시 예약 방어** — 방 가용성·성별 충돌 검증을 `SELECT ... FOR UPDATE`로 직렬화해 오버부킹 차단.
- **호스트 정산** — 매주 수요일 02:00 정산 배치. 크론이 아니라 **BullMQ 잡(재시도 3회 + 지수 백오프)** 으로 위임해 실패 내구성 확보.
- **법적 보관정책 자동화** — 전자상거래법 기준 예약/결제 5년, 신고 기록 3년 경과분을 스케줄러가 자동 파기.

### 결제 멱등성 + 금액 검증
```js
// Redis 분산 락으로 더블클릭(중복 결제 승인) 차단
const lock_key = `lock:confirm_payment:${orderId}`;
const acquired = await redis.set(lock_key, 'locked', 'NX', 'EX', 10); // 10초 TTL
if (!acquired) throw new AppError('현재 결제가 진행 중입니다.', 409);

// 클라이언트 금액을 신뢰하지 않고 서버 저장 금액과 대조
if (payment_info.amount !== Number(amount)) {
  throw new AppError('결제 요청 금액이 위변조되었습니다.', 400);
}
```

### 동시 예약 직렬화 (오버부킹 차단)
```js
// 방 가용성·성별 충돌 검증을 FOR UPDATE로 직렬화 → 동시 예약이 몰려도 정확한 재고
await tx(`SELECT capacity, room_type FROM house_rooms
          WHERE room_id = ? FOR UPDATE`, [roomId]);
await tx(`SELECT total_capacity, reserved_capacity, room_type
          FROM room_availability
          WHERE room_id = ? AND target_date = ? FOR UPDATE`, [roomId, date]);
```

> 이 도메인의 동시성 방어를 별도로 재현·정량화한 저장소 → **[concurrency-correctness-lab](https://github.com/pill27211/concurrency-correctness-lab)**
