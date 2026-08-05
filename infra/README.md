# 🏗️ 인프라 구성

시크릿(자격증명·키·실 도메인/IP)을 제거한 인프라 설정 발췌본입니다.

| 파일 | 역할 |
|------|------|
| `docker-compose.infra.yml` | 상태 계층 — Redis(Valkey) · MySQL 8 · Nginx |
| `docker-compose.apps.yml` | 앱 서버 — main ×2 · message ×2 · upload · worker |
| `Dockerfile` | Node 앱 이미지 |
| `nginx.sample.conf` | 리버스 프록시 · TLS · LB · WebSocket 업그레이드 · 점검 모드 |
| `prometheus.yml` | 메트릭 스크레이프 + `relabel_configs` |
| `log_watcher.sample.sh` | 에러 로그 → Discord 웹훅 알림 |

## ⚙️ 개발 / 운영 실행 분리

실제 프로젝트의 `package.json`은 실행 스크립트를 목적별로 나눠 두었습니다.

- **개발**: `npm run dev:*` → `nodemon`(핫리로드)
- **운영**: `npm run start:*` → `node`

> ⚠️ 이 저장소의 **`docker-compose.apps.yml`은 로컬 개발용** 오케스트레이션입니다 — 소스 볼륨 마운트(`.:/usr/src/app`)와 `nodemon` 핫리로드를 사용합니다.
> **운영 배포**는 빌드된 이미지에서 소스 볼륨 없이 `npm run start`(= `node`)로 실행하는 구성이 올바릅니다. 실제 프로젝트에서 이 분리가 느슨했던 점은 [회고](../README.md#8-회고--잘한-점--아쉬운-점--배운-점)에 기록했습니다.
