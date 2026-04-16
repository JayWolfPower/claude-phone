FROM kamailio/kamailio:5.8-bullseye

# Add sqlite3 CLI (for DB init) and kamctl/kamdbctl tools
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        sqlite3 \
        kamailio-utils-cfg \
    && rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /docker-entrypoint.sh
RUN chmod +x /docker-entrypoint.sh

ENTRYPOINT ["/docker-entrypoint.sh"]
