#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# Migration script: Redis 7.2+ (RDB v12) to Valkey 8.x
# This script converts RDB format version 12 (unsupported by Valkey 8) to a compatible format

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
REDIS_SERVICE="redis-xo"
REDIS_SOCKET="/run/redis-xo/redis.sock"
BACKUP_DIR="/var/lib/redis-xo-backup-$(date +%Y%m%d-%H%M%S)"
REDIS_DATA_DIR="/var/lib/redis-xo"
RDB_FILE="dump.rdb"
EXPORT_FILE="/tmp/redis-export-$(date +%Y%m%d-%H%M%S).json"
TEMP_REDIS_PORT=6380

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

check_service_exists() {
    if ! systemctl list-units --all | grep -q "${REDIS_SERVICE}.service"; then
        log_error "Service ${REDIS_SERVICE} not found"
        exit 1
    fi
}

check_dependencies() {
    local missing=()

    if ! command -v redis-cli &> /dev/null; then
        missing+=("redis-cli")
    fi

    if ! command -v redis-server &> /dev/null; then
        missing+=("redis-server")
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Missing required tools: ${missing[*]}"
        log_info "Install with: nix-shell -p redis"
        exit 1
    fi
}

detect_rdb_version() {
    local rdb_path="${REDIS_DATA_DIR}/${RDB_FILE}"

    if [[ ! -f "${rdb_path}" ]]; then
        log_warn "No RDB file found at: ${rdb_path}"
        return 1
    fi

    # Read the RDB header - format is "REDIS####" where #### is version
    local header=$(head -c 9 "${rdb_path}" 2>/dev/null || echo "")

    if [[ $header =~ ^REDIS([0-9]{4}) ]]; then
        local version="${BASH_REMATCH[1]}"
        # Remove leading zeros
        version=$((10#$version))
        echo $version
        return 0
    fi

    log_warn "Could not detect RDB version"
    return 1
}

create_backup() {
    log_info "Creating backup directory: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}"

    if [[ -d "${REDIS_DATA_DIR}" ]]; then
        log_info "Backing up Redis data directory..."
        cp -a "${REDIS_DATA_DIR}" "${BACKUP_DIR}/redis-data"
        log_success "Backup created at: ${BACKUP_DIR}"
    else
        log_error "Redis data directory not found: ${REDIS_DATA_DIR}"
        exit 1
    fi
}

start_temp_redis() {
    log_info "Starting temporary Redis server on port ${TEMP_REDIS_PORT}..."

    # Create temp config
    local temp_config="/tmp/redis-temp-$$.conf"
    cat > "${temp_config}" << EOF
port ${TEMP_REDIS_PORT}
bind 127.0.0.1
dir ${REDIS_DATA_DIR}
dbfilename ${RDB_FILE}
protected-mode yes
daemonize yes
pidfile /tmp/redis-temp-$$.pid
logfile /tmp/redis-temp-$$.log
EOF

    # Start Redis with the old RDB file
    redis-server "${temp_config}"

    # Wait for Redis to start
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if redis-cli -p ${TEMP_REDIS_PORT} PING &>/dev/null; then
            log_success "Temporary Redis server started"
            return 0
        fi
        sleep 1
        ((retries--))
    done

    log_error "Failed to start temporary Redis server"
    cat /tmp/redis-temp-$$.log
    rm -f "${temp_config}"
    return 1
}

stop_temp_redis() {
    log_info "Stopping temporary Redis server..."
    redis-cli -p ${TEMP_REDIS_PORT} SHUTDOWN NOSAVE &>/dev/null || true
    sleep 2

    # Clean up temp files
    rm -f /tmp/redis-temp-$$.conf /tmp/redis-temp-$$.pid /tmp/redis-temp-$$.log
}

export_data() {
    log_info "Exporting data from Redis..."

    local key_count=$(redis-cli -p ${TEMP_REDIS_PORT} DBSIZE | awk '{print $NF}')
    log_info "Found ${key_count} keys to export"

    if [[ "${key_count}" == "0" ]]; then
        log_warn "No keys to export - database is empty"
        echo "[]" > "${EXPORT_FILE}"
        return 0
    fi

    # Export all keys using redis-cli
    log_info "Exporting keys to ${EXPORT_FILE}..."

    # Get all keys and export them
    redis-cli -p ${TEMP_REDIS_PORT} --raw KEYS '*' | while IFS= read -r key; do
        local key_type=$(redis-cli -p ${TEMP_REDIS_PORT} TYPE "$key")

        case "$key_type" in
            string)
                local value=$(redis-cli -p ${TEMP_REDIS_PORT} GET "$key")
                local ttl=$(redis-cli -p ${TEMP_REDIS_PORT} TTL "$key")
                echo "SET|${key}|${value}|${ttl}" >> "${EXPORT_FILE}.tmp"
                ;;
            list)
                redis-cli -p ${TEMP_REDIS_PORT} LRANGE "$key" 0 -1 | while IFS= read -r value; do
                    echo "RPUSH|${key}|${value}|-1" >> "${EXPORT_FILE}.tmp"
                done
                ;;
            set)
                redis-cli -p ${TEMP_REDIS_PORT} SMEMBERS "$key" | while IFS= read -r value; do
                    echo "SADD|${key}|${value}|-1" >> "${EXPORT_FILE}.tmp"
                done
                ;;
            zset)
                redis-cli -p ${TEMP_REDIS_PORT} ZRANGE "$key" 0 -1 WITHSCORES | paste - - | while read value score; do
                    echo "ZADD|${key}|${score}|${value}|-1" >> "${EXPORT_FILE}.tmp"
                done
                ;;
            hash)
                redis-cli -p ${TEMP_REDIS_PORT} HGETALL "$key" | paste - - | while read field value; do
                    echo "HSET|${key}|${field}|${value}|-1" >> "${EXPORT_FILE}.tmp"
                done
                ;;
            *)
                log_warn "Unknown key type: ${key_type} for key: ${key}"
                ;;
        esac
    done

    if [[ -f "${EXPORT_FILE}.tmp" ]]; then
        mv "${EXPORT_FILE}.tmp" "${EXPORT_FILE}"
        local exported_count=$(wc -l < "${EXPORT_FILE}")
        log_success "Exported ${exported_count} operations to ${EXPORT_FILE}"
    else
        log_error "Export failed - no data file created"
        return 1
    fi
}

import_data() {
    log_info "Importing data into Valkey..."

    if [[ ! -f "${EXPORT_FILE}" ]]; then
        log_error "Export file not found: ${EXPORT_FILE}"
        return 1
    fi

    local import_count=0

    while IFS='|' read -r cmd key value ttl; do
        case "$cmd" in
            SET)
                redis-cli -s "${REDIS_SOCKET}" SET "$key" "$value" &>/dev/null
                if [[ "$ttl" != "-1" && "$ttl" -gt 0 ]]; then
                    redis-cli -s "${REDIS_SOCKET}" EXPIRE "$key" "$ttl" &>/dev/null
                fi
                ;;
            RPUSH)
                redis-cli -s "${REDIS_SOCKET}" RPUSH "$key" "$value" &>/dev/null
                ;;
            SADD)
                redis-cli -s "${REDIS_SOCKET}" SADD "$key" "$value" &>/dev/null
                ;;
            ZADD)
                redis-cli -s "${REDIS_SOCKET}" ZADD "$key" "$value" "$ttl" &>/dev/null
                ;;
            HSET)
                redis-cli -s "${REDIS_SOCKET}" HSET "$key" "$value" "$ttl" &>/dev/null
                ;;
        esac
        ((import_count++))

        # Progress indicator
        if (( import_count % 100 == 0 )); then
            echo -ne "\r${BLUE}[INFO]${NC} Imported ${import_count} operations..."
        fi
    done < "${EXPORT_FILE}"

    echo "" # New line after progress
    log_success "Imported ${import_count} operations into Valkey"
}

verify_valkey() {
    log_info "Verifying Valkey installation..."

    # Wait for socket to be ready
    local retries=10
    while [[ $retries -gt 0 ]]; do
        if [[ -S "${REDIS_SOCKET}" ]]; then
            break
        fi
        log_info "Waiting for socket to be ready..."
        sleep 1
        ((retries--))
    done

    if ! [[ -S "${REDIS_SOCKET}" ]]; then
        log_error "Socket not available: ${REDIS_SOCKET}"
        return 1
    fi

    if redis-cli -s "${REDIS_SOCKET}" PING 2>/dev/null | grep -q "PONG"; then
        log_success "Valkey is responding"

        local key_count=$(redis-cli -s "${REDIS_SOCKET}" DBSIZE 2>/dev/null | awk '{print $NF}')
        log_info "Database size: ${key_count} keys"

        return 0
    else
        log_error "Valkey is not responding"
        return 1
    fi
}

show_rollback_instructions() {
    cat << EOF

${YELLOW}=== ROLLBACK INSTRUCTIONS ===${NC}

If you need to rollback to the old Redis data:

1. Stop the service:
   sudo systemctl stop ${REDIS_SERVICE}

2. Restore the backup:
   sudo rm -rf ${REDIS_DATA_DIR}/*
   sudo cp -a ${BACKUP_DIR}/redis-data/* ${REDIS_DATA_DIR}/

3. Temporarily switch back to Redis in your NixOS config:
   In modules/features/xo/service.nix, comment out line 42:
   # services.redis.package = pkgs.valkey;

4. Rebuild:
   sudo nixos-rebuild switch

Backup location: ${BACKUP_DIR}
Export file: ${EXPORT_FILE}

EOF
}

main() {
    echo -e "${GREEN}============================================${NC}"
    echo -e "${GREEN}Redis RDB v12 to Valkey Migration Script${NC}"
    echo -e "${GREEN}============================================${NC}"
    echo ""

    check_root
    check_service_exists
    check_dependencies

    log_info "Starting migration process..."
    echo ""

    # Detect RDB version
    log_info "Step 1: Detecting RDB format version"
    if rdb_version=$(detect_rdb_version); then
        log_info "RDB format version: ${rdb_version}"
        if [[ $rdb_version -lt 12 ]]; then
            log_success "RDB version is compatible with Valkey 8"
            log_info "You may not need this migration script"
            read -p "$(echo -e ${YELLOW}Continue anyway? [y/N]: ${NC})" -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                exit 0
            fi
        else
            log_warn "RDB version 12 detected - incompatible with Valkey 8.x"
            log_info "This script will export and re-import your data"
        fi
    fi
    echo ""

    # Confirm with user
    read -p "$(echo -e ${YELLOW}This will stop services and migrate data. Continue? [y/N]: ${NC})" -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Migration cancelled by user"
        exit 0
    fi
    echo ""

    # Create backup
    log_info "Step 2: Creating backup"
    create_backup
    echo ""

    # Stop Valkey service
    log_info "Step 3: Stopping Valkey service"
    systemctl stop "${REDIS_SERVICE}" || true
    sleep 2
    echo ""

    # Start temporary Redis to export data
    log_info "Step 4: Starting temporary Redis server to read old RDB"
    if ! start_temp_redis; then
        log_error "Failed to start temporary Redis server"
        log_error "The RDB file may be corrupted or Redis is not available"
        exit 1
    fi
    echo ""

    # Export data
    log_info "Step 5: Exporting data from old Redis database"
    if ! export_data; then
        stop_temp_redis
        log_error "Data export failed"
        exit 1
    fi
    echo ""

    # Stop temp Redis
    stop_temp_redis
    echo ""

    # Remove old RDB file
    log_info "Step 6: Removing incompatible RDB file"
    rm -f "${REDIS_DATA_DIR}/${RDB_FILE}"
    log_success "Old RDB file removed"
    echo ""

    # Start Valkey with fresh database
    log_info "Step 7: Starting Valkey with fresh database"
    systemctl start "${REDIS_SERVICE}"
    sleep 3

    if ! systemctl is-active --quiet "${REDIS_SERVICE}"; then
        log_error "Failed to start Valkey"
        log_error "Check logs with: journalctl -u ${REDIS_SERVICE} -n 50"
        show_rollback_instructions
        exit 1
    fi
    log_success "Valkey started successfully"
    echo ""

    # Verify Valkey is working
    if ! verify_valkey; then
        log_error "Valkey verification failed"
        show_rollback_instructions
        exit 1
    fi
    echo ""

    # Import data
    log_info "Step 8: Importing data into Valkey"
    if ! import_data; then
        log_error "Data import failed"
        show_rollback_instructions
        exit 1
    fi
    echo ""

    # Final verification
    log_info "Step 9: Final verification"
    verify_valkey
    echo ""

    log_success "Migration completed successfully!"
    log_info "Export file saved at: ${EXPORT_FILE}"
    log_info "You can delete it after verifying everything works"

    show_rollback_instructions
}

# Cleanup on exit
trap 'stop_temp_redis 2>/dev/null || true' EXIT

main "$@"
