# Security Notes

> Owner: Person A

---

## File Permissions

All config files containing credentials must be mode 640 (owner read/write, group read, no world access).

```bash
# Apply correct permissions after installation:
sudo chmod 640 /etc/prometheus/prometheus.yml
sudo chmod 640 /etc/alertmanager/alertmanager.yml
sudo chmod 640 /etc/grafana/grafana.ini

# Verify:
ls -la /etc/prometheus/prometheus.yml
ls -la /etc/alertmanager/alertmanager.yml
```

---

## Credential Storage

SMTP credentials and other secrets must never be committed to the repository.

Use `.env` file on the server (excluded by `.gitignore`):
```bash
# /etc/alertmanager/.env (not in repo)
ALERTMANAGER_SMTP_PASSWORD=your_16_char_app_password
```

See `.env.example` in the repo root for the required variable names.

---

## Nginx Reverse Proxy (Optional)

If the monitoring VM is shared, add HTTP basic auth via nginx:

```bash
sudo apt-get install -y nginx apache2-utils

# Create password file:
sudo htpasswd -c /etc/nginx/.htpasswd monitoring-admin

# Create nginx site config:
sudo tee /etc/nginx/sites-available/prometheus <<'EOF'
server {
    listen 80;
    server_name _;

    location /prometheus/ {
        proxy_pass http://localhost:9090/;
        auth_basic "Prometheus";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }

    location /alertmanager/ {
        proxy_pass http://localhost:9093/;
        auth_basic "Alertmanager";
        auth_basic_user_file /etc/nginx/.htpasswd;
    }

    location /grafana/ {
        proxy_pass http://localhost:3000/;
        proxy_set_header Host $host;
    }
}
EOF

sudo ln -s /etc/nginx/sites-available/prometheus /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

---

## Firewall Configuration

Open only the minimum required ports:

```bash
# On monitoring server:
sudo ufw allow 9090/tcp   # Prometheus (team access)
sudo ufw allow 9093/tcp   # Alertmanager (team access)
sudo ufw allow 3000/tcp   # Grafana (team access)

# On each monitored server:
sudo ufw allow from <monitoring-server-IP> to any port 9100
```

Restrict Node Exporter to only accept scrapes from the Prometheus server using `--web.listen-address` flag:
```bash
# In node_exporter.service ExecStart:
ExecStart=/usr/local/bin/node_exporter --web.listen-address=<monitoring-IP>:9100
```

---

*Last updated: 2026-06-21 | Owner: Person A*
