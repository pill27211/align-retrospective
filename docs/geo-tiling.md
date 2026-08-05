# 🗺️ 지도 기반 숙소 탐색 (Geo-Tiling)

지도 뷰포트를 움직일 때마다 전체 숙소를 훑으면 비용이 크다. 한반도를 격자로 나눠 **주변 타일만 조회**하는 저비용 공간 인덱스를 Redis Set으로 구현했다.

## 핵심 설계
- 한반도 영역을 **60×43 = 2,580개 타일**로 분할하고, 각 타일에 속한 숙소 ID를 **Redis Set**(`tile:{n}:houses`)으로 인덱싱.
- 위/경도 → 타일 번호를 **O(1) 산술**로 계산 → 뷰포트 이동 시 주변 타일만 조회.
- 숙소 추가/삭제 시 해당 타일 Set만 갱신해 인덱스를 증분 유지.

### 좌표 → 타일 번호
```js
// 위/경도를 격자 인덱스로 환산 (O(1))
const row = Math.floor((NORTH_WEST.lat - lat) / DELTA_LAT);
const col = Math.floor((lng - NORTH_WEST.lng) / DELTA_LON);
if (row < 0 || row >= ROWS || col < 0 || col >= COLS) return null; // 범위 밖
return row * COLS + col + 1;   // → Redis: SADD tile:{n}:houses {houseId}
```
