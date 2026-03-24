# =============================================================================
# 멀티스테이지 빌드 Dockerfile
#
# 멀티스테이지 빌드의 핵심:
# - Stage 1 (빌드): Node.js로 React 앱을 빌드한다 (~1GB)
# - Stage 2 (실행): Nginx로 빌드 결과물만 서빙한다 (~30MB)
# 빌드 도구(node_modules 등)는 최종 이미지에 포함되지 않는다 → 이미지 크기 감소
#
# 보안 고려사항:
# - non-root 사용자로 실행 (nginx 사용자)
# - 불필요한 패키지 미설치
# - .dockerignore로 소스코드/node_modules 제외
#
# 빌드:
#   docker build -t dashboard:dev .
#
# 실행:
#   docker run -p 8080:80 dashboard:dev
#   브라우저에서 http://localhost:8080 접속
#
# Trivy 스캔:
#   trivy image dashboard:dev
# =============================================================================

# ─── Stage 1: 빌드 ──────────────────────────────────────────────────────────
FROM node:22-alpine AS build

# 작업 디렉토리 설정
WORKDIR /app

# 의존성 파일만 먼저 복사 (Docker 레이어 캐시 활용)
# package.json이 변경되지 않으면 npm ci를 다시 실행하지 않는다
COPY package.json package-lock.json ./
RUN npm ci --production=false

# 소스 복사 후 빌드
COPY . .
RUN npm run build

# ─── Stage 2: 실행 ──────────────────────────────────────────────────────────
FROM nginx:1.27-alpine

# Nginx 설정 복사
COPY nginx.conf /etc/nginx/conf.d/default.conf

# 빌드 결과물만 복사 (node_modules, src 등은 포함되지 않음)
COPY --from=build /app/dist /usr/share/nginx/html

# non-root 실행을 위한 디렉토리 권한 설정
# K8s에서 runAsUser: 101 (nginx)로 실행할 때 필요하다
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    mkdir -p /var/cache/nginx/client_temp \
             /var/cache/nginx/proxy_temp \
             /var/cache/nginx/fastcgi_temp \
             /var/cache/nginx/uwsgi_temp \
             /var/cache/nginx/scgi_temp && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /run/nginx.pid && chown nginx:nginx /run/nginx.pid

# non-root 사용자로 전환 (nginx 사용자 = UID 101)
USER nginx

# 8080 포트 노출 (non-root는 1024 이하 포트를 바인드할 수 없다)
EXPOSE 8080

# Nginx를 포그라운드에서 실행 (PID 1)
CMD ["nginx", "-g", "daemon off;"]
