FROM mongo:latest

COPY coordinator/init.sh /init.sh

RUN chmod +x /init.sh

ENTRYPOINT ["/init.sh"]
