# WordPress Operations dashboard

The dashboard uses the existing Loki datasource (`uid: loki`) and the node2
Promtail stream (`job="docker-node2", container="yukis-wordpress"`). It shows
successful and denied logins, failed REST writes (including block-editor save
failures), PHP errors, HTTP 5xx responses, request volume, and recent log lines.

The WordPress must-use plugin at `../mu-plugins/yukis-observability.php` emits
the login and failed-write events into the WordPress container log. The node2
Promtail config already ships that log to Loki. It does not log passwords,
attempted usernames, request bodies, or error messages.

To install the dashboard on the Grafana host, copy
`dashboards/wordpress-operations.json` into the directory mounted as
`/var/lib/grafana/dashboards` (the observability repository uses
`grafana/dashboards/`). Its file provider checks for changes every 30 seconds.
For the Git repository at `/opt/observability`, the host commands are:

```sh
cp /opt/wordpress/grafana/dashboards/wordpress-operations.json \
  /opt/observability/grafana/dashboards/wordpress-operations.json
git -C /opt/observability add grafana/dashboards/wordpress-operations.json
git -C /opt/observability commit -m "Add WordPress operations dashboard"
git -C /opt/observability push origin main
```

The dashboard starts showing new login and write-failure events after the
plugin is mounted into a running WordPress container. It does not reconstruct
past events. HTTP and PHP log panels can show earlier retained logs.
