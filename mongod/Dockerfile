FROM mongo:7.0

EXPOSE 27017

COPY mongod.conf /etc/mongod.conf
COPY entrypoint.sh /mongo-entrypoint.sh
RUN chmod +x /mongo-entrypoint.sh

ENTRYPOINT ["/mongo-entrypoint.sh"]
