# syntax=docker/dockerfile:1
# AIStudio2API v0.2.19 + 云端补丁（输出前重发 + 换行归一化）· Render 自建镜像
#
# 设计要点（2026-11-01 定案）：
#   - 二进制不在仓库里（81MB 太大，GitHub 推大文件必 408）
#   - 改为构建时从上游源码编译：拉 v0.2.19 → 打 patches/cloud-patches.diff → CGO+SpiderMonkey 静态编译
#   - 补丁文件仅 14KB（文本），随仓库走，永远同步
#   - 用 --platform=$BUILDPLATFORM 让编译在原生 amd64 上跑（Render 是 amd64，无模拟开销）

# ---------- 阶段 1：编译底座 + 上游源码 + 云端补丁 ----------
FROM --platform=$BUILDPLATFORM golang:1.27-bookworm AS src

ARG UPSTREAM_REPO=https://github.com/Mag1cFall/AIStudio2API.git
ARG UPSTREAM_TAG=v0.2.19
ARG SPIDERMONKEY=v152.0.4-aistudio2api.1

# SpiderMonkey 静态库（使用 linux-amd64-gnu 配合 bookworm 原生 gcc/g++，避免 Zig 编译 libcxx 在 2GB 构建容器 OOM）
RUN set -eux; \
    mkdir -p /opt/spidermonkey; \
    curl -fsSL "https://github.com/Mag1cFall/firefox/releases/download/${SPIDERMONKEY}/spidermonkey-${SPIDERMONKEY}-linux-amd64-gnu.tar.gz" \
      | tar -xz --no-same-owner -C /opt/spidermonkey; \
    ls /opt/spidermonkey/lib

WORKDIR /src

# 拉上游指定 tag
RUN git clone --depth 1 --branch "${UPSTREAM_TAG}" "${UPSTREAM_REPO}" . \
    && git log --oneline -1

# 打入云端补丁：输出前重发 + CRLF 全链路归一化（补丁不落地即构建失败，别让它悄悄跳过）
COPY patches/cloud-patches.diff /tmp/cloud-patches.diff
RUN git apply --check /tmp/cloud-patches.diff \
 && git apply /tmp/cloud-patches.diff \
 && grep -c "retryBeforeOutput" internal/aistudio/generate.go \
 && grep -c "normalizePromptLineEndings" internal/aistudio/service.go

# ---------- 阶段 2：前端产物（独立 Node 22 阶段，与上游 Dockerfile 一致） ----------
FROM --platform=$BUILDPLATFORM node:22-bookworm-slim AS web
WORKDIR /src/web
COPY --from=src /src/web/package.json /src/web/package-lock.json ./
RUN npm ci --no-audit --no-fund
COPY --from=src /src/web/ ./
RUN npx vp build && test -f /src/internal/webui/dist/index.html

# ---------- 阶段 3：CGO + SpiderMonkey 编译（与上游 CI checks job 一致） ----------
FROM src AS build

# 依赖（GOPROXY 走国内镜像更快，失败回落官方）
ENV GOPROXY=https://goproxy.cn,https://proxy.golang.org,direct \
    GOSUMDB=off \
    GOFLAGS=-mod=readonly

RUN go mod download

# 前端产物：上游仓库不含 internal/webui/dist（//go:embed），必须自己构建
COPY --from=web /src/internal/webui/dist internal/webui/dist
RUN test -f internal/webui/dist/index.html

RUN set -eux; \
    printf '#include <stdlib.h>\n#include <stdio.h>\n#include <stdarg.h>\nlong __isoc23_strtol(const char *s, char **e, int b){return strtol(s,e,b);}\nunsigned long __isoc23_strtoul(const char *s, char **e, int b){return strtoul(s,e,b);}\nlong long __isoc23_strtoll(const char *s, char **e, int b){return strtoll(s,e,b);}\nunsigned long long __isoc23_strtoull(const char *s, char **e, int b){return strtoull(s,e,b);}\nint __isoc23_sscanf(const char *s, const char *f, ...){va_list a;va_start(a,f);int r=vsscanf(s,f,a);va_end(a);return r;}\n' > /tmp/isoc23.c; \
    gcc -O2 -c /tmp/isoc23.c -o /tmp/isoc23.o; \
    ar rcs /opt/spidermonkey/lib/libjs_static.a /tmp/isoc23.o; \
    ar rcs /opt/spidermonkey/lib/libjsrust.a /tmp/isoc23.o; \
    VERSION="$(git describe --tags --exact-match 2>/dev/null || git rev-parse --short HEAD)"; \
    CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    CGO_CXXFLAGS=-I/opt/spidermonkey/include \
    CGO_LDFLAGS=-L/opt/spidermonkey/lib \
    go build -p 2 -trimpath \
      -ldflags="-s -w -X github.com/Mag1cFall/AIStudio2API/internal/app.version=${VERSION}-cloud -X github.com/Mag1cFall/AIStudio2API/internal/app.managedBy=render-docker" \
      -o /out/aistudio2api ./cmd/aistudio2api; \
    ls -lh /out/aistudio2api; \
    grep -a -c "render-docker" /out/aistudio2api

# ---------- 运行时镜像（与上游 Dockerfile 一致用 debian:bookworm-slim） ----------
FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates tzdata curl \
    && rm -rf /var/lib/apt/lists/*

# cloudflared 基线 ≥2026.10.2（eMudhra 中间证书事件后 CF 强制），钉 2026.10.7 + sha256
ARG CLOUDFLARED_VERSION=2026.10.7
ARG CLOUDFLARED_SHA256=1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64"; \
    echo "${CLOUDFLARED_SHA256}  /usr/local/bin/cloudflared" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/cloudflared; \
    cloudflared --version

COPY --from=build /out/aistudio2api /app/aistudio2api
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh /app/aistudio2api \
    && /app/aistudio2api --help | head -n 5

ENV TZ=Asia/Singapore \
    LISTEN_ADDR=0.0.0.0:10000 \
    AISTUDIO_AUTH_STATES=auth

WORKDIR /var/data
EXPOSE 10000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/app/aistudio2api", "-open-ui=false"]
