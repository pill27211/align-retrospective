# 📊 관측성 (Observability)

모놀리식에서 분산 시스템으로 커지며 "안 보이면 못 고친다"를 절감하고, **메트릭 · 추적 · 로그 알림** 3층을 구축했다.

## 3계층
- **Metrics** — `prom-client` 커스텀 메트릭(HTTP 지연 히스토그램, 소켓 접속자 Gauge, 메시지 전송 Counter)을 Prometheus가 수집, Grafana로 시각화. `relabel_configs`로 `gh-server-main-server-1` 같은 컨테이너명을 **"서버 1"** 로 가독화.
- **Tracing** — OpenTelemetry **무침습 자동 계측**을 부팅 시점에 주입 → Express/MySQL/MongoDB/Redis 스팬을 **코드 수정 없이** 수집, Jaeger로 전송.
- **Logging/Alerting** — 에러 로그를 감시해 **Discord 웹훅으로 실시간 알림**(중복 방지 락 포함)하는 경량 Bash 워처.

### 무침습 자동 계측
```js
// node --require ./tracing.js 로 부팅 시 주입 → 비즈니스 코드에 손대지 않고 스팬 수집
const sdk = new NodeSDK({
  traceExporter: new OTLPTraceExporter({ url: process.env.OTLP_ENDPOINT }),
  instrumentations: [getNodeAutoInstrumentations()], // Express/MySQL/Mongo/Redis/HTTP 자동 계측
});
sdk.start();
```

> 상세 → **[분산 시스템 관측성(Observability) 스택 구축기](https://yeohaenghage.kr/backend/monitoring/)**
