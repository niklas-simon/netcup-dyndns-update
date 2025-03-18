FROM alpine

RUN apk add bash curl jq
COPY entrypoint.sh /opt/netcup-dyndns-update/

ENV RECORDS=@,mail \
    INTERVAL=120 \
    LOG_LEVEL=1 \
    DRY_RUN=0

ENTRYPOINT [ "bash", "/opt/netcup-dyndns-update/entrypoint.sh" ]