# syntax=docker/dockerfile:1
# AIStudio2API v0.2.18 + 云端补丁（输出前重发）· Render 自建镜像
#
# 设计要点（2026-11-01 定案）：
#   - 二进制不在仓库里（81MB 太大，GitHub 推大文件必 408）
#   - 改为构建时从上游源码编译：拉 v0.2.18 → 打 patches/cloud-patches.diff → CGO+SpiderMonkey 静态编译
#   - 补丁文件仅 7.5KB，随仓库走，永远同步
#   - 用 --platform=$BUILDPLATFORM 让编译在原生 amd64 上跑（Render 是 amd64，无模拟开销）

FROM --platform=$BUILDPLATFORM golang:1.27-bookworm AS build

ARG UPSTREAM_REPO=https://github.com/Mag1cFall/AIStudio2API.git
ARG UPSTREAM_TAG=v0.2.18
ARG ZIG=0.16.0
ARG SPIDERMONKEY=v152.0.4-aistudio2api.1

RUN apt-get update && apt-get install -y --no-install-recommends \
      xz-utils git ca-certificates curl nodejs npm \
    && rm -rf /var/lib/apt/lists/* \
    && node --version && npm --version

# Zig：用 musl 目标静态链接（与上游 CI 一致）
RUN set -eux; \
    curl -fsSL "https://ziglang.org/download/${ZIG}/zig-$(uname -m)-linux-${ZIG}.tar.xz" \
      | tar -xJ -C /opt; \
    mv /opt/zig-* /opt/zig; \
    /opt/zig/zig version

# SpiderMonkey 静态库（WAA 在进程内执行官方 interpreter 所需）
RUN set -eux; \
    mkdir -p /opt/spidermonkey; \
    curl -fsSL "https://github.com/Mag1cFall/firefox/releases/download/${SPIDERMONKEY}/spidermonkey-${SPIDERMONKEY}-linux-amd64.tar.gz" \
      | tar -xz -C /opt/spidermonkey; \
    ls /opt/spidermonkey/lib

WORKDIR /src

# 拉上游指定 tag
RUN git clone --depth 1 --branch "${UPSTREAM_TAG}" "${UPSTREAM_REPO}" . \
    && git log --oneline -1

# 打入云端补丁（输出前重发）
COPY patches/cloud-patches.diff /tmp/cloud-patches.diff
RUN patch -p1 --dry-run < /tmp/cloud-patches.diff \
 && patch -p1 < /tmp/cloud-patches.diff \
 && grep -c "retryBeforeOutput" internal/aistudio/generate.go

# 依赖（GOPROXY 走国内镜像更快，失败回落官方）
ENV GOPROXY=https://goproxy.cn,https://proxy.golang.org,direct \
    GOSUMDB=off \
    GOFLAGS=-mod=readonly

RUN go mod download

# 前端产物：上游仓库不含 internal/webui/dist（//go:embed），必须自己构建
RUN set -eux; \
    cd web && npm ci --no-audit --no-fund && npx vp build; \
    test -f internal/webui/dist/index.html

RUN set -eux; \
    CGO_ENABLED=1 GOOS=linux GOARCH=amd64 \
    CC="/opt/zig/zig cc -target x86_64-linux-musl" \
    CXX="/opt/zig/zig c++ -target x86_64-linux-musl" \
    CGO_CXXFLAGS=-I/opt/spidermonkey/include \
    CGO_LDFLAGS=-L/opt/spidermonkey/lib \
    go build -trimpath -tags netgo,osusergo \
      -ldflags="-s -w -linkmode external -extldflags '-static -Wl,--strip-all'" \
      -o /out/aistudio2api ./cmd/aistudio2api; \
    file /out/aistudio2api

# ---------- 运行时镜像 ----------
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata curl

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
RUN chmod 0755 /usr/local/bin/entrypoint.sh /app/aistudio2api

ENV TZ=Asia/Singapore \
    LISTEN_ADDR=0.0.0.0:10000 \
    AISTUDIO_AUTH_STATES=auth

WORKDIR /var/data
EXPOSE 10000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/app/aistudio2api", "-open-ui=false"]
