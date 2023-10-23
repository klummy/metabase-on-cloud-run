FROM metabase/metabase:v0.47.4

RUN apk update
RUN apk add --no-cache socat

# Set up symlink to Cloud SQL UNIX socket
# TODO: Replace <db-connection-name> with your Cloud SQL connection name
RUN ln -s /cloudsql/<db-connection-name>/.s.PGSQL.5432 pg.sock

COPY startup.sh startup.sh
RUN chmod +x startup.sh
ENTRYPOINT ["./startup.sh"]
