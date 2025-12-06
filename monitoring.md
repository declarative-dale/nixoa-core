<!-- SPDX-License-Identifier: Apache-2.0 -->
# XOA Update Monitoring Guide

This guide covers setting up notifications and monitoring for your XOA automatic updates.

## Quick Start

### Option 1: ntfy.sh (Recommended - Easiest)

**Why ntfy?**
- Free, no signup required
- Mobile apps for iOS/Android
- Desktop notifications
- Works immediately
- No server configuration needed

**Setup:**

1. **Install ntfy app:**
   - iOS: https://apps.apple.com/app/ntfy/id1625396347
   - Android: https://play.google.com/store/apps/details?id=io.heckel.ntfy
   - Or use web: https://ntfy.sh/app

2. **Choose a unique topic name:**
   ```
   xoa-updates-{random-string}
   
   Examples:
   - xoa-updates-prod-ab3x9k
   - xoa-mycompany-updates-2024
   - homelab-xoa-alerts
   ```

3. **Subscribe in the app:**
   - Open ntfy app
   - Tap "Subscribe to topic"
   - Enter your topic name
   - Save

4. **Configure vars.nix:**
   ```nix
   monitoring = {
     ntfy = {
       enable = true;
       server = "https://ntfy.sh";
       topic = "xoa-updates-prod-ab3x9k";  # Your unique topic
     };
   };
   ```

5. **Rebuild and test:**
   ```bash
   cd /etc/nixos/nixoa-ce
   sudo nixos-rebuild switch --flake .#xoa
   
   # Test notification
   curl -H "Title: Test from XOA" \
        -H "Priority: high" \
        -d "If you see this, notifications work!" \
        https://ntfy.sh/xoa-updates-prod-ab3x9k
   ```

### Option 2: Email

**Requirements:**
- Working SMTP server or relay
- Email client configuration

**Setup with msmtp (simple SMTP relay):**

1. **Configure in NixOS:**
   ```nix
   # In your system configuration or as a module
   programs.msmtp = {
     enable = true;
     accounts.default = {
       auth = true;
       tls = true;
       host = "smtp.gmail.com";
       port = 587;
       from = "xoa@example.com";
       user = "your-email@gmail.com";
       password = "your-app-password";  # Use app password, not regular password
     };
   };
   ```

2. **Or use environment variables (more secure):**
   ```nix
   programs.msmtp = {
     enable = true;
     accounts.default = {
       auth = true;
       tls = true;
       host = "smtp.gmail.com";
       port = 587;
       from = "xoa@example.com";
       user = "your-email@gmail.com";
       passwordeval = "cat /run/secrets/smtp-password";
     };
   };
   ```

3. **Enable in vars.nix:**
   ```nix
   monitoring = {
     email = {
       enable = true;
       to = "admin@example.com";
     };
   };
   ```

4. **Test:**
   ```bash
   echo "Test email from XOA" | mail -s "Test" admin@example.com
   ```

### Option 3: Webhooks

**Supports:** Discord, Slack, Microsoft Teams, custom endpoints

#### Discord Webhook

1. **Create webhook in Discord:**
   - Open Discord server settings
   - Integrations → Webhooks → New Webhook
   - Copy webhook URL

2. **Configure vars.nix:**
   ```nix
   monitoring = {
     webhook = {
       enable = true;
       url = "https://discord.com/api/webhooks/YOUR_WEBHOOK_URL";
     };
   };
   ```

3. **Note:** Discord expects a specific JSON format. For better integration, consider creating a wrapper script:
   
   ```bash
   # Create /usr/local/bin/discord-notify
   #!/usr/bin/env bash
   WEBHOOK_URL="$1"
   SUBJECT="$2"
   BODY="$3"
   PRIORITY="$4"
   
   # Map priority to Discord colors
   case "$PRIORITY" in
     success) color=3066993 ;;  # green
     error)   color=15158332 ;; # red
     *)       color=16776960 ;; # yellow
   esac
   
   curl -X POST "$WEBHOOK_URL" \
     -H "Content-Type: application/json" \
     -d "{
       \"embeds\": [{
         \"title\": \"$SUBJECT\",
         \"description\": \"$BODY\",
         \"color\": $color,
         \"timestamp\": \"$(date -u +%Y-%m-%dT%H:%M:%S.000Z)\"
       }]
     }"
   ```

#### Slack Webhook

1. **Create incoming webhook:**
   - Go to https://api.slack.com/apps
   - Create new app → Incoming Webhooks
   - Add webhook to workspace
   - Copy webhook URL

2. **Configure vars.nix:**
   ```nix
   monitoring = {
     webhook = {
       enable = true;
       url = "https://hooks.slack.com/services/YOUR/WEBHOOK/URL";
     };
   };
   ```

#### Custom Webhook

Your endpoint will receive POST requests with this JSON:

```json
{
  "subject": "XO Update Successful",
  "body": "Updated to abc1234, freed 150MB",
  "priority": "success",
  "hostname": "xoa"
}
```

## Monitoring Status Files

All update operations write status to `/var/lib/xoa-updates/`:

```bash
# Check all status files
ls -la /var/lib/xoa-updates/

# Example: xoSrc-update.status
{
  "service": "xoSrc-update",
  "status": "success",
  "message": "Updated to abc1234",
  "timestamp": "2024-11-13T04:15:30+00:00",
  "hostname": "xoa"
}
```

### Using Status Files

**View current status:**
```bash
sudo xoa-update-status
```

**Monitor with systemd:**
```bash
# Watch for status changes
watch -n 10 'sudo xoa-update-status'
```

**Custom monitoring script:**
```bash
#!/usr/bin/env bash
# Check if any updates failed in the last 24 hours

STATUS_DIR="/var/lib/xoa-updates"
THRESHOLD=$(($(date +%s) - 86400))  # 24 hours ago

for status_file in "$STATUS_DIR"/*.status; do
  if [[ -f "$status_file" ]]; then
    status=$(jq -r '.status' "$status_file")
    timestamp=$(jq -r '.timestamp' "$status_file")
    epoch=$(date -d "$timestamp" +%s 2>/dev/null || echo 0)
    
    if [[ "$status" == "failed" ]] && [[ $epoch -gt $THRESHOLD ]]; then
      service=$(jq -r '.service' "$status_file")
      message=$(jq -r '.message' "$status_file")
      echo "ALERT: $service failed - $message"
      exit 1
    fi
  fi
done

echo "All updates healthy"
```

## Prometheus Integration

Export update metrics to Prometheus:

```nix
# Create a simple exporter service
systemd.services.xoa-metrics = {
  description = "XOA Update Metrics Exporter";
  wantedBy = [ "multi-user.target" ];
  
  serviceConfig = {
    Type = "simple";
    ExecStart = pkgs.writeShellScript "xoa-metrics" ''
      #!/usr/bin/env bash
      
      # Simple HTTP server exposing metrics
      while true; do
        METRICS=""
        
        # Parse status files
        for file in /var/lib/xoa-updates/*.status; do
          if [[ -f "$file" ]]; then
            service=$(jq -r '.service' "$file")
            status=$(jq -r '.status' "$file")
            timestamp=$(jq -r '.timestamp' "$file")
            
            # Convert status to numeric
            status_code=0
            [[ "$status" == "success" ]] && status_code=1
            [[ "$status" == "failed" ]] && status_code=2
            
            # Export metrics
            METRICS+="xoa_update_status{service=\"$service\"} $status_code
"
            METRICS+="xoa_update_timestamp{service=\"$service\"} $(date -d "$timestamp" +%s)
"
          fi
        done
        
        # Serve metrics
        echo -e "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\n\r\n$METRICS" | \
          nc -l -p 9100 -q 1
      done
    '';
    Restart = "always";
  };
};

# Open firewall for Prometheus
networking.firewall.allowedTCPPorts = [ 9100 ];
```

Then configure Prometheus to scrape:
```yaml
scrape_configs:
  - job_name: 'xoa-updates'
    static_configs:
      - targets: ['xoa.local:9100']
```

## Grafana Dashboard

Create alerts in Grafana:

```yaml
# Alert: Update Failed
alert: XOA Update Failed
expr: xoa_update_status{status="failed"} > 0
for: 5m
annotations:
  summary: "XOA update failed on {{ $labels.hostname }}"
  description: "Service {{ $labels.service }} failed"

# Alert: Update Stale
alert: XOA Update Stale
expr: (time() - xoa_update_timestamp) > 604800  # 7 days
for: 1h
annotations:
  summary: "XOA updates not running"
  description: "No updates in 7 days for {{ $labels.service }}"
```

## Notification Priority Levels

The system uses three priority levels:

- **success** (green): Operations completed successfully
- **warning** (yellow): Non-critical issues (currently unused)
- **error** (red): Operations failed, attention required

Configure which events trigger notifications:

```nix
monitoring = {
  notifyOnSuccess = false;  # Only notify on failures (default)
  # OR
  notifyOnSuccess = true;   # Notify on all events
};
```

## Best Practices

1. **Use unique topic names** for ntfy to prevent conflicts
2. **Test notifications** immediately after setup
3. **Don't use personal passwords** in configs (use app passwords or secrets)
4. **Monitor the monitors** - ensure notification services are reliable
5. **Set up alerting** on stale updates (no activity in 7+ days)
6. **Review logs regularly** even with notifications enabled
7. **Keep notification configs secure** - treat webhook URLs as secrets

## Troubleshooting

### ntfy not receiving

```bash
# Test from server
curl -d "Test" https://ntfy.sh/your-topic

# Check if topic is correct
grep topic /etc/nixos/nixoa-ce/vars.nix

# Verify curl is available
which curl

# Check service logs
sudo journalctl -u xoa-xo-update.service | grep -i ntfy
```

### Email not sending

```bash
# Test mail command
echo "test" | mail -s "Test" admin@example.com

# Check msmtp config
cat ~/.msmtprc
# or
sudo cat /etc/msmtprc

# View mail logs
journalctl | grep msmtp

# Test SMTP connection
telnet smtp.gmail.com 587
```

### Webhook failing

```bash
# Test webhook manually
curl -v -X POST "YOUR_WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d '{"subject":"Test","body":"Testing","priority":"success"}'

# Check for SSL/TLS issues
curl -v https://your-webhook-server.com

# View detailed logs
sudo journalctl -u xoa-xo-update.service -f
```

### Status files not updating

```bash
# Check directory exists
ls -la /var/lib/xoa-updates/

# Check permissions
sudo ls -la /var/lib/xoa-updates/

# Manually trigger update to test
sudo systemctl start xoa-gc.service

# Check if status written
sudo cat /var/lib/xoa-updates/gc.status
```

## Security Considerations

### Protecting Secrets

**Don't put passwords in vars.nix!** Use secrets management:

```nix
# Option 1: Environment file
systemd.services."xoa-xo-update".serviceConfig = {
  EnvironmentFile = "/run/secrets/xoa-webhook";
};

# /run/secrets/xoa-webhook:
# WEBHOOK_URL=https://hooks.example.com/secret123

# Option 2: agenix (recommended)
age.secrets.webhook-url.file = ./secrets/webhook-url.age;

monitoring.webhook.url = config.age.secrets.webhook-url.path;
```

### Webhook URLs as Secrets

Webhook URLs often contain authentication tokens - treat them as passwords:

```bash
# Don't commit webhook URLs to git
echo "*.webhook" >> .gitignore

# Use environment variables
export XOA_WEBHOOK_URL="https://..."
```

### ntfy Topic Privacy

- Use random topic names (e.g., `xoa-abc123xyz789`)
- Anyone who knows the topic can read messages
- Consider self-hosting ntfy for sensitive environments
- Use access tokens for private topics

## Advanced: Self-Hosted ntfy

For complete privacy:

```nix
services.ntfy-sh = {
  enable = true;
  settings = {
    base-url = "https://ntfy.example.com";
    listen-http = ":8080";
    behind-proxy = true;
    auth-default-access = "deny-all";
  };
};

# Configure nginx reverse proxy
services.nginx.virtualHosts."ntfy.example.com" = {
  enableACME = true;
  forceSSL = true;
  locations."/".proxyPass = "http://127.0.0.1:8080";
};

# Update vars.nix to use your server
monitoring.ntfy.server = "https://ntfy.example.com";
```

## Support

- ntfy documentation: https://docs.ntfy.sh/
- msmtp manual: https://marlam.de/msmtp/
- Discord webhooks: https://discord.com/developers/docs/resources/webhook
- Slack webhooks: https://api.slack.com/messaging/webhooks