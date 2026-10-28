# Monitoring configuration

The Prometheus, alert rule, Grafana and systemd files deployed in milestone 3b. The drill and what it showed are in [../docs/monitoring.md](../docs/monitoring.md).

| File | Goes to | On |
|---|---|---|
| `../scripts/gluster-metrics.sh` | `/usr/local/bin/gluster-metrics.sh` | each server |
| `systemd/node_exporter.service` | `/etc/systemd/system/` | each server |
| `systemd/gluster-metrics.service`, `systemd/gluster-metrics.timer` | `/etc/systemd/system/` | each server |
| `prometheus/prometheus.yml`, `prometheus/rules/gluster.yml` | `/opt/monitoring/prometheus/` | gluster4 |
| `grafana/provisioning/...` | `/opt/monitoring/grafana/provisioning/` | gluster4 |
| `grafana/dashboards/gluster-gv0.json` | `/opt/monitoring/grafana/dashboards/` | gluster4 |

On each server, after `node_exporter` 1.8.2 (linux-arm64) is installed in `/usr/local/bin`, a `node_exporter` system user exists, and `/var/lib/node_exporter/textfile` is created:

```bash
systemctl daemon-reload
systemctl enable --now node_exporter gluster-metrics.timer
firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<gluster4 address>" port port="9100" protocol="tcp" accept'
firewall-cmd --reload
```

On `gluster4`:

```bash
podman run --rm -v /opt/monitoring/prometheus:/etc/prometheus:Z --entrypoint promtool docker.io/prom/prometheus:v2.53.2 check config /etc/prometheus/prometheus.yml
podman run -d --name prometheus --network host --restart=always \
  -v /opt/monitoring/prometheus:/etc/prometheus:Z -v prometheus-data:/prometheus \
  docker.io/prom/prometheus:v2.53.2 --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/prometheus
read -rsp 'Grafana admin password: ' GF_PW; echo
podman run -d --name grafana --network host --restart=always -e GF_SECURITY_ADMIN_PASSWORD="$GF_PW" \
  -v /opt/monitoring/grafana/provisioning:/etc/grafana/provisioning:Z \
  -v /opt/monitoring/grafana/dashboards:/var/lib/grafana/dashboards:Z -v grafana-data:/var/lib/grafana \
  docker.io/grafana/grafana-oss:11.2.0
unset GF_PW
systemctl enable --now podman-restart.service
firewall-cmd --permanent --add-port=9090/tcp --add-port=3000/tcp && firewall-cmd --reload
```
