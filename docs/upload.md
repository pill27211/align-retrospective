# 🖼️ 이미지 업로드 (Presigned URL · 서버 우회)

파일이 서버를 경유하던 방식을 **Presigned URL 방식**으로 전환해, 클라이언트가 S3로 직접 업로드하도록 바꿨다. 이 전환이 upload-server를 [legacy로 만든](../README.md#3-서버-구성--왜-하나가-아니라-넷인가) 배경이다.

## 핵심 설계
- **서버는 URL만 발급** — 실제 파일은 클라이언트가 S3로 직접 업로드 → 서버 대역폭·CPU 부담 제거.
- **정책 레벨 강제** — 발급 시 제약을 걸어 **클라이언트를 신뢰하지 않고 S3가 위반 업로드를 거부**하게 함 (용량 상한 · 파일 타입 · 짧은 서명 수명).
- **클라이언트 이분 탐색 압축** — 용량 상한에 맞춰 최적 압축률로 업로드.
- **사후처리 API** — 업로드 완료 후 별도 API로 DB 반영/후속 이벤트 트리거 (2단계 커밋 형태).

### Presigned POST 발급
```js
const params = {
  Bucket: S3_BUCKET_NAME,
  Fields: { key: s3_key, 'Content-Type': 'image/' + ext },
  Expires: 120,                                 // 서명 수명 2분
  Conditions: [
    ['content-length-range', 0, 756800],        // 용량 상한(≈740KB) → 큰 파일 원천 차단
    ['starts-with', '$Content-Type', 'image/'], // 이미지 타입만 허용
  ],
};
s3.createPresignedPost(params, (err, data) => { /* upload_url + fields 를 클라에 반환 */ });
```

> 이 "클라이언트 불신 + 정책 레벨 방어"는 [Zero Trust 설계](./auth.md)와 같은 철학이다.
