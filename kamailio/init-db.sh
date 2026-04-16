#!/bin/bash
# ===========================================================================
# init-db.sh — Add SIP users to the Kamailio subscriber database
#
# Run this after `docker compose up -d` to register softphone credentials.
# Each user added here can register a softphone (Linphone, Zoiper, Bria, etc.)
# against your Kamailio server and place/receive calls.
#
# Usage:
#   ./kamailio/init-db.sh <username> <password>
#
# Example:
#   ./kamailio/init-db.sh alice secretpass
#   ./kamailio/init-db.sh bob   anotherpass
# ===========================================================================

set -e

# Load .env so we know SIP_DOMAIN and EXTERNAL_IP
if [ -f "$(dirname "$0")/../.env" ]; then
    # shellcheck disable=SC1091
    source "$(dirname "$0")/../.env"
fi

USERNAME="$1"
PASSWORD="$2"
DOMAIN="${SIP_DOMAIN:-pbx.local}"
EXT_IP="${EXTERNAL_IP:-<your-server-ip>}"

if [ -z "$USERNAME" ] || [ -z "$PASSWORD" ]; then
    echo "Usage: $0 <username> <password>"
    echo ""
    echo "Adds a SIP user to the Kamailio subscriber database."
    echo ""
    echo "Examples:"
    echo "  $0 alice    secretpass"
    echo "  $0 bob      anotherpass"
    echo ""
    echo "Then configure your softphone (Linphone, Zoiper, Bria) with:"
    echo "  SIP server:  ${EXT_IP}:5060"
    echo "  Username:    <user>"
    echo "  Password:    <password>"
    echo "  Domain:      ${DOMAIN}"
    exit 1
fi

# Kamailio container must be running
if ! docker compose ps kamailio | grep -q "running\|Up"; then
    echo "ERROR: Kamailio container is not running."
    echo "Start it first with: docker compose up -d kamailio"
    exit 1
fi

echo "Adding SIP user: ${USERNAME}@${DOMAIN}"
docker compose exec kamailio kamctl add "${USERNAME}@${DOMAIN}" "${PASSWORD}"

echo ""
echo "Done! Configure your softphone with:"
echo "  SIP server:  ${EXT_IP}:5060"
echo "  Username:    ${USERNAME}"
echo "  Password:    ${PASSWORD}"
echo "  Domain:      ${DOMAIN}"
echo ""
echo "To verify registration after connecting the softphone:"
echo "  docker compose exec kamailio kamctl ul show"
