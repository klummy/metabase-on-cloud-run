#! /bin/bash

# By default, the Java Postgres driver does not support Unix sockets
# Forward TCP:5432 to Cloud SQL Unix socket
nohup socat -d -d TCP4-LISTEN:5432,fork UNIX-CONNECT:pg.sock &

# Runs Metabase
/app/run_metabase.sh