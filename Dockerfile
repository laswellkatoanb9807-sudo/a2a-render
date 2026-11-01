# syntax=docker/dockerfile:1
# AIStudio2API v0.2.14（cloud-patches 版）Render 镜像
# 校验后解压，避免把 49MB 裸二进制塞进 Git；gz 哈希与 lifecycle 档案 §4 台账一致
FROM alpine:3.20

RUN apk add --no-cache ca-certificates tzdata curl

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
