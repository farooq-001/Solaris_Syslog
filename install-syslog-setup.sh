#!/usr/bin/env bash

#################
#check root user#
#################
if [ "$(id -u)" -ne 0 ]; then
    echo ""
    echo 'Invalid User!!! Please run the script as root.'
    echo ""
    exit 1
fi

########################
# Check Internet access #
########################
echo -n "Checking for Internet access... "
IP=$(curl -s --max-time 5 ipinfo.io/ip 2>/dev/null)
if [[ $? -eq 0 && -n "$IP" ]]; then
    echo "Online."
    echo ""
else
    echo "Offline."
    echo ""
    echo "Check internet access and rerun the script. Terminating!"
    exit 1
fi

echo "#########################"
echo "# Detect OS and version #"
echo "#########################"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    # VERSION_ID is already sourced; no need to reassign it
    OS_FLAVOR="$PRETTY_NAME"
else
    echo "Cannot detect OS. /etc/os-release not found."
    exit 1
fi

echo "Detected OS: $OS_FLAVOR"

# Initialize IP variable from command line argument
ip=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -ip)
      if [[ -n $2 ]]; then
        ip="$2"
        shift 2
      else
        echo "Error: -ip requires an IP address argument."
        exit 1
      fi
      ;;
    *)
      echo "Unknown option: $1"
      echo "Usage: $0 -ip <IP_ADDRESS>"
      exit 1
      ;;
  esac
done

# Check if required IP parameter is provided
if [[ -z "$ip" ]]; then
  echo "Error: IP address is required."
  echo "Usage: $0 -ip <IP_ADDRESS>"
  exit 1
fi

echo "Using IP address: $ip"

# Check if rsyslog is installed; Solaris pkg commands differ
if ! pkg list rsyslog >/dev/null 2>&1; then
  echo "rsyslog not installed. Installing now via pkg..."
  # Install with auto confirmation; handle failure
  if ! pkg install -y system/rsyslog; then
    echo "Failed to install rsyslog. Please install manually."
    exit 1
  fi
else
  echo "rsyslog is already installed."
fi

# Backup existing config file if it exists
RSYSLOG_CONF="/etc/rsyslog.d/50-blusapphire-log-forward.conf"
CKUP_DIR="/tmp"
TS=$(date +%Y%m%d-%H%M%S)

if [[ -f "$RSYSLOG_CONF" ]]; then
    mv "$RSYSLOG_CONF" "$CKUP_DIR/50-blusapphire-log-forward.conf.$TS"
fi

# Write rsyslog configuration with given IP
cat <<EOF > "$RSYSLOG_CONF"
####################################################################
# BluSapphire - Rsyslog Configuration for Syslog, Audit Forwarding
#
# Note: This configuration uses legacy syntax compatible with 
#       rsyslog versions 3.x, 4.x, and 5.x (pre-6.0).
####################################################################
#### Modules and Work Directory ####
#\$ModLoad imfile
module(load="imuxsock")
#\$WorkDirectory /var/lib/rsyslog
\$WorkDirectory /var/spool/rsyslog

#### TEMPLATES ####
# Syslog template (all non-audit logs)
\$template SyslogRFC5424Format,"<%PRI%>%protocol-version% %TIMESTAMP:::date-rfc3339% %HOSTNAME% %APP-NAME% %PROCID% %MSGID% [log type=\"linux_syslog\"] %msg%\n"
# Audit template (audit logs from /var/log/audit/audit.log)
#\$template AuditRFC5424Format,"<%PRI%>%protocol-version% %TIMESTAMP:::date-rfc3339% %HOSTNAME% %APP-NAME% %PROCID% %MSGID% [log type=\"linux_auditd\"] %msg%\n"

#### AUDIT LOG FORWARDER ####
# Monitor audit log file
#\$InputFileName /var/log/audit/audit.log
#\$InputFileTag auditd:
#\$InputFileStateFile audit_log_state
#\$InputFileSeverity info
#\$InputFileFacility local6
#\$InputFilePollInterval 1
#\$InputRunFileMonitor

# Queue for audit forwarding
#\$ActionQueueType LinkedList
#\$ActionQueueFileName audit_fwd
#\$ActionQueueMaxDiskSpace 1g
#\$ActionQueueSaveOnShutdown on

# Forward audit logs
## TCP forwarding (uncomment if required)
#local6.* @@${ip}:12513;AuditRFC5424Format
## UDP forwarding (uncomment if required)
#local6.* @${ip}:12513;AuditRFC5424Format

#### SYSLOG FORWARDER ####
# Queue for syslog forwarding
\$ActionQueueType LinkedList
\$ActionQueueFileName syslog_fwd
\$ActionQueueMaxDiskSpace 1g
\$ActionQueueSaveOnShutdown on

# Forward all non-audit/syslog messages to port 12514
# Exclude auditd program and messages containing "audit" to prevent duplication
#:programname, isequal, "auditd"     ~
#:msg, contains, "audit"              ~

# Forward syslog logs
## TCP forwarding (uncomment if required)
#*.* @@${ip}:12514;SyslogRFC5424Format
## UDP forwarding (uncomment if required)
*.* @${ip}:12514;SyslogRFC5424Format

EOF

echo "Rsyslog configuration updated at $RSYSLOG_CONF."

sleep 5
# Disable default system log and enable rsyslog service
echo "Disabling default system log service..."
svcadm disable svc:/system/system-log:default
echo "Enabling rsyslog service..."
svcadm enable svc:/system/system-log:rsyslog
echo "Clearing rsyslog service fault status..."
svcadm clear svc:/system/system-log:rsyslog

# Check rsyslog service status
svcs system-log:rsyslog

echo "Restarting rsyslog service..."
svcadm restart svc:/system/system-log:rsyslog

echo "Refreshing rsyslog service..."
svcadm refresh svc:/system/system-log:rsyslog

# Final rsyslog service status
svcs system-log:rsyslog

echo "Script completed successfully."
exit 0
