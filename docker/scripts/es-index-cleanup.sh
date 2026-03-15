#!/bin/bash
# Elasticsearch index cleanup - safety net for ILM
# Deletes old logstash indices based on retention days per type
# Runs daily via cron

set -euo pipefail

ES_HOST="localhost"
ES_PORT="9200"
ES_URL="http://${ES_HOST}:${ES_PORT}"
DOCKER_ES="docker compose -f /opt/selksd/SELKS/docker/docker-compose.yml exec -T elasticsearch"
LOG="/var/log/es-index-cleanup.log"

# Retention in days per event type
HEAVY_RETENTION=3   # flow, snmp, dns, sip
ALERT_RETENTION=7   # alert
LIGHT_RETENTION=5   # ike, anomaly, quic, tftp, krb5, dhcp, etc.

HEAVY_TYPES="flow snmp dns sip"
ALERT_TYPES="alert"
LIGHT_TYPES="ike anomaly quic tftp krb5 dhcp"

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $1" | tee -a "$LOG"
}

delete_old_indices() {
    local event_type="$1"
    local retention_days="$2"
    local cutoff_date
    cutoff_date=$(date -d "-${retention_days} days" '+%Y.%m.%d')

    # Get all indices for this event type
    local indices
    indices=$($DOCKER_ES curl -s "http://localhost:9200/_cat/indices/logstash-${event_type}-*?h=index" 2>/dev/null | tr -d '[:space:]' | tr '\n' ' ')

    for index in $indices; do
        # Extract date from index name (format: logstash-TYPE-YYYY.MM.DD)
        local index_date
        index_date=$(echo "$index" | grep -oP '\d{4}\.\d{2}\.\d{2}$' || true)
        if [[ -z "$index_date" ]]; then
            continue
        fi

        if [[ "$index_date" < "$cutoff_date" ]]; then
            log "DELETING $index (date: $index_date, cutoff: $cutoff_date, retention: ${retention_days}d)"
            $DOCKER_ES curl -s -X DELETE "http://localhost:9200/${index}" 2>/dev/null | tee -a "$LOG"
            echo "" >> "$LOG"
        fi
    done
}

log "=== Starting ES index cleanup ==="

# Check ES is reachable
if ! $DOCKER_ES curl -s "http://localhost:9200/_cluster/health" >/dev/null 2>&1; then
    log "ERROR: Elasticsearch not reachable, aborting"
    exit 1
fi

# Report disk usage before
DISK_BEFORE=$(df -h / | awk 'NR==2{print $5}')
log "Disk usage before: $DISK_BEFORE"

# Delete heavy types
for t in $HEAVY_TYPES; do
    delete_old_indices "$t" "$HEAVY_RETENTION"
done

# Delete alert types
for t in $ALERT_TYPES; do
    delete_old_indices "$t" "$ALERT_RETENTION"
done

# Delete light types
for t in $LIGHT_TYPES; do
    delete_old_indices "$t" "$LIGHT_RETENTION"
done

# Also clean any unmatched logstash-YYYY.MM.dd (stats) indices older than 3 days
cutoff=$(date -d "-3 days" '+%Y.%m.%d')
for index in $($DOCKER_ES curl -s "http://localhost:9200/_cat/indices/logstash-2*?h=index" 2>/dev/null | tr -d '[:space:]'); do
    index_date=$(echo "$index" | grep -oP '\d{4}\.\d{2}\.\d{2}$' || true)
    if [[ -n "$index_date" && "$index_date" < "$cutoff" ]]; then
        log "DELETING stats index $index"
        $DOCKER_ES curl -s -X DELETE "http://localhost:9200/${index}" 2>/dev/null | tee -a "$LOG"
        echo "" >> "$LOG"
    fi
done

# Report disk usage after
DISK_AFTER=$(df -h / | awk 'NR==2{print $5}')
log "Disk usage after: $DISK_AFTER"
log "=== Cleanup complete ==="
