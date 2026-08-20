#!/usr/bin/env bash
set -e
set -x

trap "exit 0" 15

GRAFANA_HOST=${GRAFANA_HOST:-"127.0.0.1:3000"}
GRAFANA_PASSWORD=${GRAFANA_PASSWORD:-elite}
GRAFANA_BASE="https://${GRAFANA_HOST}"

register_dashboard() {
    local dashboard='{}'
    local datasource_id=0
    dashboard=$(cat "$1")
    datasource_id=$(curl "$GRAFANA_BASE/api/datasources/name/prometheus" -u "admin:${GRAFANA_PASSWORD}" | jq .uid)
    tmp_dashboard_file=$(mktemp)
    cat <<EOF > "${tmp_dashboard_file}"
{
    "dashboard": $dashboard,
    "overwrite": true,
    "inputs": [
        {
            "name": "DS_PROMETHEUS",
            "type": "datasource",
            "pluginId": "prometheus",
            "value": $datasource_id
        }
    ],
    "folderUid": ""
}
EOF
    curl "$GRAFANA_BASE/api/dashboards/import" \
      -u "admin:${GRAFANA_PASSWORD}" \
      -H 'content-type: application/json' \
      --data  @"${tmp_dashboard_file}"
}

grafana_ready() {
    local n=0
    while [[ $n -lt 10 ]]; do
        # shellcheck disable=SC2068
        if curl -u "admin:${GRAFANA_PASSWORD}" "$GRAFANA_BASE/api/datasources/name/prometheus" &> /dev/null; then
            return 0
        else
            n=$((n + 1))
            sleep 5
        fi
    done
    echo "timeout wait grafana ready"
    exit 1
}

grafana_ready
register_dashboard /etc/elite-exporter-pods-dashboard.json
register_dashboard /etc/elite-exporter-nodes-dashboard.json
sleep infinity
