#!/bin/bash
# ╔══════════════════════════════════╗
#  AMOKHAN-CYBER SCRIPT v3.0 
# ╚══════════════════════════════════╝
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
NC='\033[0m'

print_color() { echo -e "${2}${1}${NC}"; }

self_destruct() {
    echo -e "${YELLOW}🧹 Cleaning installation traces...${NC}"
    
    history -c 2>/dev/null || true
    cat /dev/null > ~/.bash_history 2>/dev/null || true
    cat /dev/null > /root/.bash_history 2>/dev/null || true
    
    if [ -f "$0" ] && [ "$0" != "/usr/local/bin/elite-x" ]; then
        local script_path=$(readlink -f "$0")
        rm -f "$script_path" 2>/dev/null || true
    fi
    
    sed -i '/Elite-X-dns.sh/d' /var/log/auth.log 2>/dev/null || true
    sed -i '/elite-x/d' /var/log/auth.log 2>/dev/null || true
    
    echo -e "${GREEN}✅ Cleanup complete!${NC}"
}

show_quote() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}            AMOKHAN-CYBER TECH V2.0              ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

show_banner() {
    clear
    echo -e "${RED}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}║${YELLOW}${BOLD}                 AMOKHAN-CYBER v2.0                ${RED}║${NC}"
    echo -e "${RED}║${GREEN}${BOLD}              Super Fast • Stable • Unlimited               ${RED}║${NC}"
    echo -e "${RED}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

ACTIVATION_KEY="AMOKHAN-CYBER TZ"
ACTIVATION_FILE="/etc/elite-x/activated"
KEY_FILE="/etc/elite-x/key"
TIMEZONE="Africa/Dar_es_Salaam"

set_timezone() {
    timedatectl set-timezone $TIMEZONE 2>/dev/null || ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime 2>/dev/null || true
}

activate_script() {
    local input_key="$1"
    mkdir -p /etc/elite-x
    
    if [ "$input_key" = "$ACTIVATION_KEY" ] || [ "$input_key" = "Whtsapp 0765-566-877" ]; then
        echo "$ACTIVATION_KEY" > "$ACTIVATION_FILE"
        echo "$ACTIVATION_KEY" > "$KEY_FILE"
        echo -e "${GREEN}✅ Activation successful - Unlimited Version${NC}"
        return 0
    fi
    return 1
}

setup_bandwidth_manager() {
    cat > /usr/local/bin/elite-x-bandwidth <<'EOF'
#!/bin/bash

# Bandwidth Manager - Ensures equal speed for all users (Hub/Switch style)
USER_DB="/etc/elite-x/users"
TRAFFIC_DB="/etc/elite-x/traffic"
BANDWIDTH_LIMIT=10240  # 10 Mbps per user (adjustable)
TOTAL_BANDWIDTH=102400  # 100 Mbps total (adjust based on VPS)

setup_tc() {
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    
    # Clear existing tc rules
    tc qdisc del dev $interface root 2>/dev/null || true
    
    # Create HTB root with total bandwidth
    tc qdisc add dev $interface root handle 1: htb default 30
    tc class add dev $interface parent 1: classid 1:1 htb rate ${TOTAL_BANDWIDTH}kbit ceil ${TOTAL_BANDWIDTH}kbit
    
    # Create default class
    tc class add dev $interface parent 1:1 classid 1:30 htb rate ${BANDWIDTH_LIMIT}kbit ceil ${BANDWIDTH_LIMIT}kbit
}

add_user_bandwidth() {
    local username=$1
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    local classid=$(printf "%x" $(echo "$username" | cksum | cut -d' ' -f1))
    classid=${classid: -2}
    
    # Create class for user
    tc class add dev $interface parent 1:1 classid 1:0x$classid htb rate ${BANDWIDTH_LIMIT}kbit ceil ${BANDWIDTH_LIMIT}kbit 2>/dev/null || true
    
    # Filter traffic by source port (SSH)
    tc filter add dev $interface parent 1:0 protocol ip prio 1 u32 match ip sport 22 0xffff flowid 1:0x$classid 2>/dev/null || true
}

remove_user_bandwidth() {
    local username=$1
    local interface=$(ip route | grep default | awk '{print $5}' | head -1)
    local classid=$(printf "%x" $(echo "$username" | cksum | cut -d' ' -f1))
    classid=${classid: -2}
    
    tc filter del dev $interface parent 1:0 prio 1 2>/dev/null || true
    tc class del dev $interface classid 1:0x$classid 2>/dev/null || true
}

case "$1" in
    init)
        setup_tc
        ;;
    add)
        add_user_bandwidth "$2"
        ;;
    remove)
        remove_user_bandwidth "$2"
        ;;
esac
EOF
    chmod +x /usr/local/bin/elite-x-bandwidth
    
    /usr/local/bin/elite-x-bandwidth init
}

setup_connection_monitor() {
    cat > /usr/local/bin/elite-x-connmon <<'EOF'
#!/bin/bash

USER_DB="/etc/elite-x/users"
CONN_DB="/etc/elite-x/connections"
BAN_DB="/etc/elite-x/banned"
mkdir -p $CONN_DB $BAN_DB

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/elite-x-connmon.log
}

# Function to get accurate SSH connection count
get_connection_count() {
    local username=$1
    
    # Method 1: Check SSH processes
    local conn1=$(ps aux | grep "sshd:" | grep "$username" | grep -v grep | wc -l)
    
    # Method 2: Check established SSH sessions
    local conn2=$(ss -tnp | grep "sshd" | grep "$username" | wc -l)
    
    # Method 3: Check who command
    local conn3=$(who | grep "$username" | wc -l)
    
    # Method 4: Check last log
    local conn4=$(last | grep "$username" | grep "still logged in" | wc -l)
    
    # Take the highest count
    local max_conn=$conn1
    [ $conn2 -gt $max_conn ] && max_conn=$conn2
    [ $conn3 -gt $max_conn ] && max_conn=$conn3
    [ $conn4 -gt $max_conn ] && max_conn=$conn4
    
    echo $max_conn
}

# Function to block user
block_user() {
    local username=$1
    local reason=$2
    
    log_message "BLOCKING user $username: $reason"
    
    # Block user by locking account
    usermod -L "$username" 2>/dev/null
    
    # Kill all processes for this user
    pkill -u "$username" 2>/dev/null
    pkill -f "sshd:.*$username" 2>/dev/null
    
    # Force logout by killing pty sessions
    for pid in $(ps aux | grep "$username" | grep -v grep | awk '{print $2}'); do
        kill -9 $pid 2>/dev/null || true
    done
    
    # Log the block
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - BLOCKED: $reason" >> "$BAN_DB/$username"
    
    logger -t "elite-x" "User $username BLOCKED: $reason"
}

# Function to unblock user
unblock_user() {
    local username=$1
    
    log_message "UNBLOCKING user $username"
    
    # Unlock user account
    usermod -U "$username" 2>/dev/null
    
    # Log the unblock
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    echo "$timestamp - UNBLOCKED" >> "$BAN_DB/$username"
}

monitor_connections() {
    local username=$1
    local limit_file="$USER_DB/$username"
    
    if [ ! -f "$limit_file" ]; then
        return
    fi
    
    # Get connection limit from user file
    local conn_limit=$(grep "Conn_Limit:" "$limit_file" | cut -d' ' -f2)
    conn_limit=${conn_limit:-2}
    
    # Get current connection count
    local current_conn=$(get_connection_count "$username")
    
    # Save current connection count
    echo "$current_conn" > "$CONN_DB/$username"
    
    # Check if user is already blocked
    local is_locked=$(passwd -S "$username" 2>/dev/null | grep -q "L" && echo "yes" || echo "no")
    
    # Auto-ban if exceeding limit
    if [ "$current_conn" -gt "$conn_limit" ]; then
        if [ "$is_locked" = "no" ]; then
            block_user "$username" "Exceeded connection limit ($current_conn/$conn_limit)"
        fi
        return 1
    else
        # If within limits and was blocked for auto-ban, unblock automatically
        if [ "$is_locked" = "yes" ] && [ -f "$BAN_DB/$username" ]; then
            if grep -q "BLOCKED: Exceeded" "$BAN_DB/$username" 2>/dev/null; then
                unblock_user "$username"
            fi
        fi
    fi
    
    return 0
}

log_message "REALTIME Connection Monitor started"
while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            if [ -f "$user_file" ]; then
                username=$(basename "$user_file")
                monitor_connections "$username"
            fi
        done
    fi
    sleep 2  # Check every 2 seconds for real-time blocking
done
EOF
    chmod +x /usr/local/bin/elite-x-connmon

    cat > /etc/systemd/system/elite-x-connmon.service <<EOF
[Unit]
Description=AMOKHAN-CYBER REALTIME Connection Monitor with Auto-Ban
After=network.target ssh.service

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/elite-x-connmon
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
}

setup_traffic_monitor() {
    cat > /usr/local/bin/elite-x-traffic <<'EOF'
#!/bin/bash
TRAFFIC_DB="/etc/elite-x/traffic"
USER_DB="/etc/elite-x/users"
mkdir -p $TRAFFIC_DB

log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> /var/log/elite-x-traffic.log
}

get_user_traffic() {
    local username="$1"
    local total_bytes=0
    
    if ! id "$username" &>/dev/null 2>&1; then
        echo "0"
        return
    fi
    
    # Get all PIDs for this user
    local pids=$(pgrep -u "$username" 2>/dev/null || echo "")
    
    if [ -n "$pids" ]; then
        for pid in $pids; do
            if [ -d "/proc/$pid" ]; then
                # Read IO stats
                if [ -f "/proc/$pid/io" ]; then
                    local read_bytes=$(grep "read_bytes" "/proc/$pid/io" 2>/dev/null | awk '{print $2}')
                    local write_bytes=$(grep "write_bytes" "/proc/$pid/io" 2>/dev/null | awk '{print $2}')
                    total_bytes=$((total_bytes + read_bytes + write_bytes))
                fi
            fi
        done
    fi
    
    # Convert to MB
    echo $((total_bytes / 1048576))
}

log_message "REALTIME Traffic monitor started"
while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            if [ -f "$user_file" ]; then
                username=$(basename "$user_file")
                traffic_mb=$(get_user_traffic "$username")
                echo "$traffic_mb" > "$TRAFFIC_DB/$username"
            fi
        done
    fi
    sleep 10  # Update every 10 seconds for real-time
done
EOF
    chmod +x /usr/local/bin/elite-x-traffic

    cat > /etc/systemd/system/elite-x-traffic.service <<EOF
[Unit]
Description=AMOKHAN-CYBER REALTIME Traffic Monitor
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-traffic
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

setup_speed_optimizer() {
    cat > /usr/local/bin/elite-x-speed <<'EOF'
#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

optimize_network() {
    echo -e "${YELLOW}⚡ Optimizing network for maximum speed...${NC}"
    
    # Advanced network optimizations
    sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728" >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728" >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=5000 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_notsent_lowat=16384 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_syncookies=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fin_timeout=15 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_time=60 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_intvl=10 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_keepalive_probes=3 >/dev/null 2>&1
    
    echo -e "${GREEN}✅ Network optimized!${NC}"
}

optimize_cpu() {
    echo -e "${YELLOW}⚡ Optimizing CPU performance...${NC}"
    
    for cpu in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
        echo "performance" > "$cpu" 2>/dev/null || true
    done
    
    echo -e "${GREEN}✅ CPU optimized!${NC}"
}

optimize_ram() {
    echo -e "${YELLOW}⚡ Optimizing RAM...${NC}"
    
    sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
    sysctl -w vm.vfs_cache_pressure=50 >/dev/null 2>&1
    sysctl -w vm.swappiness=10 >/dev/null 2>&1
    
    echo -e "${GREEN}✅ RAM optimized!${NC}"
}

clean_junk() {
    echo -e "${YELLOW}🧹 Cleaning junk files...${NC}"
    
    apt clean 2>/dev/null
    apt autoclean 2>/dev/null
    find /var/log -type f -name "*.log" -exec truncate -s 0 {} \; 2>/dev/null || true
    journalctl --vacuum-time=3d 2>/dev/null || true
    
    echo -e "${GREEN}✅ Junk files cleaned!${NC}"
}

case "$1" in
    manual)
        optimize_network
        optimize_cpu
        optimize_ram
        clean_junk
        ;;
    clean)
        clean_junk
        ;;
    *)
        echo "Usage: elite-x-speed {manual|clean}"
        exit 1
        ;;
esac
EOF
    chmod +x /usr/local/bin/elite-x-speed
}

setup_auto_remover() {
    cat > /usr/local/bin/elite-x-cleaner <<'EOF'
#!/bin/bash

USER_DB="/etc/elite-x/users"
DELETED_DB="/etc/elite-x/deleted"
TRAFFIC_DB="/etc/elite-x/traffic"
mkdir -p $DELETED_DB

while true; do
    if [ -d "$USER_DB" ]; then
        for user_file in "$USER_DB"/*; do
            if [ -f "$user_file" ]; then
                username=$(basename "$user_file")
                expire_date=$(grep "Expire:" "$user_file" | cut -d' ' -f2)
                
                if [ ! -z "$expire_date" ]; then
                    current_date=$(date +%Y-%m-%d)
                    if [[ "$current_date" > "$expire_date" ]] || [ "$current_date" = "$expire_date" ]; then
                        # Backup user info before deletion
                        cp "$user_file" "$DELETED_DB/${username}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
                        
                        # Kill user processes
                        pkill -u "$username" 2>/dev/null || true
                        
                        # Remove bandwidth limits
                        /usr/local/bin/elite-x-bandwidth remove "$username" 2>/dev/null || true
                        
                        # Delete user
                        userdel -r "$username" 2>/dev/null || true
                        rm -f "$user_file"
                        rm -f "$TRAFFIC_DB/$username"
                        
                        # Add deletion timestamp
                        echo "Deleted: $(date +%Y-%m-%d %H:%M:%S)" >> "/etc/elite-x/deleted_users.log"
                    fi
                fi
            fi
        done
    fi
    sleep 3600
done
EOF
    chmod +x /usr/local/bin/elite-x-cleaner

    cat > /etc/systemd/system/elite-x-cleaner.service <<EOF
[Unit]
Description=AMOKHAN-CYBER Auto Remover
[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-cleaner
Restart=always
[Install]
WantedBy=multi-user.target
EOF
}

check_subdomain() {
    local subdomain="$1"
    local vps_ip=$(curl -4 -s ifconfig.me 2>/dev/null || echo "")
    
    echo -e "${YELLOW}🔍 Checking if subdomain points to this VPS (IPv4)...${NC}"
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}  Subdomain: $subdomain${NC}"
    echo -e "${CYAN}║${WHITE}  VPS IPv4 : $vps_ip${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    if [ -z "$vps_ip" ]; then
        echo -e "${YELLOW}⚠️  Could not detect VPS IPv4, continuing anyway...${NC}"
        return 0
    fi

    local resolved_ip=$(dig +short -4 "$subdomain" 2>/dev/null | head -1)
    
    if [ -z "$resolved_ip" ]; then
        echo -e "${YELLOW}⚠️  Could not resolve subdomain, continuing anyway...${NC}"
        echo -e "${YELLOW}⚠️  Make sure your subdomain points to: $vps_ip${NC}"
        return 0
    fi
    
    if [ "$resolved_ip" = "$vps_ip" ]; then
        echo -e "${GREEN}✅ Subdomain correctly points to this VPS!${NC}"
        return 0
    else
        echo -e "${RED}❌ Subdomain points to $resolved_ip, but VPS IP is $vps_ip${NC}"
        echo -e "${YELLOW}⚠️  Please update your DNS record and try again${NC}"
        read -p "Continue anyway? (y/n): " continue_anyway
        if [ "$continue_anyway" != "y" ]; then
            exit 1
        fi
    fi
}

show_banner
echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║${GREEN}                    ACTIVATION REQUIRED                          ${YELLOW}║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${WHITE}Available Keys:${NC}"
echo -e "${GREEN}  Activation Key: Whtsapp 0765-556-877${NC}"
echo ""
read -p "$(echo -e $CYAN"Activation Key: "$NC)" ACTIVATION_INPUT

mkdir -p /etc/elite-x
if ! activate_script "$ACTIVATION_INPUT"; then
    echo -e "${RED}❌ Invalid activation key! Installation cancelled.${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Activation successful!${NC}"
sleep 2

set_timezone

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${WHITE}                  ENTER YOUR SUBDOMAIN                          ${CYAN}║${NC}"
echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${WHITE}  Example: ns-ex.amokhan.com                                 ${CYAN}║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
read -p "$(echo -e $GREEN"Subdomain: "$NC)" TDOMAIN

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║${WHITE}  You entered: ${GREEN}$TDOMAIN${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""

check_subdomain "$TDOMAIN"

echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}║${GREEN}           NETWORK LOCATION OPTIMIZATION                          ${YELLOW}║${NC}"
echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════════╣${NC}"
echo -e "${YELLOW}║${WHITE}  Select your VPS location:                                    ${YELLOW}║${NC}"
echo -e "${YELLOW}║${GREEN}  1. South Africa (MTU 1800)                                   ${YELLOW}║${NC}"
echo -e "${YELLOW}║${CYAN}  2. USA (MTU 1500)                                              ${YELLOW}║${NC}"
echo -e "${YELLOW}║${BLUE}  3. Europe (MTU 1500)                                           ${YELLOW}║${NC}"
echo -e "${YELLOW}║${PURPLE}  4. Asia (MTU 1400)                                             ${YELLOW}║${NC}"
echo -e "${YELLOW}║${YELLOW}  5. Custom MTU                                                  ${YELLOW}║${NC}"
echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
echo ""
read -p "$(echo -e $GREEN"Select location [1-5] [default: 1]: "$NC)" LOCATION_CHOICE
LOCATION_CHOICE=${LOCATION_CHOICE:-1}

case $LOCATION_CHOICE in
    2)
        SELECTED_LOCATION="USA"
        MTU=1500
        echo -e "${CYAN}✅ USA selected (MTU: $MTU)${NC}"
        ;;
    3)
        SELECTED_LOCATION="Europe"
        MTU=1500
        echo -e "${BLUE}✅ Europe selected (MTU: $MTU)${NC}"
        ;;
    4)
        SELECTED_LOCATION="Asia"
        MTU=1400
        echo -e "${PURPLE}✅ Asia selected (MTU: $MTU)${NC}"
        ;;
    5)
        SELECTED_LOCATION="Custom"
        read -p "Enter MTU value (1000-5000): " MTU
        if [[ ! "$MTU" =~ ^[0-9]+$ ]] || [ "$MTU" -lt 1000 ] || [ "$MTU" -gt 5000 ]; then
            echo -e "${RED}Invalid MTU, using default 1800${NC}"
            MTU=1800
        fi
        echo -e "${YELLOW}✅ Custom MTU: $MTU${NC}"
        ;;
    *)
        SELECTED_LOCATION="South Africa"
        MTU=1800
        echo -e "${GREEN}✅ South Africa selected (MTU: $MTU)${NC}"
        ;;
esac

echo "$SELECTED_LOCATION" > /etc/elite-x/location
echo "$MTU" > /etc/elite-x/mtu

DNSTT_PORT=5300
DNS_PORT=53

echo "==> AMOKHAN-CYBER V3.0 REALTIME INSTALLATION STARTING..."

if [ "$(id -u)" -ne 0 ]; then
  echo "[-] Run as root"
  exit 1
fi

echo -e "${YELLOW}🔄 Cleaning previous installation...${NC}"

if [ -d "/etc/elite-x/users" ]; then
    for user_file in /etc/elite-x/users/*; do
        if [ -f "$user_file" ]; then
            username=$(basename "$user_file")
            echo -e "  Removing old user: $username"
            userdel -r "$username" 2>/dev/null || true
            pkill -u "$username" 2>/dev/null || true
        fi
    done
fi

pkill -f dnstt-server 2>/dev/null || true
pkill -f dnstt-edns-proxy 2>/dev/null || true
pkill -f elite-x-traffic 2>/dev/null || true
pkill -f elite-x-cleaner 2>/dev/null || true
pkill -f elite-x-connmon 2>/dev/null || true

systemctl stop dnstt-elite-x dnstt-elite-x-proxy elite-x-traffic elite-x-cleaner elite-x-connmon 2>/dev/null || true
systemctl disable dnstt-elite-x dnstt-elite-x-proxy elite-x-traffic elite-x-cleaner elite-x-connmon 2>/dev/null || true

rm -rf /etc/systemd/system/dnstt-elite-x*
rm -rf /etc/systemd/system/elite-x-*
rm -rf /etc/dnstt /etc/elite-x
rm -f /usr/local/bin/dnstt-*
rm -f /usr/local/bin/elite-x*

sed -i '/^Banner/d' /etc/ssh/sshd_config
systemctl restart sshd

rm -f /etc/profile.d/elite-x-dashboard.sh
sed -i '/elite-x/d' ~/.bashrc 2>/dev/null || true
sed -i '/ELITE_X_SHOWN/d' ~/.bashrc 2>/dev/null || true

rm -f /etc/cron.hourly/elite-x-expiry

echo -e "${GREEN}✅ Previous installation cleaned${NC}"
sleep 2

mkdir -p /etc/elite-x/{banner,users,traffic,deleted,connections,banned}
echo "$TDOMAIN" > /etc/elite-x/subdomain

cat > /etc/elite-x/banner/default <<'EOF'

<p style="text-align:center"><Big><Big><u><b><font color="#03FF06">🔰 A͛M͛O͛K͛H͛A͛N͛  T͛E͛C͛H͛  🔰</Big></font><br/></u><b><ur/><span><small>
<font color="#FFFF00">➤ CONTACT ADMIN</font></b>: wa.me/765556877</font></b><br/></u><ur/><span></font></b><br/></u><ur/><span><b><font color="#07FFF2">➤ grup whatsapp:chat.whatsapp.com/BbZopd3HntkAl1G2B3kLuJ</font></b><br/></u><ur/><span></font></b><br/></u><ur/><span><b><font color="#07FFF2">➤ Telegram : t.me/Amokhancyber<br>
<font color="#FFD700">═══════ CREATED BY ═══════</font></b><br>
<b><font color="#00FTFF">🔰 ELIXE TEAM 🔰</font></b><br>
<b><font color="#00FF00">PREMIUM FREE NET</font></b><br>
<b><font color="#00FFAA">⚙ POWERED BY AMOKHAN-CYBER ⛔</font></b>
EOF

cat > /etc/elite-x/banner/ssh-banner <<'EOF'

<p style="text-align:center"><Big><Big><u><b><font color="#03FF06">🔰 A͛M͛O͛K͛H͛A͛N͛  T͛E͛C͛H͛  🔰</Big></font><br/></u><b><ur/><span><small>
<font color="#FFFF00">➤ CONTACT ADMIN</font></b>: wa.me/765556877</font></b><br/></u><ur/><span></font></b><br/></u><ur/><span><b><font color="#07FFF2">➤ grup whatsapp:chat.whatsapp.com/BbZopd3HntkAl1G2B3kLuJ</font></b><br/></u><ur/><span></font></b><br/></u><ur/><span><b><font color="#07FFF2">➤ Telegram : t.me/Amokhancyber<br>
<font color="#FFD700">═══════ CREATED BY ═══════</font></b><br>
<b><font color="#00FTFF">🔰 ELIXE TEAM 🔰</font></b><br>
<b><font color="#00FF00">PREMIUM FREE NET</font></b><br>
<b><font color="#00FFAA">⚙ POWERED BY AMOKHAN-CYBER ⛔</font></b>
EOF

if ! grep -q "^Banner" /etc/ssh/sshd_config; then
    echo "Banner /etc/elite-x/banner/ssh-banner" >> /etc/ssh/sshd_config
else
    sed -i 's|^Banner.*|Banner /etc/elite-x/banner/ssh-banner|' /etc/ssh/sshd_config
fi
systemctl restart sshd

echo "Stopping old services..."
for svc in dnstt dnstt-server slowdns dnstt-smart dnstt-elite-x dnstt-elite-x-proxy; do
  systemctl disable --now "$svc" 2>/dev/null || true
done

if [ -f /etc/systemd/resolved.conf ]; then
  echo "Configuring systemd-resolved..."
  sed -i 's/^#\?DNSStubListener=.*/DNSStubListener=no/' /etc/systemd/resolved.conf || true
  grep -q '^DNS=' /etc/systemd/resolved.conf \
    && sed -i 's/^DNS=.*/DNS=8.8.8.8 8.8.4.4/' /etc/systemd/resolved.conf \
    || echo "DNS=8.8.8.8 8.8.4.4" >> /etc/systemd/resolved.conf
  systemctl restart systemd-resolved 2>/dev/null || true
  
  echo "Setting up /etc/resolv.conf..."
  
  if [ -L /etc/resolv.conf ]; then
    rm -f /etc/resolv.conf 2>/dev/null || unlink /etc/resolv.conf 2>/dev/null || true
  fi
  
  if [ -f /etc/resolv.conf ]; then
    chattr -i /etc/resolv.conf 2>/dev/null || true
  fi
  
  echo "nameserver 8.8.8.8" > /tmp/resolv.conf
  echo "nameserver 8.8.4.4" >> /tmp/resolv.conf
  cp -f /tmp/resolv.conf /etc/resolv.conf 2>/dev/null || {
    echo "nameserver 8.8.8.8" | sudo tee /etc/resolv.conf >/dev/null 2>&1
    echo "nameserver 8.8.4.4" | sudo tee -a /etc/resolv.conf >/dev/null 2>&1
  }
  rm -f /tmp/resolv.conf
  
  chmod 644 /etc/resolv.conf 2>/dev/null || true
  echo "✅ DNS configuration complete"
fi

echo "Installing dependencies..."
apt update -y
apt install -y curl python3 jq nano iptables iptables-persistent ethtool dnsutils python3-minimal net-tools iproute2

if ! command -v tc &> /dev/null; then
    echo -e "${YELLOW}⚠️  tc command not found, installing iproute2 specifically...${NC}"
    apt install -y iproute2
fi

echo "Installing dnstt-server..."
if ! curl -fsSL https://dnstt.network/dnstt-server-linux-amd64 -o /usr/local/bin/dnstt-server 2>/dev/null; then
    echo -e "${YELLOW}⚠️  Primary download failed, trying alternative...${NC}"
    curl -fsSL https://github.com/NoXFiQ/Elite-X-dns.sh/raw/main/dnstt-server -o /usr/local/bin/dnstt-server 2>/dev/null || {
        echo -e "${RED}❌ Failed to download dnstt-server${NC}"
        exit 1
    }
fi
chmod +x /usr/local/bin/dnstt-server

echo "Setting static DNSTT keys..."
mkdir -p /etc/dnstt

# Force overwrite keys (ensure only ONE key is used)
rm -f /etc/dnstt/server.key
rm -f /etc/dnstt/server.pub

# ==============================
# STATIC PRIVATE KEY (FIXED)
# ==============================
cat > /etc/dnstt/server.key <<'EOF'
819d82813183e4be3ca1ad74387e47c0c993b81c601b2d1473a3f47731c404ae
EOF

# ==============================
# STATIC PUBLIC KEY (FIXED)
# ==============================
cat > /etc/dnstt/server.pub <<'EOF'
7fbd1f8aa0abfe15a7903e837f78aba39cf61d36f183bd604daa2fe4ef3b7b59
EOF

# Set correct permissions
chmod 600 /etc/dnstt/server.key
chmod 644 /etc/dnstt/server.pub

echo -e "${GREEN}✅ Static DNSTT keys installed successfully${NC}"

echo "Creating dnstt-elite-x.service..."
cat >/etc/systemd/system/dnstt-elite-x.service <<EOF
[Unit]
Description=AMOKHAN-CYBER DNSTT Server
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=/tmp
ExecStart=/usr/local/bin/dnstt-server -udp :${DNSTT_PORT} -mtu ${MTU} -privkey-file /etc/dnstt/server.key ${TDOMAIN} 127.0.0.1:22
Restart=always
RestartSec=5
KillSignal=SIGTERM
LimitNOFILE=1048576
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "Installing EDNS proxy..."
cat >/usr/local/bin/dnstt-edns-proxy.py <<'EOF'
#!/usr/bin/env python3
import socket
import threading
import struct
import sys
import time
import os
import signal

L=5300
running = True

def signal_handler(sig, frame):
    global running
    running = False
    sys.stderr.write("\nShutting down...\n")
    sys.exit(0)

signal.signal(signal.SIGINT, signal_handler)
signal.signal(signal.SIGTERM, signal_handler)

def modify_edns(d, max_size):
    if len(d) < 12:
        return d
    try:
        q, a, n, r = struct.unpack("!HHHH", d[4:12])
    except:
        return d
    
    o = 12
    
    def skip_name(b, o):
        while o < len(b):
            l = b[o]
            o += 1
            if l == 0:
                break
            if l & 0xC0 == 0xC0:
                o += 1
                break
            o += l
        return o
    
    for _ in range(q):
        o = skip_name(d, o)
        o += 4
    
    for _ in range(a + n):
        o = skip_name(d, o)
        if o + 10 > len(d):
            return d
        try:
            _, _, _, l = struct.unpack("!HHIH", d[o:o+10])
        except:
            return d
        o += 10 + l
    
    modified = bytearray(d)
    for _ in range(r):
        o = skip_name(d, o)
        if o + 10 > len(d):
            return d
        t = struct.unpack("!H", d[o:o+2])[0]
        if t == 41:
            modified[o+2:o+4] = struct.pack("!H", max_size)
            return bytes(modified)
        _, _, l = struct.unpack("!HIH", d[o+2:o+10])
        o += 10 + l
    
    return d

def handle_request(sock, data, addr):
    client = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    client.settimeout(5)
    try:
        modified_data = modify_edns(data, 1800)
        client.sendto(modified_data, ('127.0.0.1', L))
        response, _ = client.recvfrom(4096)
        modified_response = modify_edns(response, 512)
        sock.sendto(modified_response, addr)
    except Exception as e:
        sys.stderr.write(f"Error in handler: {e}\n")
    finally:
        client.close()

def main():
    global running
    
    server = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    
    os.system("fuser -k 53/udp 2>/dev/null || true")
    time.sleep(2)
    
    for attempt in range(3):
        try:
            server.bind(('0.0.0.0', 53))
            sys.stderr.write(f"✅ EDNS Proxy started on port 53 (forwarding to {L})\n")
            sys.stderr.flush()
            break
        except Exception as e:
            if attempt < 2:
                sys.stderr.write(f"Attempt {attempt+1} failed, retrying...\n")
                time.sleep(2)
                os.system("fuser -k 53/udp 2>/dev/null || true")
            else:
                sys.stderr.write(f"❌ Failed to bind to port 53 after 3 attempts: {e}\n")
                sys.exit(1)
    
    while running:
        try:
            data, addr = server.recvfrom(4096)
            threading.Thread(target=handle_request, args=(server, data, addr), daemon=True).start()
        except Exception as e:
            if running:
                sys.stderr.write(f"Error in main loop: {e}\n")
                time.sleep(1)

if __name__ == "__main__":
    main()
EOF
chmod +x /usr/local/bin/dnstt-edns-proxy.py

python3 -m py_compile /usr/local/bin/dnstt-edns-proxy.py || {
    echo -e "${YELLOW}⚠️  Python syntax check failed, installing python3-full...${NC}"
    apt install -y python3-full
}

cat >/etc/systemd/system/dnstt-elite-x-proxy.service <<EOF
[Unit]
Description=AMOKHAN-CYBER Proxy
After=network.target
Wants=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/bin/python3 /usr/local/bin/dnstt-edns-proxy.py
Restart=always
RestartSec=3
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

command -v ufw >/dev/null && ufw allow 22/tcp && ufw allow 53/udp || true

echo -e "${YELLOW}Cleaning up ports...${NC}"
fuser -k 53/udp 2>/dev/null || true
fuser -k 5300/udp 2>/dev/null || true
sleep 3

setup_bandwidth_manager
setup_connection_monitor  
setup_traffic_monitor
setup_speed_optimizer
setup_auto_remover

cat > /etc/systemd/system/elite-x-traffic.service <<EOF
[Unit]
Description=AMOKHAN-CYBER Traffic Monitor
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-traffic
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/elite-x-cleaner.service <<EOF
[Unit]
Description=AMOKHAN-CYBER Auto Remover
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/elite-x-cleaner
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable dnstt-elite-x.service dnstt-elite-x-proxy.service elite-x-traffic.service elite-x-cleaner.service elite-x-connmon.service

echo -e "${YELLOW}Starting DNSTT Server...${NC}"
systemctl start dnstt-elite-x.service
sleep 5

if systemctl is-active dnstt-elite-x >/dev/null 2>&1; then
    echo -e "${GREEN}✅ DNSTT Server is running${NC}"
    
    echo -e "${YELLOW}Starting DNSTT Proxy...${NC}"
    systemctl start dnstt-elite-x-proxy.service
    sleep 3
else
    echo -e "${YELLOW}⚠️  DNSTT Server not running, checking logs...${NC}"
    journalctl -u dnstt-elite-x -n 10 --no-pager
    echo -e "${YELLOW}Attempting to start Proxy anyway...${NC}"
    systemctl start dnstt-elite-x-proxy.service
    sleep 3
fi

systemctl start elite-x-traffic.service
systemctl start elite-x-cleaner.service
systemctl start elite-x-connmon.service

echo -e "\n${CYAN}Service Status:${NC}"
systemctl is-active dnstt-elite-x >/dev/null 2>&1 && echo -e "${GREEN}✅ DNSTT Server: Running${NC}" || echo -e "${RED}❌ DNSTT Server: Failed${NC}"
systemctl is-active dnstt-elite-x-proxy >/dev/null 2>&1 && echo -e "${GREEN}✅ DNSTT Proxy: Running${NC}" || echo -e "${RED}❌ DNSTT Proxy: Failed${NC}"
systemctl is-active elite-x-traffic >/dev/null 2>&1 && echo -e "${GREEN}✅ Traffic Monitor: Running${NC}" || echo -e "${RED}❌ Traffic Monitor: Failed${NC}"
systemctl is-active elite-x-connmon >/dev/null 2>&1 && echo -e "${GREEN}✅ Auto-Ban Monitor: Running${NC}" || echo -e "${RED}❌ Auto-Ban Monitor: Failed${NC}"

echo -e "\n${CYAN}Port Status:${NC}"
ss -uln | grep -q ":53 " && echo -e "${GREEN}✅ Port 53: Listening${NC}" || echo -e "${RED}❌ Port 53: Not listening${NC}"
ss -uln | grep -q ":${DNSTT_PORT} " && echo -e "${GREEN}✅ Port ${DNSTT_PORT}: Listening${NC}" || echo -e "${RED}❌ Port ${DNSTT_PORT}: Not listening${NC}"

/usr/local/bin/elite-x-speed manual

for iface in $(ls /sys/class/net/ | grep -v lo); do
    ethtool -K $iface tx off sg off tso off 2>/dev/null || true
    ip link set dev $iface txqueuelen 10000 2>/dev/null || true
done

systemctl daemon-reload
systemctl restart dnstt-elite-x dnstt-elite-x-proxy

cat >/usr/local/bin/elite-x-user <<'EOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m';WHITE='\033[1;37m';BOLD='\033[1m';NC='\033[0m'

show_quote() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}            Always Remember ELITE-X when you see X      ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

UD="/etc/elite-x/users"
TD="/etc/elite-x/traffic"
CD="/etc/elite-x/connections"
DD="/etc/elite-x/deleted"
BD="/etc/elite-x/banned"
mkdir -p $UD $TD $CD $DD $BD

user_exists_in_system() {
    local username="$1"
    if id "$username" &>/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Get realtime traffic
get_realtime_traffic() {
    local username="$1"
    
    if [ -f "$TD/$username" ]; then
        cat "$TD/$username" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Get realtime connections
get_user_logins() {
    local username="$1"
    
    if [ -f "$CD/$username" ]; then
        cat "$CD/$username" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

add_user() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}              CREATE SSH + DNS USER                            ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Password: "$NC)" password
    read -p "$(echo -e $GREEN"Expire days: "$NC)" days
    read -p "$(echo -e $GREEN"Connection limit (1-10, default 2): "$NC)" conn_limit
    conn_limit=${conn_limit:-2}
    
    if id "$username" &>/dev/null; then
        echo -e "${RED}User already exists!${NC}"
        return
    fi
    
    useradd -m -s /bin/false "$username"
    echo "$username:$password" | chpasswd
    
    expire_date=$(date -d "+$days days" +"%Y-%m-%d")
    chage -E "$expire_date" "$username"
    
    cat > $UD/$username <<INFO
Username: $username
Password: $password
Expire: $expire_date
Conn_Limit: $conn_limit
Created: $(date +"%Y-%m-%d %H:%M:%S")
INFO
    
    echo "0" > $TD/$username
    echo "0" > $CD/$username
    
    # Add bandwidth limit for user
    /usr/local/bin/elite-x-bandwidth add "$username" 2>/dev/null || true
    
    SERVER=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "?")
    PUBKEY=$(cat /etc/dnstt/server.pub 2>/dev/null || echo "Not generated")
    
    clear
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${YELLOW}                  USER DETAILS                                   ${GREEN}║${NC}"
    echo -e "${GREEN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║${WHITE}  Username  :${CYAN} $username${NC}"
    echo -e "${GREEN}║${WHITE}  Password  :${CYAN} $password${NC}"
    echo -e "${GREEN}║${WHITE}  Server    :${CYAN} $SERVER${NC}"
    echo -e "${GREEN}║${WHITE}  Public Key:${CYAN} $PUBKEY${NC}"
    echo -e "${GREEN}║${WHITE}  Expire    :${CYAN} $expire_date${NC}"
    echo -e "${GREEN}║${WHITE}  Max Login :${CYAN} $conn_limit connection(s)${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    show_quote
}

show_user_details() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    
    if [ ! -f "$UD/$username" ]; then
        echo -e "${RED}User not found!${NC}"
        return
    fi
    
    if ! user_exists_in_system "$username"; then
        echo -e "${RED}User does not exist in system! Cleaning up...${NC}"
        rm -f "$UD/$username" "$TD/$username" "$CD/$username"
        return
    fi
    
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                  USER DETAILS (REALTIME)                         ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    
    while IFS= read -r line; do
        echo -e "${CYAN}║${WHITE}  $line${NC}"
    done < "$UD/$username"
    
    current_conn=$(get_user_logins "$username")
    limit=$(grep "Conn_Limit:" "$UD/$username" | cut -d' ' -f2)
    echo -e "${CYAN}║${WHITE}  Current Connections: ${YELLOW}$current_conn/$limit${NC}"
    
    traffic_used=$(get_realtime_traffic "$username")
    echo -e "${CYAN}║${WHITE}  Traffic Used: ${GREEN}${traffic_used} MB${NC}"
    
    # Check if blocked
    if passwd -S "$username" 2>/dev/null | grep -q "L"; then
        echo -e "${CYAN}║${WHITE}  Account Status: ${RED}BLOCKED${NC}"
        if [ -f "$BD/$username" ]; then
            last_ban=$(tail -1 "$BD/$username" 2>/dev/null)
            echo -e "${CYAN}║${WHITE}  Last Block: ${YELLOW}$last_ban${NC}"
        fi
    else
        echo -e "${CYAN}║${WHITE}  Account Status: ${GREEN}ACTIVE${NC}"
    fi
    
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    show_quote
}

renew_user() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"Additional days: "$NC)" days
    
    if [ ! -f "$UD/$username" ]; then
        echo -e "${RED}User not found!${NC}"
        return
    fi
    
    if ! user_exists_in_system "$username"; then
        echo -e "${RED}User does not exist in system! Cleaning up...${NC}"
        rm -f "$UD/$username" "$TD/$username" "$CD/$username"
        return
    fi
    
    current_expire=$(grep "Expire:" "$UD/$username" | cut -d' ' -f2)
    new_expire=$(date -d "$current_expire +$days days" +"%Y-%m-%d")
    
    sed -i "s/Expire: .*/Expire: $new_expire/" "$UD/$username"
    chage -E "$new_expire" "$username"
    
    # Unblock if blocked
    if passwd -S "$username" 2>/dev/null | grep -q "L"; then
        usermod -U "$username" 2>/dev/null
        echo "$(date) - AUTO-UNBLOCKED after renewal" >> "$BD/$username"
    fi
    
    echo -e "${GREEN}✅ User renewed until $new_expire${NC}"
    show_quote
}

set_login_limit() {
    read -p "$(echo -e $GREEN"Username: "$NC)" username
    read -p "$(echo -e $GREEN"New connection limit (1-10): "$NC)" new_limit
    
    if [ ! -f "$UD/$username" ]; then
        echo -e "${RED}User not found!${NC}"
        return
    fi
    
    if ! user_exists_in_system "$username"; then
        echo -e "${RED}User does not exist in system! Cleaning up...${NC}"
        rm -f "$UD/$username" "$TD/$username" "$CD/$username"
        return
    fi
    
    if grep -q "Conn_Limit:" "$UD/$username"; then
        sed -i "s/Conn_Limit: .*/Conn_Limit: $new_limit/" "$UD/$username"
    else
        echo "Conn_Limit: $new_limit" >> "$UD/$username"
    fi
    
    echo -e "${GREEN}✅ Login limit updated to $new_limit${NC}"
    show_quote
}

show_deleted_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                   DELETED USERS                                 ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    
    if [ -z "$(ls -A $DD 2>/dev/null)" ]; then
        echo -e "${CYAN}║${RED}  No deleted users found${NC}"
    else
        printf "%-15s %-12s %-12s\n" "USERNAME" "EXPIRED" "DELETED"
        echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
        
        for user in $DD/*; do
            [ ! -f "$user" ] && continue
            u=$(basename "$user" | cut -d'_' -f1)
            ex=$(grep "Expire:" "$user" 2>/dev/null | cut -d' ' -f2)
            dl=$(stat -c %y "$user" 2>/dev/null | cut -d' ' -f1)
            printf "%-15s %-12s %-12s\n" "$u" "$ex" "$dl"
        done
    fi
    
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    show_quote
}

restore_user() {
    read -p "$(echo -e $GREEN"Username to restore: "$NC)" username
    
    # Find latest backup
    latest_backup=$(ls -t $DD/${username}_* 2>/dev/null | head -1)
    
    if [ -z "$latest_backup" ] || [ ! -f "$latest_backup" ]; then
        echo -e "${RED}User not found in deleted list!${NC}"
        return
    fi
    
    # Extract user info
    pass=$(grep "Password:" "$latest_backup" | head -1 | cut -d' ' -f2)
    expire=$(grep "Expire:" "$latest_backup" | head -1 | cut -d' ' -f2)
    conn_limit=$(grep "Conn_Limit:" "$latest_backup" | head -1 | cut -d' ' -f2)
    conn_limit=${conn_limit:-2}
    
    # Recreate user
    useradd -m -s /bin/false "$username"
    echo "$username:$pass" | chpasswd
    chage -E "$expire" "$username"
    
    # Restore user file
    cp "$latest_backup" "$UD/$username"
    
    # Remove from deleted
    rm -f "$latest_backup"
    
    echo -e "${GREEN}✅ User $username restored${NC}"
    show_quote
}

list_users() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                     ACTIVE USERS (REALTIME)                      ${CYAN}║${NC}"
    echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
    
    if [ -z "$(ls -A $UD 2>/dev/null)" ]; then
        echo -e "${CYAN}║${RED}  No users found${NC}"
        echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
        show_quote
        return
    fi
    
    printf "%-12s %-10s %-10s %-8s %-8s\n" "USERNAME" "EXPIRE" "LOGIN" "LIMIT" "STATUS"
    echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
    
    TOTAL_USERS=0
    ONLINE_COUNT=0
    BLOCKED_COUNT=0
    
    for user in $UD/*; do
        [ ! -f "$user" ] && continue
        u=$(basename "$user")
        
        if ! user_exists_in_system "$u"; then
            echo -e "${YELLOW}⚠️  Orphaned entry for $u - cleaning up${NC}"
            rm -f "$user" "$TD/$u" "$CD/$u"
            continue
        fi
        
        ex=$(grep "Expire:" "$user" | cut -d' ' -f2)
        limit=$(grep "Conn_Limit:" "$user" | cut -d' ' -f2)
        limit=${limit:-2}
        
        # Get realtime data
        current_conn=$(get_user_logins "$u")
        
        if [ "$current_conn" -gt 0 ]; then
            ONLINE_COUNT=$((ONLINE_COUNT + 1))
        fi
        
        # Format login display
        if [ "$current_conn" -ge "$limit" ]; then
            login_display="${RED}$current_conn${NC}"
        else
            login_display="${GREEN}$current_conn${NC}"
        fi
        
        # Check status
        if passwd -S "$u" 2>/dev/null | grep -q "L"; then
            status="${RED}BLOCKED${NC}"
            BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
        elif [ "$current_conn" -gt 0 ]; then
            status="${GREEN}ONLINE${NC}"
        else
            status="${YELLOW}OFFLINE${NC}"
        fi
        
        # Highlight if near expiry
        days_left=$(( ($(date -d "$ex" +%s) - $(date +%s)) / 86400 ))
        if [ $days_left -le 3 ]; then
            ex="${RED}$ex${NC}"
        elif [ $days_left -le 7 ]; then
            ex="${YELLOW}$ex${NC}"
        fi
        
        printf "%-12s %-10b %-10b %-8s %-8b\n" "$u" "$ex" "$login_display" "$limit" "$status"
        TOTAL_USERS=$((TOTAL_USERS + 1))
    done
    
    echo -e "${CYAN}─────────────────────────────────────────────────────────────${NC}"
    echo -e "Total Users: ${GREEN}$TOTAL_USERS${NC} | Online: ${CYAN}$ONLINE_COUNT${NC} | Blocked: ${RED}$BLOCKED_COUNT${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    show_quote
}

lock_user() { 
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    if [ -f "$UD/$u" ]; then
        if user_exists_in_system "$u"; then
            usermod -L "$u" 2>/dev/null
            pkill -u "$u" 2>/dev/null
            echo "$(date) - MANUALLY LOCKED by admin" >> "$BD/$u"
            echo -e "${GREEN}✅ User locked and disconnected${NC}"
        else
            echo -e "${RED}User does not exist in system! Cleaning up...${NC}"
            rm -f "$UD/$u" "$TD/$u" "$CD/$u"
        fi
    else
        echo -e "${RED}User not found${NC}"
    fi
    show_quote
}

unlock_user() { 
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    if [ -f "$UD/$u" ]; then
        if user_exists_in_system "$u"; then
            usermod -U "$u" 2>/dev/null
            echo "$(date) - MANUALLY UNLOCKED by admin" >> "$BD/$u"
            echo -e "${GREEN}✅ User unlocked${NC}"
        else
            echo -e "${RED}User does not exist in system! Cleaning up...${NC}"
            rm -f "$UD/$u" "$TD/$u" "$CD/$u"
        fi
    else
        echo -e "${RED}User not found${NC}"
    fi
    show_quote
}

delete_user() { 
    read -p "$(echo -e $GREEN"Username: "$NC)" u
    
    if [ ! -f "$UD/$u" ]; then
        echo -e "${RED}User not found!${NC}"
        return
    fi
    
    # Backup user info
    cp "$UD/$u" "$DD/${u}_$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
    
    # Remove bandwidth limits
    /usr/local/bin/elite-x-bandwidth remove "$u" 2>/dev/null || true
    
    # Kill user processes
    pkill -u "$u" 2>/dev/null || true
    
    # Delete user
    userdel -r "$u" 2>/dev/null
    rm -f "$UD/$u" "$TD/$u" "$CD/$u" "$BD/$u"
    
    echo -e "${GREEN}✅ User deleted and backed up${NC}"
    show_quote
}

view_ban_history() {
    clear
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}                      BAN HISTORY                                  ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    if [ -z "$(ls -A $BD 2>/dev/null)" ]; then
        echo -e "${YELLOW}No ban history found${NC}"
    else
        for ban_file in $BD/*; do
            [ -f "$ban_file" ] || continue
            username=$(basename "$ban_file")
            echo -e "${CYAN}User: $username${NC}"
            echo "────────────────"
            cat "$ban_file"
            echo ""
        done
    fi
    
    echo ""
    read -p "Press Enter to continue..."
}

case $1 in
    add) add_user ;;
    list) list_users ;;
    details) show_user_details ;;
    renew) renew_user ;;
    setlimit) set_login_limit ;;
    deleted) show_deleted_users ;;
    restore) restore_user ;;
    lock) lock_user ;;
    unlock) unlock_user ;;
    del) delete_user ;;
    banhistory) view_ban_history ;;
    *) echo "Usage: elite-x-user {add|list|details|renew|setlimit|deleted|restore|lock|unlock|del|banhistory}" ;;
esac
EOF
chmod +x /usr/local/bin/elite-x-user

cat >/usr/local/bin/elite-x <<'EOF'
#!/bin/bash

RED='\033[0;31m';GREEN='\033[0;32m';YELLOW='\033[1;33m';CYAN='\033[0;36m'
PURPLE='\033[0;35m';WHITE='\033[1;37m';BOLD='\033[1m';NC='\033[0m'

show_quote() {
    echo ""
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}            Always Remember ELITE-X when you see X      ${CYAN}║${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                                                               ${CYAN}║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

if [ -f /tmp/elite-x-running ]; then
    exit 0
fi
touch /tmp/elite-x-running
trap 'rm -f /tmp/elite-x-running' EXIT

show_dashboard() {
    clear
    
    IP=$(cat /etc/elite-x/cached_ip 2>/dev/null || curl -s ifconfig.me 2>/dev/null || echo "Unknown")
    LOC=$(cat /etc/elite-x/cached_location 2>/dev/null || echo "Unknown")
    ISP=$(cat /etc/elite-x/cached_isp 2>/dev/null || echo "Unknown")
    RAM=$(free -m | awk '/^Mem:/{print $3"/"$2"MB"}')
    SUB=$(cat /etc/elite-x/subdomain 2>/dev/null || echo "Not configured")
    ACTIVATION_KEY=$(cat /etc/elite-x/key 2>/dev/null || echo "AMOKHAN-CYBER TZ")
    
    LOCATION=$(cat /etc/elite-x/location 2>/dev/null || echo "South Africa")
    CURRENT_MTU=$(cat /etc/elite-x/mtu 2>/dev/null || echo "1800")
    
    DNS=$(systemctl is-active dnstt-elite-x 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    PRX=$(systemctl is-active dnstt-elite-x-proxy 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    CONN=$(systemctl is-active elite-x-connmon 2>/dev/null | grep -q active && echo "${GREEN}●${NC}" || echo "${RED}●${NC}")
    
    TOTAL_USERS=$(ls -1 /etc/elite-x/users 2>/dev/null | wc -l)
    ONLINE_USERS=$(ps aux | grep "sshd:" | grep -v grep | awk '{print $1}' | sort -u | wc -l)
    BLOCKED_USERS=$(passwd -S $(ls /etc/elite-x/users 2>/dev/null) 2>/dev/null | grep " L " | wc -l)
    
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${YELLOW}${BOLD}                 AMOKHAN-CYBER REALTIME v3.0                  ${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${WHITE}  Subdomain :${GREEN} $SUB${NC}"
    echo -e "${CYAN}║${WHITE}  IP        :${GREEN} $IP${NC}"
    echo -e "${CYAN}║${WHITE}  Location  :${GREEN} $LOC${NC}"
    echo -e "${CYAN}║${WHITE}  ISP       :${GREEN} $ISP${NC}"
    echo -e "${CYAN}║${WHITE}  RAM       :${GREEN} $RAM${NC}"
    echo -e "${CYAN}║${WHITE}  VPS Loc   :${GREEN} $LOCATION (MTU: $CURRENT_MTU)${NC}"
    echo -e "${CYAN}║${WHITE}  Services  : DNS:$DNS PRX:$PRX MON:$CONN${NC}"
    echo -e "${CYAN}║${WHITE}  Real-Time :${GREEN} $TOTAL_USERS users, $ONLINE_USERS online, $BLOCKED_USERS blocked${NC}"
    echo -e "${CYAN}║${WHITE}  Developer :${PURPLE} ELITE-X TEAM${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${WHITE}  Version   :${YELLOW} V2.0 REALTIME - Unlimited${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

change_mtu() {
    echo -e "${YELLOW}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${YELLOW}║${WHITE}                    CHANGE MTU VALUE                              ${YELLOW}║${NC}"
    echo -e "${YELLOW}╠═══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${YELLOW}║${WHITE}  Current MTU: $(cat /etc/elite-x/mtu)${NC}"
    echo -e "${YELLOW}║${WHITE}  Recommended: 1800 (South Africa), 1500 (USA/Europe), 1400 (Asia)${NC}"
    echo -e "${YELLOW}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    read -p "$(echo -e $GREEN"New MTU (1000-5000): "$NC)" mtu
    
    if [[ "$mtu" =~ ^[0-9]+$ ]] && [ $mtu -ge 1000 ] && [ $mtu -le 5000 ]; then
        echo "$mtu" > /etc/elite-x/mtu
        sed -i "s/-mtu [0-9]*/-mtu $mtu/" /etc/systemd/system/dnstt-elite-x.service
        systemctl daemon-reload
        systemctl restart dnstt-elite-x dnstt-elite-x-proxy
        echo -e "${GREEN}✅ MTU updated to $mtu${NC}"
    else
        echo -e "${RED}❌ Invalid MTU (must be 1000-5000)${NC}"
    fi
    read -p "Press Enter to continue..."
}

settings_menu() {
    while true; do
        clear
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${YELLOW}${BOLD}                      SETTINGS MENU                              ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${WHITE}  [8]  🔑 View Public Key${NC}"
        echo -e "${CYAN}║${WHITE}  [9]  Change MTU Value${NC}"
        echo -e "${CYAN}║${WHITE}  [10] ⚡ Manual Speed Optimization${NC}"
        echo -e "${CYAN}║${WHITE}  [11] 🧹 Clean Junk Files${NC}"
        echo -e "${CYAN}║${WHITE}  [12] 🔄 Auto Expired Account Remover${NC}"
        echo -e "${CYAN}║${WHITE}  [13] Restart All Services${NC}"
        echo -e "${CYAN}║${WHITE}  [14] Reboot VPS${NC}"
        echo -e "${CYAN}║${WHITE}  [15] Uninstall Script${NC}"
        echo -e "${CYAN}║${WHITE}  [16] 🌍 Re-apply Location Optimization${NC}"
        echo -e "${CYAN}║${WHITE}  [17] View Bandwidth Stats${NC}"
        echo -e "${CYAN}║${WHITE}  [18] View Ban History${NC}"
        echo -e "${CYAN}║${WHITE}  [19] 🔓 Unblock All Users${NC}"
        echo -e "${CYAN}║${WHITE}  [0]  Back to Main Menu${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        read -p "$(echo -e $GREEN"Settings option: "$NC)" ch
        
        case $ch in
            8)
                echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${YELLOW}                    PUBLIC KEY                                    ${CYAN}║${NC}"
                echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
                echo -e "${CYAN}║${GREEN}  $(cat /etc/dnstt/server.pub)${NC}"
                echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
                read -p "Press Enter to continue..."
                ;;
            9) change_mtu ;;
            10) elite-x-speed manual; read -p "Press Enter to continue..." ;;
            11) elite-x-speed clean; read -p "Press Enter to continue..." ;;
            12)
                systemctl enable --now elite-x-cleaner.service
                echo -e "${GREEN}✅ Auto remover started${NC}"
                read -p "Press Enter to continue..."
                ;;
            13)
                systemctl restart dnstt-elite-x dnstt-elite-x-proxy elite-x-connmon sshd
                echo -e "${GREEN}✅ Services restarted${NC}"
                read -p "Press Enter to continue..."
                ;;
            14)
                read -p "Reboot? (y/n): " c
                [ "$c" = "y" ] && reboot
                ;;
            15)
                read -p "Uninstall? (YES): " c
                [ "$c" = "YES" ] && {
                    echo -e "${YELLOW}🔄 Removing all users and data...${NC}"
                    
                    if [ -d "/etc/elite-x/users" ]; then
                        for user_file in /etc/elite-x/users/*; do
                            if [ -f "$user_file" ]; then
                                username=$(basename "$user_file")
                                echo -e "  Removing user: $username"
                                userdel -r "$username" 2>/dev/null || true
                                pkill -u "$username" 2>/dev/null || true
                            fi
                        done
                    fi
                    
                    pkill -f dnstt-server 2>/dev/null || true
                    pkill -f dnstt-edns-proxy 2>/dev/null || true
                    pkill -f elite-x-traffic 2>/dev/null || true
                    pkill -f elite-x-cleaner 2>/dev/null || true
                    pkill -f elite-x-connmon 2>/dev/null || true
                    
                    systemctl stop dnstt-elite-x dnstt-elite-x-proxy elite-x-traffic elite-x-cleaner elite-x-connmon 2>/dev/null || true
                    systemctl disable dnstt-elite-x dnstt-elite-x-proxy elite-x-traffic elite-x-cleaner elite-x-connmon 2>/dev/null || true
                    
                    rm -rf /etc/systemd/system/dnstt-elite-x*
                    rm -rf /etc/systemd/system/elite-x-*
                    rm -rf /etc/dnstt /etc/elite-x
                    rm -f /usr/local/bin/dnstt-*
                    rm -f /usr/local/bin/elite-x*
                    
                    sed -i '/^Banner/d' /etc/ssh/sshd_config
                    systemctl restart sshd
                    
                    rm -f /etc/profile.d/elite-x-dashboard.sh
                    sed -i '/elite-x/d' ~/.bashrc
                    sed -i '/ELITE_X_SHOWN/d' ~/.bashrc
                    
                    rm -f /etc/cron.hourly/elite-x-expiry
                    
                    echo -e "${GREEN}✅ Uninstalled completely${NC}"
                    rm -f /tmp/elite-x-running
                    exit 0
                }
                read -p "Press Enter to continue..."
                ;;
            16)
                echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
                echo -e "${GREEN}           RE-APPLY LOCATION OPTIMIZATION                        ${NC}"
                echo -e "${YELLOW}═══════════════════════════════════════════════════════════════${NC}"
                echo -e "${WHITE}Select your VPS location:${NC}"
                echo -e "${GREEN}  1. South Africa (MTU 1800)${NC}"
                echo -e "${CYAN}  2. USA (MTU 1500)${NC}"
                echo -e "${BLUE}  3. Europe (MTU 1500)${NC}"
                echo -e "${PURPLE}  4. Asia (MTU 1400)${NC}"
                echo -e "${YELLOW}  5. Custom MTU${NC}"
                read -p "Choice: " opt_choice
                
                case $opt_choice in
                    1) echo "South Africa" > /etc/elite-x/location
                       echo "1800" > /etc/elite-x/mtu
                       sed -i "s/-mtu [0-9]*/-mtu 1800/" /etc/systemd/system/dnstt-elite-x.service
                       systemctl daemon-reload
                       systemctl restart dnstt-elite-x dnstt-elite-x-proxy
                       echo -e "${GREEN}✅ South Africa selected (MTU 1800)${NC}" ;;
                    2) echo "USA" > /etc/elite-x/location
                       echo "1500" > /etc/elite-x/mtu
                       sed -i "s/-mtu [0-9]*/-mtu 1500/" /etc/systemd/system/dnstt-elite-x.service
                       systemctl daemon-reload
                       systemctl restart dnstt-elite-x dnstt-elite-x-proxy
                       echo -e "${GREEN}✅ USA selected (MTU 1500)${NC}" ;;
                    3) echo "Europe" > /etc/elite-x/location
                       echo "1500" > /etc/elite-x/mtu
                       sed -i "s/-mtu [0-9]*/-mtu 1500/" /etc/systemd/system/dnstt-elite-x.service
                       systemctl daemon-reload
                       systemctl restart dnstt-elite-x dnstt-elite-x-proxy
                       echo -e "${GREEN}✅ Europe selected (MTU 1500)${NC}" ;;
                    4) echo "Asia" > /etc/elite-x/location
                       echo "1400" > /etc/elite-x/mtu
                       sed -i "s/-mtu [0-9]*/-mtu 1400/" /etc/systemd/system/dnstt-elite-x.service
                       systemctl daemon-reload
                       systemctl restart dnstt-elite-x dnstt-elite-x-proxy
                       echo -e "${GREEN}✅ Asia selected (MTU 1400)${NC}" ;;
                    5) read -p "Enter MTU (1000-5000): " custom_mtu
                       if [[ "$custom_mtu" =~ ^[0-9]+$ ]] && [ $custom_mtu -ge 1000 ] && [ $custom_mtu -le 5000 ]; then
                           echo "Custom" > /etc/elite-x/location
                           echo "$custom_mtu" > /etc/elite-x/mtu
                           sed -i "s/-mtu [0-9]*/-mtu $custom_mtu/" /etc/systemd/system/dnstt-elite-x.service
                           systemctl daemon-reload
                           systemctl restart dnstt-elite-x dnstt-elite-x-proxy
                           echo -e "${GREEN}✅ Custom MTU $custom_mtu selected${NC}"
                       else
                           echo -e "${RED}Invalid MTU${NC}"
                       fi ;;
                esac
                read -p "Press Enter to continue..."
                ;;
            17)
                clear
                echo -e "${CYAN}╔═══════════════════════════════════════════════════════════════╗${NC}"
                echo -e "${CYAN}║${YELLOW}                  BANDWIDTH STATISTICS                           ${CYAN}║${NC}"
                echo -e "${CYAN}╠═══════════════════════════════════════════════════════════════╣${NC}"
                tc -s qdisc show
                echo -e "${CYAN}╚═══════════════════════════════════════════════════════════════╝${NC}"
                read -p "Press Enter to continue..."
                ;;
            18)
                elite-x-user banhistory
                read -p "Press Enter to continue..."
                ;;
            19)
                echo -e "${YELLOW}Unblocking all users...${NC}"
                for user in /etc/elite-x/users/*; do
                    if [ -f "$user" ]; then
                        username=$(basename "$user")
                        usermod -U "$username" 2>/dev/null
                        echo "$(date) - MANUALLY UNBLOCKED by admin" >> "/etc/elite-x/banned/$username"
                    fi
                done
                echo -e "${GREEN}✅ All users unblocked${NC}"
                read -p "Press Enter to continue..."
                ;;
            0) return ;;
            *) echo -e "${RED}Invalid option${NC}"; read -p "Press Enter to continue..." ;;
        esac
    done
}

main_menu() {
    while true; do
        show_dashboard
        echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║${GREEN}${BOLD}                         MAIN MENU                              ${CYAN}║${NC}"
        echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${CYAN}║${WHITE}  [1] Create SSH + DNS User${NC}"
        echo -e "${CYAN}║${WHITE}  [2] List All Users (REALTIME)${NC}"
        echo -e "${CYAN}║${WHITE}  [3] Show User Details (REALTIME)${NC}"
        echo -e "${CYAN}║${WHITE}  [4] Renew User${NC}"
        echo -e "${CYAN}║${WHITE}  [5] Set Login Limit${NC}"
        echo -e "${CYAN}║${WHITE}  [6] Show Deleted Users${NC}"
        echo -e "${CYAN}║${WHITE}  [7] Restore Deleted User${NC}"
        echo -e "${CYAN}║${WHITE}  [8] Lock User${NC}"
        echo -e "${CYAN}║${WHITE}  [9] Unlock User${NC}"
        echo -e "${CYAN}║${WHITE}  [10] Delete User${NC}"
        echo -e "${CYAN}║${WHITE}  [11] Create/Edit Banner${NC}"
        echo -e "${CYAN}║${WHITE}  [12] Delete Banner${NC}"
        echo -e "${CYAN}║${WHITE}  [13] View Ban History${NC}"
        echo -e "${CYAN}║${RED}  [S] ⚙️  Settings${NC}"
        echo -e "${CYAN}║${WHITE}  [00] Exit${NC}"
        echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        read -p "$(echo -e $GREEN"Main menu option: "$NC)" ch
        
        case $ch in
            1) elite-x-user add; read -p "Press Enter to continue..." ;;
            2) elite-x-user list; read -p "Press Enter to continue..." ;;
            3) elite-x-user details; read -p "Press Enter to continue..." ;;
            4) elite-x-user renew; read -p "Press Enter to continue..." ;;
            5) elite-x-user setlimit; read -p "Press Enter to continue..." ;;
            6) elite-x-user deleted; read -p "Press Enter to continue..." ;;
            7) elite-x-user restore; read -p "Press Enter to continue..." ;;
            8) elite-x-user lock; read -p "Press Enter to continue..." ;;
            9) elite-x-user unlock; read -p "Press Enter to continue..." ;;
            10) elite-x-user del; read -p "Press Enter to continue..." ;;
            11)
                [ -f /etc/elite-x/banner/custom ] || cp /etc/elite-x/banner/default /etc/elite-x/banner/custom
                nano /etc/elite-x/banner/custom
                cp /etc/elite-x/banner/custom /etc/elite-x/banner/ssh-banner
                systemctl restart sshd
                echo -e "${GREEN}✅ Banner saved${NC}"
                read -p "Press Enter to continue..."
                ;;
            12)
                rm -f /etc/elite-x/banner/custom
                cp /etc/elite-x/banner/default /etc/elite-x/banner/ssh-banner
                systemctl restart sshd
                echo -e "${GREEN}✅ Banner deleted${NC}"
                read -p "Press Enter to continue..."
                ;;
            13) elite-x-user banhistory; read -p "Press Enter to continue..." ;;
            [Ss]) settings_menu ;;
            00|0) 
                rm -f /tmp/elite-x-running
                show_quote
                echo -e "${GREEN}Goodbye!${NC}"
                exit 0 
                ;;
            *) echo -e "${RED}Invalid option${NC}"; read -p "Press Enter to continue..." ;;
        esac
    done
}

main_menu
EOF
chmod +x /usr/local/bin/elite-x

echo "Caching network information for fast login..."
IP=$(curl -4 -s ifconfig.me 2>/dev/null || echo "Unknown")
echo "$IP" > /etc/elite-x/cached_ip

if [ "$IP" != "Unknown" ]; then
    LOCATION_INFO=$(curl -s http://ip-api.com/json/$IP 2>/dev/null)
    echo "$LOCATION_INFO" | jq -r '.city + ", " + .country' 2>/dev/null > /etc/elite-x/cached_location || echo "Unknown" > /etc/elite-x/cached_location
    echo "$LOCATION_INFO" | jq -r '.isp' 2>/dev/null > /etc/elite-x/cached_isp || echo "Unknown" > /etc/elite-x/cached_isp
else
    echo "Unknown" > /etc/elite-x/cached_location
    echo "Unknown" > /etc/elite-x/cached_isp
fi

cat > /etc/profile.d/elite-x-dashboard.sh <<'EOF'
#!/bin/bash
if [ -f /usr/local/bin/elite-x ] && [ -z "$ELITE_X_SHOWN" ]; then
    export ELITE_X_SHOWN=1
    rm -f /tmp/elite-x-running 2>/dev/null
    /usr/local/bin/elite-x
fi
EOF
chmod +x /etc/profile.d/elite-x-dashboard.sh

cat >> ~/.bashrc <<'EOF'
# Auto-show ELITE-X dashboard
if [ -f /usr/local/bin/elite-x ] && [ -z "$ELITE_X_SHOWN" ]; then
    export ELITE_X_SHOWN=1
    rm -f /tmp/elite-x-running 2>/dev/null
    /usr/local/bin/elite-x
fi
EOF

echo "alias menu='elite-x'" >> ~/.bashrc
echo "alias elitex='elite-x'" >> ~/.bashrc

if [ ! -f /etc/elite-x/key ]; then
    if [ -f "$ACTIVATION_FILE" ]; then
        cp "$ACTIVATION_FILE" /etc/elite-x/key
    else
        echo "$ACTIVATION_KEY" > /etc/elite-x/key
    fi
fi

echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║       AMOKHAN-CYBER V3.0 REALTIME INSTALLED SUCCESSFULLY     ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
FINAL_MTU=$(cat /etc/elite-x/mtu 2>/dev/null || echo "1800")
ACTIVATION_KEY=$(cat /etc/elite-x/key 2>/dev/null || echo "AMOKHAN-CYBER TZ")
echo "DOMAIN  : ${TDOMAIN}"
echo "LOCATION: ${SELECTED_LOCATION}"
echo "MTU     : ${FINAL_MTU}"
echo "VERSION : V3.0 REALTIME (Unlimited)"
echo "╚═══════════════════════════════════════════════════════════════╝"
show_quote

echo -e "\n${CYAN}Final Service Status:${NC}"
sleep 2
systemctl is-active dnstt-elite-x >/dev/null 2>&1 && echo -e "${GREEN}✅ DNSTT Server: Running${NC}" || echo -e "${RED}❌ DNSTT Server: Failed${NC}"
systemctl is-active dnstt-elite-x-proxy >/dev/null 2>&1 && echo -e "${GREEN}✅ DNSTT Proxy: Running${NC}" || echo -e "${RED}❌ DNSTT Proxy: Failed${NC}"
systemctl is-active elite-x-connmon >/dev/null 2>&1 && echo -e "${GREEN}✅ Auto-Ban Monitor: Running${NC}" || echo -e "${RED}❌ Auto-Ban Monitor: Failed${NC}"

echo -e "\n${CYAN}Port Status:${NC}"
ss -uln | grep -q ":53 " && echo -e "${GREEN}✅ Port 53: Listening${NC}" || echo -e "${RED}❌ Port 53: Not listening${NC}"
ss -uln | grep -q ":${DNSTT_PORT} " && echo -e "${GREEN}✅ Port ${DNSTT_PORT}: Listening${NC}" || echo -e "${RED}❌ Port ${DNSTT_PORT}: Not listening${NC}"

echo -e "\n${GREEN}Features:${NC}"
echo -e "  ${YELLOW}→${NC} REALTIME Traffic Monitoring"
echo -e "  ${YELLOW}→${NC} AUTO-BAN for exceeding login limits"
echo -e "  ${YELLOW}→${NC} Auto-unblock when within limits"
echo -e "  ${YELLOW}→${NC} User Login Limit (Max concurrent connections)"
echo -e "  ${YELLOW}→${NC} Renew User Option"
echo -e "  ${YELLOW}→${NC} Deleted Users Archive"
echo -e "  ${YELLOW}→${NC} User Restore Function"
echo -e "  ${YELLOW}→${NC} Online Users Report"
echo -e "  ${YELLOW}→${NC} Ban History Viewer"

if ! systemctl is-active dnstt-elite-x >/dev/null 2>&1; then
    echo -e "\n${YELLOW}DNSTT Server Logs:${NC}"
    journalctl -u dnstt-elite-x -n 5 --no-pager
fi

read -p "Open menu now? (y/n): " open
if [ "$open" = "y" ]; then
    echo -e "${GREEN}Opening dashboard...${NC}"
    sleep 1
    /usr/local/bin/elite-x
else
    echo -e "${YELLOW}You can type 'menu' anytime to open the dashboard.${NC}"
fi

self_destruct