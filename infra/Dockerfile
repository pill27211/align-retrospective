# Node.js 23 기반 이미지 사용
FROM node:23-alpine

# 작업 디렉토리 설정
WORKDIR /usr/src/app

# 패키지 파일 복사
COPY package*.json ./

# nodemon을 전역으로 설치
RUN npm install -g nodemon

# 의존성 설치 (프로덕션 모드에서도 nodemon을 사용하기 위해 devDependencies를 포함)
RUN npm install --legacy-peer-deps

# 소스 코드 복사
COPY . .

# 로그 디렉토리 생성
RUN mkdir -p /usr/src/app/logging/logs

# 필요한 포트 노출
EXPOSE 60006 60007 60008 9101

# 애플리케이션 실행
CMD ["nodemon", "--exec", "npm", "start"]
