FROM alpine:3.21 AS builder

RUN apk add --no-cache curl jq bc bash

COPY hetzner-speedtest.sh /opt/hetzner-speedtest/hetzner-speedtest.sh
COPY hosts.json /opt/hetzner-speedtest/hosts.json

RUN chmod +x /opt/hetzner-speedtest/hetzner-speedtest.sh

FROM alpine:3.21

RUN apk add --no-cache --upgrade curl jq bc bash && \
    adduser -D -h /opt/hetzner-speedtest -s /bin/bash speedtest

COPY --from=builder /opt/hetzner-speedtest /opt/hetzner-speedtest

USER speedtest
WORKDIR /opt/hetzner-speedtest

ENTRYPOINT ["/opt/hetzner-speedtest/hetzner-speedtest.sh"]
