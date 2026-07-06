FROM mongo:7.0

COPY coordinator/init.sh /init.sh

RUN chmod +x /init.sh

ENTRYPOINT ["/init.sh"]
