FROM alpine:latest

RUN apk add --no-cache \
    wireguard-tools \
    iptables \
    ip6tables \
    nftables \
    iproute2 \
    tcpdump \
    iputils \
    bash \
    curl

RUN mkdir -p /entrypoints /etc/wireguard

COPY r1-entrypoint.sh /entrypoints/r1-entrypoint.sh
COPY r2-entrypoint.sh /entrypoints/r2-entrypoint.sh
RUN chmod +x /entrypoints/r1-entrypoint.sh /entrypoints/r2-entrypoint.sh

CMD ["sleep", "infinity"]
