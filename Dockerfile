# syntax=docker/dockerfile:1
# AIStudio2API v0.2.14（cloud-patches 版）+ cloudflared 出站隧道
# 二进制走「校验后解压」，避免把 49MB 裸文件塞进 Git
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata curl

# cloudflared 版本基线 ≥2026.10.2（eMudhra 中间证书事件后 CF 强制），此处钉 2026.10.7 + sha256
ARG CLOUDFLARED_VERSION=2026.10.7
ARG CLOUDFLARED_SHA256=1f99fb518b83dec2ba8d870a7cc991d82a77e6196295a3d2754ba17ab9f91872
RUN set -eux; \
    curl -fsSL -o /usr/local/bin/cloudflared \
      "https://github.com/cloudflare/cloudflared/releases/download/${CLOUDFLARED_VERSION}/cloudflared-linux-amd64"; \
    echo "${CLOUDFLARED_SHA256}  /usr/local/bin/cloudflared" | sha256sum -c -; \
    chmod 0755 /usr/local/bin/cloudflared; \
    cloudflared --version

ENV TZ=Asia/Singapore \
    LISTEN_ADDR=0.0.0.0:10000 \
    AISTUDIO_AUTH_STATES=auth

WORKDIR /app
COPY artifacts/aistudio2api-linux-amd64-v0214-cloud-patches.gz /tmp/a2a.gz
RUN echo "8bed5f9e55771ed2f1133070efee663eafff3e39205e64b516fede3b737b331f  /tmp/a2a.gz" | sha256sum -c - \
 && gunzip -c /tmp/a2a.gz > /app/aistudio2api \
 && chmod 0755 /app/aistudio2api \
 && rm -f /tmp/a2a.gz

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 0755 /usr/local/bin/entrypoint.sh

# 运行时状态（.env / auth / runtime）全部落在持久盘 /var/data
WORKDIR /var/data
EXPOSE 10000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/app/aistudio2api", "-open-ui=false"]
