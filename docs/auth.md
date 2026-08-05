# 🔐 인증 · 보안 (Zero Trust)

"모든 입력은 유죄"라는 전제로, 인증을 개별 기능이 아니라 **여러 계층이 각자 상위를 불신하는 다층 방어(Defense in Depth)** 로 설계했다.

## 핵심 설계
- **자격 증명** — `bcrypt` 비밀번호 해싱, `speakeasy` 기반 **MFA(TOTP)**, 민감정보는 AES-256-CBC로 암호화 저장.
- **토큰 기반 신원** — JWT Access(2h)/Refresh(14d) 분리. 신원은 **클라이언트가 준 ID가 아니라 토큰에서** 결정 (IDOR 방어).
- **역할 분리** — `guest` / `host` 역할을 토큰에 담아, 사장님 모드 전용 API를 `verifyHost`로 차단.
- **다층 방어** — WAF → 스키마 검증 → JWT 소유권 검증 → DB 원자성. 어느 한 층이 뚫려도 다음 층이 막는다.

> 이 "클라이언트 불신 + 정책 레벨 방어" 철학은 [이미지 업로드](./upload.md)·[결제](./reservation-payment.md) 도메인에서도 동일하게 관통한다.
> 상세 → **[Zero Trust — 모든 입력은 유죄라는 방어 설계](https://yeohaenghage.kr/backend/zero_trust_architecture_01/)**
