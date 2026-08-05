# 💬 실시간 메시징 · 여행 동행 매칭

Socket.IO 기반 실시간 채팅과 여행 동행 매칭. 다중 서버 환경에서도 메시지가 새지 않도록 **Redis 클러스터링 + Pub/Sub**으로 설계했다.

## 핵심 설계
- **신뢰할 수 없는 클라이언트** — Socket.IO 핸드셰이크에서 **JWT를 검증**하고, 클라이언트가 보낸 `user_id`는 무시한 채 토큰에서 추출한 ID만 신뢰.
- **소켓 클러스터링** — `@socket.io/redis-adapter`로 다중 message-server 간 브로드캐스트를 투명 처리 → 어느 인스턴스에 붙어도 메시지 전달.
- **서버 간 이벤트 전파** — 이미지 업로드 완료 / 메시지 트랜잭션 성공·실패를 **Redis Pub/Sub 채널**로 전파.
- **오프라인 폴백** — 접속 안 한 사용자에겐 FCM 푸시. 발신자 중복 렌더링은 Room `except`로 방지.

### 소켓 JWT 인증
```js
io.use((socket, next) => {
  const token = socket.handshake.auth.token;   // 클라가 보낸 user_id는 신뢰하지 않는다
  const decoded = jwt.verify(token, jwt_secret);
  socket.userId = decoded.user_id;             // 토큰에서 추출한 ID만 신뢰
  next();
});
```
