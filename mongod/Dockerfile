FROM mongo:latest

EXPOSE 27017

COPY mongod.conf /etc/mongod.conf
COPY entrypoint.sh /mongo-entrypoint.sh
RUN chmod +x /mongo-entrypoint.sh

ENTRYPOINT ["/mongo-entrypoint.sh"]
