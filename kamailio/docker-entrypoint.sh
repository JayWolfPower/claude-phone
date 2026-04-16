#!/bin/bash
# Kamailio Docker entrypoint
# - Detects architecture for module path
# - Creates kamailio-local.cfg from environment variables
# - Initializes SQLite subscriber DB if it doesn't exist
# - Starts Kamailio

set -e

DB_PATH="/etc/kamailio/subscriber.db"

# ---------------------------------------------------------------------------
# 1. Write kamctlrc so kamctl/kamdbctl know which DB to use
# ---------------------------------------------------------------------------
cat > /etc/kamailio/kamctlrc << EOF
DBENGINE=SQLITE
DBPATH=${DB_PATH}
SIP_DOMAIN=${SIP_DOMAIN:-pbx.local}
EOF

# ---------------------------------------------------------------------------
# 2. Initialise subscriber DB if missing or empty
#    kamdbctl create writes the full Kamailio schema (subscriber + location
#    tables, etc.) to the SQLite file.
# ---------------------------------------------------------------------------
if [ ! -s "${DB_PATH}" ]; then
    echo "[KAMAILIO] Initializing subscriber database at ${DB_PATH}..."
    echo "y" | kamdbctl create 2>/dev/null || {
        # Fallback: create minimal tables directly with sqlite3
        echo "[KAMAILIO] kamdbctl not available, creating schema with sqlite3..."
        sqlite3 "${DB_PATH}" << 'SQL'
CREATE TABLE IF NOT EXISTS subscriber (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    username    TEXT    NOT NULL DEFAULT '',
    domain      TEXT    NOT NULL DEFAULT '',
    password    TEXT    NOT NULL DEFAULT '',
    email_address TEXT  NOT NULL DEFAULT '',
    ha1         TEXT    NOT NULL DEFAULT '',
    ha1b        TEXT    NOT NULL DEFAULT '',
    rpid        TEXT    DEFAULT NULL,
    UNIQUE (username, domain)
);
CREATE TABLE IF NOT EXISTS location (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    ruid            TEXT    NOT NULL DEFAULT '',
    username        TEXT    NOT NULL DEFAULT '',
    domain          TEXT    DEFAULT NULL,
    contact         TEXT    NOT NULL DEFAULT '',
    received        TEXT    DEFAULT NULL,
    path            TEXT    DEFAULT NULL,
    expires         DATETIME NOT NULL DEFAULT '2030-05-28 21:32:15',
    q               REAL    NOT NULL DEFAULT 1.0,
    callid          TEXT    NOT NULL DEFAULT 'Default-Call-ID',
    cseq            INTEGER NOT NULL DEFAULT 1,
    last_modified   DATETIME NOT NULL DEFAULT '2000-01-01 00:00:01',
    flags           INTEGER NOT NULL DEFAULT 0,
    cflags          INTEGER NOT NULL DEFAULT 0,
    user_agent      TEXT    NOT NULL DEFAULT '',
    socket          TEXT    DEFAULT NULL,
    methods         INTEGER DEFAULT NULL,
    instance        TEXT    DEFAULT NULL,
    reg_id          INTEGER NOT NULL DEFAULT 0,
    server_id       INTEGER NOT NULL DEFAULT 0,
    connection_id   INTEGER NOT NULL DEFAULT 0,
    keepalive       INTEGER NOT NULL DEFAULT 0,
    partition       INTEGER NOT NULL DEFAULT 0
);
SQL
    }
    echo "[KAMAILIO] Database ready."
    echo "[KAMAILIO] Add SIP users with:  docker compose exec kamailio kamctl add <user> <password>"
fi

# ---------------------------------------------------------------------------
# 3. Detect architecture → correct Kamailio module path
# ---------------------------------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
    x86_64)  MPATH="/usr/lib/x86_64-linux-gnu/kamailio/modules/" ;;
    aarch64) MPATH="/usr/lib/aarch64-linux-gnu/kamailio/modules/" ;;
    armv7l)  MPATH="/usr/lib/arm-linux-gnueabihf/kamailio/modules/" ;;
    *)       MPATH="/usr/lib/kamailio/modules/" ;;
esac

# ---------------------------------------------------------------------------
# 4. Generate kamailio-local.cfg from env vars
#    Values are written WITHOUT surrounding quotes so they can be placed
#    inside quoted strings in kamailio.cfg:
#      mpath="KAM_MPATH"  →  mpath="/usr/lib/x86_64-.../modules/"
# ---------------------------------------------------------------------------
mkdir -p "$(dirname /etc/kamailio/kamailio-local.cfg)"
cat > /etc/kamailio/kamailio-local.cfg << EOF
#!define EXTERNAL_IP    ${EXTERNAL_IP:-127.0.0.1}
#!define SIP_DOMAIN     ${SIP_DOMAIN:-pbx.local}
#!define KAM_REALM      ${KAM_REALM:-${SIP_DOMAIN:-pbx.local}}
#!define DRACHTIO_ADDR  127.0.0.1:5070
#!define AI_EXT_REGEX   ^9[0-9]{3}$
#!define KAM_MPATH      ${MPATH}
EOF

echo "[KAMAILIO] Starting — domain: ${SIP_DOMAIN:-pbx.local}, external IP: ${EXTERNAL_IP:-127.0.0.1}"

# ---------------------------------------------------------------------------
# 5. Start Kamailio
#    -DD = fork and run as daemon (Docker captures stdout via -E)
#    -E  = log to stderr (visible in docker compose logs)
# ---------------------------------------------------------------------------
exec kamailio -f /etc/kamailio/kamailio.cfg -DD -E
