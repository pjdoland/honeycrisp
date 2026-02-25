#!/usr/bin/env bash
# honeycrisp.sh — A read-only Mac disk audit tool
# Identifies what you might be able to delete to free up space.
# NEVER deletes, moves, or modifies any file.

# We use pipefail but handle errors gracefully per-scan
set -uo pipefail

# ─── Defaults & Globals ───────────────────────────────────────────────────────

VERSION="1.0.0"
LARGE_FILE_THRESHOLD_MB=500
QUICK_MODE=false
NO_COLOR=false
OUTPUT_FILE=""
SUMMARY_CATS=()
SUMMARY_SIZES=()
SUMMARY_SAFETY_LABELS=()
GRAND_TOTAL_BYTES=0

# ─── Color & Formatting ──────────────────────────────────────────────────────

setup_colors() {
    if [[ "$NO_COLOR" == true ]] || [[ ! -t 1 ]]; then
        BOLD=""; DIM="" ; RESET=""
        RED="" ; GREEN="" ; YELLOW="" ; BLUE="" ; CYAN="" ; MAGENTA="" ; WHITE=""
    else
        BOLD=$(tput bold 2>/dev/null || echo "")
        DIM=$(tput dim 2>/dev/null || echo "")
        RESET=$(tput sgr0 2>/dev/null || echo "")
        RED=$(tput setaf 1 2>/dev/null || echo "")
        GREEN=$(tput setaf 2 2>/dev/null || echo "")
        YELLOW=$(tput setaf 3 2>/dev/null || echo "")
        BLUE=$(tput setaf 4 2>/dev/null || echo "")
        CYAN=$(tput setaf 6 2>/dev/null || echo "")
        MAGENTA=$(tput setaf 5 2>/dev/null || echo "")
        WHITE=$(tput setaf 7 2>/dev/null || echo "")
    fi
}

# ─── Helper Functions ─────────────────────────────────────────────────────────

print_banner() {
    echo ""
    echo "${BOLD}${GREEN}  H O N E Y C R I S P${RESET}"
    echo "${BOLD}${GREEN}  ----------------------------------------${RESET}"
    echo "${DIM}  Mac Disk Audit Tool v${VERSION}${RESET}"
    echo ""
    echo "  ${CYAN}This script is ${BOLD}READ-ONLY${RESET}${CYAN} — it will ${BOLD}never${RESET}${CYAN} delete,"
    echo "  move, or modify any file on your system.${RESET}"
    echo ""
    echo "  ${DIM}Tip: Open any path in Finder with:  open <path>${RESET}"
    echo "  ${DIM}e.g.  open ~/Library/Caches${RESET}"
    echo ""
}

print_header() {
    local title="$1"
    echo ""
    echo "${BOLD}${BLUE}  -------------------------------------------------------${RESET}"
    echo "${BOLD}${BLUE}  ${title}${RESET}"
    echo "${BOLD}${BLUE}  -------------------------------------------------------${RESET}"
    echo ""
}

print_scanning() {
    echo "  ${DIM}Scanning ${1}...${RESET}"
}

# Format a safety tag as fixed-width colored text
safety_tag() {
    case "$1" in
        safe)     printf "${GREEN}[SAFE]${RESET}   " ;;
        review)   printf "${YELLOW}[REVIEW]${RESET} " ;;
        caution)  printf "${RED}[CAUTION]${RESET}" ;;
        *)        printf "         " ;;
    esac
}

print_row() {
    local safety="$1"   # safe, review, caution
    local label="$2"
    local size="$3"
    local path="${4:-}"
    local tag
    tag=$(safety_tag "$safety")
    if [[ -n "$path" ]]; then
        printf "  %s %-32s %10s   ${DIM}%s${RESET}\n" "$tag" "$label" "$size" "$path"
    else
        printf "  %s %-32s %10s\n" "$tag" "$label" "$size"
    fi
}

print_subrow() {
    local label="$1"
    local size="$2"
    local path="${3:-}"
    if [[ -n "$path" ]]; then
        printf "            %-30s %10s   ${DIM}%s${RESET}\n" "$label" "$size" "$path"
    else
        printf "            %-30s %10s\n" "$label" "$size"
    fi
}

print_note() {
    echo "    ${DIM}> $1${RESET}"
}

print_warn() {
    echo "    ${YELLOW}! $1${RESET}"
}

print_skip() {
    echo "    ${DIM}- $1 -- not found, skipping${RESET}"
}

# Get size of a path in bytes; returns 0 if path doesn't exist or errors
safe_du_bytes() {
    local target="$1"
    if [[ -e "$target" ]]; then
        local kb
        kb=$(du -sk "$target" 2>/dev/null | tail -1 | awk '{print $1}')
        echo $(( ${kb:-0} * 1024 ))
    else
        echo "0"
    fi
}

# Get size of a path as human readable; returns "0B" if missing
safe_du() {
    local target="$1"
    if [[ -e "$target" ]]; then
        du -sh "$target" 2>/dev/null | awk '{print $1}' || echo "0B"
    else
        echo "0B"
    fi
}

# Format bytes to human-readable
format_size() {
    local bytes="$1"
    if (( bytes <= 0 )); then
        echo "0 B"
    elif (( bytes < 1024 )); then
        echo "${bytes} B"
    elif (( bytes < 1048576 )); then
        echo "$(( bytes / 1024 )) KB"
    elif (( bytes < 1073741824 )); then
        local mb=$(echo "scale=1; $bytes / 1048576" | bc 2>/dev/null || echo "$(( bytes / 1048576 ))")
        echo "${mb} MB"
    else
        local gb=$(echo "scale=1; $bytes / 1073741824" | bc 2>/dev/null || echo "$(( bytes / 1073741824 ))")
        echo "${gb} GB"
    fi
}

# Parse du -sk output to bytes
du_k_to_bytes() {
    awk '{print $1 * 1024}'
}

# Check if path exists
check_exists() {
    [[ -e "$1" ]]
}

# Add to summary totals
add_summary() {
    local category="$1"
    local bytes="$2"
    local safety="$3"
    # Find existing category index
    local i
    for i in "${!SUMMARY_CATS[@]}"; do
        if [[ "${SUMMARY_CATS[$i]}" == "$category" ]]; then
            SUMMARY_SIZES[$i]=$(( ${SUMMARY_SIZES[$i]} + bytes ))
            SUMMARY_SAFETY_LABELS[$i]="$safety"
            GRAND_TOTAL_BYTES=$(( GRAND_TOTAL_BYTES + bytes ))
            return
        fi
    done
    # New category
    SUMMARY_CATS+=("$category")
    SUMMARY_SIZES+=("$bytes")
    SUMMARY_SAFETY_LABELS+=("$safety")
    GRAND_TOTAL_BYTES=$(( GRAND_TOTAL_BYTES + bytes ))
}

# Known macOS system directories in Application Support that aren't third-party apps
is_system_app_support() {
    local name="$1"
    case "$name" in
        AddressBook|Caches|CallHistoryDB|CallHistoryTransactions|CloudDocs|\
        CrashReporter|FileProvider|Knowledge|SyncServices|icdd|tts|\
        com.apple.*|Apple|FaceTime|iCloud*|MobileSync|ScreenTimeAgent|\
        StatusKit*|Dock|Chromium|ATS|SpeechSynthesizer)
            return 0 ;;
    esac
    return 1
}

# Check if an app exists in /Applications (loosely)
app_exists() {
    local name="$1"
    # macOS system components are not "missing" apps
    is_system_app_support "$name" && return 0
    # Check common locations
    [[ -d "/Applications/${name}.app" ]] || \
    [[ -d "/Applications/${name}" ]] || \
    [[ -d "$HOME/Applications/${name}.app" ]] || \
    ls /Applications/ 2>/dev/null | grep -qi "$name"
}

# ─── Usage ────────────────────────────────────────────────────────────────────

show_help() {
    cat <<'HELP'
Usage: honeycrisp.sh [OPTIONS]

A read-only Mac disk audit tool that identifies space you could reclaim.
This script NEVER deletes, moves, or modifies any file.

Options:
  --quick           Skip slow deep scans (node_modules, large file finder)
  --no-color        Disable colorized output
  --threshold MB    Large file threshold in MB (default: 500)
  --output FILE     Also write output to a file
  --help            Show this help message
  --version         Show version

Examples:
  ./honeycrisp.sh                     Full scan with defaults
  ./honeycrisp.sh --quick             Fast overview, skip deep scans
  ./honeycrisp.sh --threshold 1000    Only flag files over 1 GB
  ./honeycrisp.sh --output report.txt Save report to file
HELP
}

# ─── Parse Arguments ──────────────────────────────────────────────────────────

while [[ $# -gt 0 ]]; do
    case "$1" in
        --quick)      QUICK_MODE=true; shift ;;
        --no-color)   NO_COLOR=true; shift ;;
        --threshold)  LARGE_FILE_THRESHOLD_MB="$2"; shift 2 ;;
        --output)     OUTPUT_FILE="$2"; shift 2 ;;
        --help)       show_help; exit 0 ;;
        --version)    echo "honeycrisp v${VERSION}"; exit 0 ;;
        *)            echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

# ─── Setup ────────────────────────────────────────────────────────────────────

setup_colors

# If --output, tee everything to file
if [[ -n "$OUTPUT_FILE" ]]; then
    exec > >(tee "$OUTPUT_FILE") 2>&1
fi

# ─── Start ────────────────────────────────────────────────────────────────────

print_banner

# ═══════════════════════════════════════════════════════════════════════════════
# SYSTEM OVERVIEW
# ═══════════════════════════════════════════════════════════════════════════════

print_header "SYSTEM OVERVIEW" "💻"

macos_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
macos_build=$(sw_vers -buildVersion 2>/dev/null || echo "")
hw_model=$(sysctl -n hw.model 2>/dev/null || echo "Unknown")
chip=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo "Unknown")

# Disk info — prefer APFS container-level data (df is misleading on APFS)
apfs_info=$(diskutil apfs list 2>/dev/null)
if [[ -n "$apfs_info" ]]; then
    disk_total=$(echo "$apfs_info" | grep "Capacity Ceiling" | head -1 | sed -E 's/.*\(([0-9.]+ [KMGT]B)\).*/\1/')
    disk_used=$(echo "$apfs_info" | grep "Capacity In Use By Volumes" | head -1 | sed -E 's/.*\(([0-9.]+ [KMGT]B)\).*/\1/')
    disk_pct=$(echo "$apfs_info" | grep "Capacity In Use By Volumes" | head -1 | sed -E 's/.*\(([0-9.]+% used)\).*/\1/')
    disk_free=$(echo "$apfs_info" | grep "Capacity Not Allocated" | head -1 | sed -E 's/.*\(([0-9.]+ [KMGT]B)\).*/\1/')
else
    # Fallback to df
    disk_info=$(df -H / 2>/dev/null | tail -1)
    disk_total=$(echo "$disk_info" | awk '{print $2}')
    disk_used=$(echo "$disk_info" | awk '{print $3}')
    disk_free=$(echo "$disk_info" | awk '{print $4}')
    disk_pct=$(echo "$disk_info" | awk '{print $5}')
fi

echo "  ${BOLD}macOS${RESET}        ${macos_version} (${macos_build})"
echo "  ${BOLD}Hardware${RESET}     ${hw_model} — ${chip}"
echo "  ${BOLD}Disk Total${RESET}   ${disk_total}"
echo "  ${BOLD}Disk Used${RESET}    ${disk_used} (${disk_pct})"
echo "  ${BOLD}Disk Free${RESET}    ${disk_free}"

if [[ "$QUICK_MODE" == true ]]; then
    echo ""
    echo "  ${YELLOW}Quick mode enabled -- skipping deep scans${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# SYSTEM & APP CACHES
# ═══════════════════════════════════════════════════════════════════════════════

print_header "SYSTEM & APP CACHES" "🗄️"

# ~/Library/Caches
cache_dir="$HOME/Library/Caches"
if check_exists "$cache_dir"; then
    print_scanning "$cache_dir"
    total_bytes=$(safe_du_bytes "$cache_dir")
    total_hr=$(format_size "$total_bytes")
    print_row "safe" "User Caches" "$total_hr" "$cache_dir"
    add_summary "System & App Caches" "$total_bytes" "Safe"

    # Top 10 subdirs
    echo ""
    echo "  ${DIM}  Top 10 cache directories:${RESET}"
    du -sk "$cache_dir"/*/ 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
        dir_name=$(basename "$dir")
        size_hr=$(format_size $(( kb * 1024 )))
        print_subrow "$dir_name" "$size_hr"
    done
else
    print_skip "$cache_dir"
fi

echo ""

# /Library/Caches
sys_cache="/Library/Caches"
if check_exists "$sys_cache"; then
    print_scanning "$sys_cache"
    total_bytes=$(safe_du_bytes "$sys_cache")
    total_hr=$(format_size "$total_bytes")
    print_row "review" "System Caches" "$total_hr" "$sys_cache"
    add_summary "System & App Caches" "$total_bytes" "Safe"
    print_note "Some files may require sudo to inspect"
else
    print_skip "$sys_cache"
fi

# /System/Library/Caches
sys_lib_cache="/System/Library/Caches"
if check_exists "$sys_lib_cache"; then
    total_bytes=$(safe_du_bytes "$sys_lib_cache")
    total_hr=$(format_size "$total_bytes")
    print_row "caution" "macOS System Caches" "$total_hr" "$sys_lib_cache"
    print_note "Managed by macOS — do not modify"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LOGS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "LOGS" "📋"

log_total=0

log_labels=("User Logs" "System Logs" "System Logs (var)")
log_paths=("$HOME/Library/Logs" "/Library/Logs" "/var/log")
log_safety=("safe" "safe" "review")

for i in "${!log_paths[@]}"; do
    log_dir="${log_paths[$i]}"
    if check_exists "$log_dir"; then
        print_scanning "$log_dir"
        bytes=$(safe_du_bytes "$log_dir")
        hr=$(format_size "$bytes")
        print_row "${log_safety[$i]}" "${log_labels[$i]}" "$hr" "$log_dir"
        [[ "$log_dir" == "/var/log" ]] && print_note "Full details may require sudo"
        log_total=$(( log_total + bytes ))
    else
        print_skip "$log_dir"
    fi
done

add_summary "Logs" "$log_total" "Safe"

# ═══════════════════════════════════════════════════════════════════════════════
# TEMPORARY FILES
# ═══════════════════════════════════════════════════════════════════════════════

print_header "TEMPORARY FILES" "🗑️"

tmp_total=0

# /tmp is a symlink to /private/tmp on macOS — only count once
if check_exists "/private/tmp"; then
    bytes=$(safe_du_bytes "/private/tmp")
    hr=$(format_size "$bytes")
    print_row "review" "Temp files" "$hr" "/private/tmp"
    tmp_total=$(( tmp_total + bytes ))
fi

# /var/folders
if check_exists "/var/folders"; then
    bytes=$(safe_du_bytes "/var/folders")
    hr=$(format_size "$bytes")
    print_row "caution" "macOS per-user temp" "$hr" "/var/folders"
    print_note "Managed by macOS — report only"
    tmp_total=$(( tmp_total + bytes ))
fi

add_summary "Temporary Files" "$tmp_total" "Review"

# ═══════════════════════════════════════════════════════════════════════════════
# APPLICATION SUPPORT LEFTOVERS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "APPLICATION SUPPORT" "📦"

app_support="$HOME/Library/Application Support"
if check_exists "$app_support"; then
    print_scanning "$app_support"
    total_bytes=$(safe_du_bytes "$app_support")
    total_hr=$(format_size "$total_bytes")
    print_row "review" "Application Support (total)" "$total_hr" "$app_support"

    echo ""
    echo "  ${DIM}  Top 15 largest subdirectories:${RESET}"
    app_support_flagged=0
    du -sk "$app_support"/*/ 2>/dev/null | sort -rn | head -15 | while read -r kb dir; do
        dir_name=$(basename "$dir")
        size_hr=$(format_size $(( kb * 1024 )))
        # Check if corresponding app exists
        if app_exists "$dir_name"; then
            print_subrow "$dir_name" "$size_hr"
        else
            printf "            ${YELLOW}%-30s %10s   ! App not found in /Applications${RESET}\n" "$dir_name" "$size_hr"
        fi
    done

    add_summary "Application Support" "$total_bytes" "Review"
else
    print_skip "$app_support"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# BROWSER CACHES
# ═══════════════════════════════════════════════════════════════════════════════

print_header "BROWSER CACHES" "🌐"

browser_total=0

browser_names=("Safari" "Chrome" "Firefox" "Arc" "Edge")
browser_paths=(
    "$HOME/Library/Caches/com.apple.Safari"
    "$HOME/Library/Caches/Google/Chrome"
    "$HOME/Library/Caches/Firefox"
    "$HOME/Library/Caches/Company.Arc"
    "$HOME/Library/Caches/Microsoft Edge"
)

# Check alternate Arc paths
for arc_alt in "$HOME/Library/Caches/com.thebrowser.Browser" "$HOME/Library/Caches/Company/Arc"; do
    if check_exists "$arc_alt" && ! check_exists "${browser_paths[3]}"; then
        browser_paths[3]="$arc_alt"
    fi
done

for i in "${!browser_names[@]}"; do
    browser="${browser_names[$i]}"
    path="${browser_paths[$i]}"
    if check_exists "$path"; then
        bytes=$(safe_du_bytes "$path")
        hr=$(format_size "$bytes")
        print_row "safe" "$browser cache" "$hr" "$path"
        browser_total=$(( browser_total + bytes ))
    else
        print_skip "$browser cache"
    fi
done

add_summary "Browser Caches" "$browser_total" "Safe"

# ═══════════════════════════════════════════════════════════════════════════════
# iOS / iPHONE BACKUPS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "iOS / iPHONE BACKUPS" "📱"

backup_dir="$HOME/Library/Application Support/MobileSync/Backup"
backup_total=0

if check_exists "$backup_dir"; then
    print_scanning "$backup_dir"
    for backup in "$backup_dir"/*/; do
        [[ -d "$backup" ]] || continue
        bytes=$(safe_du_bytes "$backup")
        hr=$(format_size "$bytes")
        backup_name=$(basename "$backup")

        # Check modification time
        mod_date=$(stat -f "%Sm" -t "%Y-%m-%d" "$backup" 2>/dev/null || echo "unknown")
        mod_epoch=$(stat -f "%m" "$backup" 2>/dev/null || echo "0")
        now_epoch=$(date +%s)
        age_days=$(( (now_epoch - mod_epoch) / 86400 ))

        safety="review"
        age_note=""
        if (( age_days > 180 )); then
            safety="safe"
            age_note=" (${age_days} days old — likely safe to remove)"
        fi

        print_row "$safety" "Backup ${backup_name:0:12}..." "$hr" "${mod_date}${age_note}"
        backup_total=$(( backup_total + bytes ))
    done

    if (( backup_total == 0 )); then
        echo "  ${DIM}  No backups found.${RESET}"
    fi
else
    print_skip "iOS Backups"
fi

add_summary "iOS Backups" "$backup_total" "Review"

# ═══════════════════════════════════════════════════════════════════════════════
# XCODE & DEVELOPER TOOLS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "XCODE & DEVELOPER TOOLS" "🔨"

xcode_total=0

if check_exists "/Applications/Xcode.app" || check_exists "$HOME/Library/Developer/Xcode"; then

    # DerivedData
    dd="$HOME/Library/Developer/Xcode/DerivedData"
    if check_exists "$dd"; then
        bytes=$(safe_du_bytes "$dd")
        hr=$(format_size "$bytes")
        print_row "safe" "Xcode DerivedData" "$hr" "$dd"
        xcode_total=$(( xcode_total + bytes ))
        add_summary "Xcode DerivedData" "$bytes" "Safe"
    fi

    # Archives
    archives="$HOME/Library/Developer/Xcode/Archives"
    if check_exists "$archives"; then
        bytes=$(safe_du_bytes "$archives")
        hr=$(format_size "$bytes")
        print_row "review" "Xcode Archives" "$hr" "$archives"
        xcode_total=$(( xcode_total + bytes ))
        add_summary "Xcode Archives" "$bytes" "Review"
    fi

    # iOS DeviceSupport
    ds="$HOME/Library/Developer/Xcode/iOS DeviceSupport"
    if check_exists "$ds"; then
        bytes=$(safe_du_bytes "$ds")
        hr=$(format_size "$bytes")
        print_row "review" "iOS DeviceSupport" "$hr" "$ds"
        echo "  ${DIM}  Versions:${RESET}"
        du -sk "$ds"/*/ 2>/dev/null | sort -rn | while read -r kb dir; do
            ver=$(basename "$dir")
            size_hr=$(format_size $(( kb * 1024 )))
            print_subrow "$ver" "$size_hr"
        done
        xcode_total=$(( xcode_total + bytes ))
        add_summary "Xcode DeviceSupport" "$bytes" "Review"
    fi

    # CoreSimulator Devices
    sim="$HOME/Library/Developer/CoreSimulator/Devices"
    if check_exists "$sim"; then
        bytes=$(safe_du_bytes "$sim")
        hr=$(format_size "$bytes")
        print_row "review" "Simulator Devices" "$hr" "$sim"
        xcode_total=$(( xcode_total + bytes ))
        add_summary "Simulator Devices" "$bytes" "Review"
    fi

    # CoreSimulator Caches
    sim_cache="$HOME/Library/Developer/CoreSimulator/Caches"
    if check_exists "$sim_cache"; then
        bytes=$(safe_du_bytes "$sim_cache")
        hr=$(format_size "$bytes")
        print_row "safe" "Simulator Caches" "$hr" "$sim_cache"
        xcode_total=$(( xcode_total + bytes ))
    fi

    # CoreSimulator Volumes (runtimes)
    sim_vol="$HOME/Library/Developer/CoreSimulator/Volumes"
    if check_exists "$sim_vol"; then
        bytes=$(safe_du_bytes "$sim_vol")
        hr=$(format_size "$bytes")
        print_row "review" "Simulator Runtimes" "$hr" "$sim_vol"
        echo "  ${DIM}  Runtimes:${RESET}"
        du -sk "$sim_vol"/*/ 2>/dev/null | sort -rn | while read -r kb dir; do
            rt=$(basename "$dir")
            size_hr=$(format_size $(( kb * 1024 )))
            print_subrow "$rt" "$size_hr"
        done
        xcode_total=$(( xcode_total + bytes ))
        add_summary "Simulator Runtimes" "$bytes" "Review"
    fi

    if (( xcode_total == 0 )); then
        echo "  ${DIM}  Xcode directories are clean.${RESET}"
    fi
else
    print_skip "Xcode (not installed)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# NODE / NPM / YARN / PNPM
# ═══════════════════════════════════════════════════════════════════════════════

print_header "NODE / NPM / YARN / PNPM" "📗"

node_total=0

# Package manager caches
for pair in "$HOME/.npm/_cacache:npm cache" "$HOME/.yarn/cache:yarn cache" "$HOME/.pnpm-store:pnpm store"; do
    path="${pair%%:*}"
    label="${pair##*:}"
    if check_exists "$path"; then
        bytes=$(safe_du_bytes "$path")
        hr=$(format_size "$bytes")
        print_row "safe" "$label" "$hr" "$path"
        node_total=$(( node_total + bytes ))
    fi
done

# node_modules search (slow — skip in quick mode)
nm_total=0
if [[ "$QUICK_MODE" == false ]]; then
    echo ""
    print_scanning "node_modules directories (this may take a moment)"
    nm_results=$(find "$HOME" -maxdepth 6 -name "node_modules" -type d -prune 2>/dev/null | head -100)

    if [[ -n "$nm_results" ]]; then
        echo ""
        echo "  ${DIM}  Top 10 node_modules by size:${RESET}"
        # Get sizes in parallel-ish
        while IFS= read -r nm_dir; do
            kb=$(du -sk "$nm_dir" 2>/dev/null | awk '{print $1}')
            echo "$kb $nm_dir"
        done <<< "$nm_results" | sort -rn | head -10 | while read -r kb dir; do
            bytes=$(( kb * 1024 ))
            size_hr=$(format_size "$bytes")
            project=$(dirname "$dir")
            project_name=$(basename "$project")
            print_subrow "$project_name/node_modules" "$size_hr" "$dir"
        done

        # Compute total
        while IFS= read -r nm_dir; do
            kb=$(du -sk "$nm_dir" 2>/dev/null | awk '{print $1}')
            nm_total=$(( nm_total + kb * 1024 ))
        done <<< "$nm_results"

        echo ""
        print_row "review" "node_modules (total)" "$(format_size $nm_total)"
        add_summary "node_modules" "$nm_total" "Review"
    else
        print_skip "node_modules directories"
    fi
else
    print_skip "node_modules scan (--quick mode)"
fi

# Only add package manager caches (not node_modules) to this category
# node_modules are tracked separately to avoid double-counting
add_summary "Node/npm/yarn Caches" "$node_total" "Safe"

# ═══════════════════════════════════════════════════════════════════════════════
# PYTHON / PIP / CONDA
# ═══════════════════════════════════════════════════════════════════════════════

print_header "PYTHON / PIP / CONDA" "🐍"

py_total=0

for pair in \
    "$HOME/.cache/pip:pip cache" \
    "$HOME/miniconda3/pkgs:Miniconda packages" \
    "$HOME/anaconda3/pkgs:Anaconda packages" \
    "$HOME/.pyenv:pyenv"; do
    path="${pair%%:*}"
    label="${pair##*:}"
    if check_exists "$path"; then
        bytes=$(safe_du_bytes "$path")
        hr=$(format_size "$bytes")
        print_row "safe" "$label" "$hr" "$path"
        py_total=$(( py_total + bytes ))
    fi
done

if (( py_total == 0 )); then
    echo "  ${DIM}  No Python caches found.${RESET}"
fi

add_summary "Python/pip/conda" "$py_total" "Safe"

# ═══════════════════════════════════════════════════════════════════════════════
# HOMEBREW
# ═══════════════════════════════════════════════════════════════════════════════

print_header "HOMEBREW" "🍺"

brew_total=0

if command -v brew &>/dev/null; then
    # Brew cache
    brew_cache=$(brew --cache 2>/dev/null)
    if check_exists "$brew_cache"; then
        bytes=$(safe_du_bytes "$brew_cache")
        hr=$(format_size "$bytes")
        print_row "safe" "Homebrew cache" "$hr" "$brew_cache"
        print_note "Clean with: brew cleanup --prune=all"
        brew_total=$(( brew_total + bytes ))
    fi

    # Brew cellar top 10
    brew_cellar=$(brew --cellar 2>/dev/null)
    if check_exists "$brew_cellar"; then
        echo ""
        echo "  ${DIM}  Top 10 formulae by size:${RESET}"
        du -sk "$brew_cellar"/*/ 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
            name=$(basename "$dir")
            size_hr=$(format_size $(( kb * 1024 )))
            print_subrow "$name" "$size_hr"
        done
    fi
else
    print_skip "Homebrew (not installed)"
fi

add_summary "Homebrew Cache" "$brew_total" "Safe"

# ═══════════════════════════════════════════════════════════════════════════════
# DOCKER
# ═══════════════════════════════════════════════════════════════════════════════

print_header "DOCKER" "🐳"

docker_total=0
docker_dir="$HOME/Library/Containers/com.docker.docker"

if check_exists "$docker_dir"; then
    bytes=$(safe_du_bytes "$docker_dir")
    hr=$(format_size "$bytes")
    print_row "review" "Docker data" "$hr" "$docker_dir"
    print_note "Run 'docker system df' for detailed breakdown"
    print_note "Run 'docker system prune' to clean unused data"
    docker_total=$bytes
elif command -v docker &>/dev/null; then
    # Docker might be using a different data root
    echo "  ${DIM}  Docker is installed but data directory not in default location.${RESET}"
    print_note "Run 'docker system df' for space usage"
else
    print_skip "Docker (not installed)"
fi

add_summary "Docker" "$docker_total" "Review"

# ═══════════════════════════════════════════════════════════════════════════════
# TRASH
# ═══════════════════════════════════════════════════════════════════════════════

print_header "TRASH" "🗑️"

trash_total=0
trash_dir="$HOME/.Trash"

if check_exists "$trash_dir"; then
    bytes=$(safe_du_bytes "$trash_dir")
    hr=$(format_size "$bytes")
    file_count=$(find "$trash_dir" -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
    file_count=$(( file_count - 1 ))  # subtract the directory itself
    print_row "safe" "Trash (${file_count} items)" "$hr" "$trash_dir"
    trash_total=$bytes
fi

# Check external volumes for .Trashes
for vol in /Volumes/*/; do
    trashes="${vol}.Trashes"
    if check_exists "$trashes"; then
        bytes=$(safe_du_bytes "$trashes")
        if (( bytes > 0 )); then
            hr=$(format_size "$bytes")
            vol_name=$(basename "$vol")
            print_row "safe" "Trash on ${vol_name}" "$hr" "$trashes"
            trash_total=$(( trash_total + bytes ))
        fi
    fi
done

add_summary "Trash" "$trash_total" "Safe"

# ═══════════════════════════════════════════════════════════════════════════════
# DISK IMAGES & INSTALLERS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "DISK IMAGES & INSTALLERS" "💿"

installer_total=0

for scan_dir in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; do
    if check_exists "$scan_dir"; then
        found=$(find "$scan_dir" -maxdepth 3 \( -iname "*.dmg" -o -iname "*.pkg" -o -iname "*.iso" \) -type f 2>/dev/null)
        if [[ -n "$found" ]]; then
            echo "  ${DIM}  In $(basename "$scan_dir"):${RESET}"
            while IFS= read -r f; do
                bytes=$(stat -f "%z" "$f" 2>/dev/null || echo "0")
                hr=$(format_size "$bytes")
                fname=$(basename "$f")
                print_subrow "$fname" "$hr" "$f"
                installer_total=$(( installer_total + bytes ))
            done <<< "$found"
        fi
    fi
done

if (( installer_total == 0 )); then
    echo "  ${DIM}  No .dmg, .pkg, or .iso files found.${RESET}"
fi

add_summary "Disk Images/Installers" "$installer_total" "Review"

# ═══════════════════════════════════════════════════════════════════════════════
# MAIL
# ═══════════════════════════════════════════════════════════════════════════════

print_header "MAIL" "📧"

mail_total=0

mail_dir="$HOME/Library/Mail"
if check_exists "$mail_dir"; then
    bytes=$(safe_du_bytes "$mail_dir")
    hr=$(format_size "$bytes")
    print_row "review" "Mail data" "$hr" "$mail_dir"
    mail_total=$bytes

    echo "  ${DIM}  Top-level breakdown:${RESET}"
    du -sk "$mail_dir"/*/ 2>/dev/null | sort -rn | head -10 | while read -r kb dir; do
        name=$(basename "$dir")
        size_hr=$(format_size $(( kb * 1024 )))
        print_subrow "$name" "$size_hr"
    done
fi

mail_container="$HOME/Library/Containers/com.apple.mail"
if check_exists "$mail_container"; then
    bytes=$(safe_du_bytes "$mail_container")
    hr=$(format_size "$bytes")
    print_row "review" "Mail container/attachments" "$hr" "$mail_container"
    mail_total=$(( mail_total + bytes ))
fi

if (( mail_total == 0 )); then
    echo "  ${DIM}  No Mail data found.${RESET}"
fi

add_summary "Mail" "$mail_total" "Review"

# ═══════════════════════════════════════════════════════════════════════════════
# PHOTOS & MEDIA
# ═══════════════════════════════════════════════════════════════════════════════

print_header "PHOTOS & MEDIA" "📸"

photos_total=0

photos_lib="$HOME/Pictures/Photos Library.photoslibrary"
if check_exists "$photos_lib"; then
    bytes=$(safe_du_bytes "$photos_lib")
    hr=$(format_size "$bytes")
    print_row "caution" "Photos Library" "$hr" "$photos_lib"
    print_note "Size depends on whether originals or optimized storage is used"
    photos_total=$bytes
fi

# Other .photoslibrary bundles
other_photos=$(find "$HOME" -maxdepth 4 -name "*.photoslibrary" -not -path "$photos_lib" 2>/dev/null)
if [[ -n "$other_photos" ]]; then
    while IFS= read -r lib; do
        bytes=$(safe_du_bytes "$lib")
        hr=$(format_size "$bytes")
        print_row "review" "Photo Library" "$hr" "$lib"
        photos_total=$(( photos_total + bytes ))
    done <<< "$other_photos"
fi

# Video files in Downloads/Desktop
echo ""
echo "  ${DIM}  Video files in Downloads & Desktop:${RESET}"
video_found=false
for scan_dir in "$HOME/Downloads" "$HOME/Desktop"; do
    if check_exists "$scan_dir"; then
        vids=$(find "$scan_dir" -maxdepth 2 \( -iname "*.mp4" -o -iname "*.mov" -o -iname "*.avi" -o -iname "*.mkv" \) -type f 2>/dev/null)
        if [[ -n "$vids" ]]; then
            while IFS= read -r f; do
                bytes=$(stat -f "%z" "$f" 2>/dev/null || echo "0")
                hr=$(format_size "$bytes")
                fname=$(basename "$f")
                print_subrow "$fname" "$hr" "$f"
                photos_total=$(( photos_total + bytes ))
                video_found=true
            done <<< "$vids"
        fi
    fi
done
if [[ "$video_found" == false ]]; then
    echo "  ${DIM}     None found.${RESET}"
fi

add_summary "Photos & Media" "$photos_total" "Caution"

# ═══════════════════════════════════════════════════════════════════════════════
# DOWNLOADS — OLD & LARGE FILES
# ═══════════════════════════════════════════════════════════════════════════════

print_header "DOWNLOADS — OLD & LARGE FILES" "📥"

downloads_total=0
downloads_dir="$HOME/Downloads"

if check_exists "$downloads_dir"; then
    echo "  ${DIM}  Top 20 largest files:${RESET}"
    find "$downloads_dir" -maxdepth 1 -type f 2>/dev/null \
        | while IFS= read -r f; do
            bytes=$(stat -f "%z" "$f" 2>/dev/null || echo "0")
            mod=$(stat -f "%Sm" -t "%Y-%m-%d" "$f" 2>/dev/null || echo "???")
            echo "$bytes $mod $f"
        done \
        | sort -rn | head -20 | while read -r bytes mod path; do
            hr=$(format_size "$bytes")
            fname=$(basename "$path")
            printf "       %-33s %8s    ${DIM}%s${RESET}\n" "${fname:0:33}" "$hr" "$mod"
        done

    # Files not accessed in over 1 year
    echo ""
    echo "  ${DIM}  Files not accessed in over 1 year:${RESET}"
    one_year_ago=$(date -v-1y +%s 2>/dev/null)
    old_total=0
    old_count=0
    while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        access_epoch=$(stat -f "%a" "$f" 2>/dev/null || echo "0")
        if (( access_epoch > 0 && access_epoch < one_year_ago )); then
            bytes=$(stat -f "%z" "$f" 2>/dev/null || echo "0")
            old_total=$(( old_total + bytes ))
            old_count=$(( old_count + 1 ))
        fi
    done < <(find "$downloads_dir" -maxdepth 1 -type f 2>/dev/null)

    if (( old_count > 0 && old_total > 0 )); then
        hr=$(format_size "$old_total")
        file_word="files"
        (( old_count == 1 )) && file_word="file"
        print_row "review" "Old Downloads (${old_count} ${file_word})" "$hr" "Not accessed in 1+ year"
        downloads_total=$old_total
    else
        echo "  ${DIM}     None found.${RESET}"
    fi
fi

add_summary "Old Downloads" "$downloads_total" "Review"

# ═══════════════════════════════════════════════════════════════════════════════
# LANGUAGE PACK LEFTOVERS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "LANGUAGE PACK LEFTOVERS" "🌍"

if [[ "$QUICK_MODE" == false ]]; then
    print_scanning "/Applications for non-English .lproj bundles"
    lproj_bytes=0
    lproj_count=0
    while IFS= read -r lp; do
        kb=$(du -sk "$lp" 2>/dev/null | awk '{print $1}')
        lproj_bytes=$(( lproj_bytes + kb * 1024 ))
        lproj_count=$(( lproj_count + 1 ))
    done < <(find /Applications -name "*.lproj" -type d \
        ! -name "en.lproj" ! -name "Base.lproj" ! -name "en_US.lproj" \
        ! -name "English.lproj" 2>/dev/null)

    if (( lproj_bytes > 0 )); then
        hr=$(format_size "$lproj_bytes")
        print_row "safe" "Non-English language packs" "$hr" "${lproj_count} .lproj bundles"
        print_note "Use Monolingual app (free) to safely remove"
    else
        echo "  ${DIM}  No significant language pack leftovers found.${RESET}"
    fi

    add_summary "Language Packs" "$lproj_bytes" "Safe"
else
    print_skip "Language pack scan (--quick mode)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TIME MACHINE LOCAL SNAPSHOTS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "TIME MACHINE LOCAL SNAPSHOTS" "⏰"

# Filter to only actual snapshot lines (com.apple.TimeMachine or com.apple.os.update)
snapshots=$(tmutil listlocalsnapshots / 2>/dev/null | grep "^com\." || true)
if [[ -n "$snapshots" ]]; then
    snap_count=$(echo "$snapshots" | wc -l | tr -d ' ')
    print_row "review" "Local snapshots" "${snap_count} found" "Managed by macOS"
    echo "  ${DIM}  Recent snapshots:${RESET}"
    echo "$snapshots" | head -10 | while read -r snap; do
        print_subrow "$snap" ""
    done
    print_note "macOS manages these automatically"
    print_note "To thin: sudo tmutil thinlocalsnapshots / <bytes> 1"
else
    echo "  ${DIM}  No local Time Machine snapshots found.${RESET}"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# PODCASTS & MUSIC
# ═══════════════════════════════════════════════════════════════════════════════

print_header "PODCASTS & MUSIC" "🎵"

media_total=0

# Podcasts
podcast_dirs=$(find "$HOME/Library/Group Containers" -maxdepth 1 -name "*podcasts*" -o -name "*com.apple.podcasts*" 2>/dev/null)
if [[ -n "$podcast_dirs" ]]; then
    while IFS= read -r pd; do
        bytes=$(safe_du_bytes "$pd")
        hr=$(format_size "$bytes")
        print_row "safe" "Podcasts" "$hr" "$pd"
        media_total=$(( media_total + bytes ))
    done <<< "$podcast_dirs"
fi

# Music/iTunes
for music_dir in "$HOME/Music/iTunes" "$HOME/Music/Music"; do
    if check_exists "$music_dir"; then
        bytes=$(safe_du_bytes "$music_dir")
        hr=$(format_size "$bytes")
        label=$(basename "$music_dir")
        safety="review"
        (( bytes > 5368709120 )) && safety="review"  # flag if > 5GB
        print_row "$safety" "$label library" "$hr" "$music_dir"
        media_total=$(( media_total + bytes ))
    fi
done

if (( media_total == 0 )); then
    echo "  ${DIM}  No significant podcast/music data found.${RESET}"
fi

add_summary "Podcasts & Music" "$media_total" "Review"

# ═══════════════════════════════════════════════════════════════════════════════
# UNUSED APPLICATIONS
# ═══════════════════════════════════════════════════════════════════════════════

print_header "UNUSED APPLICATIONS" "👻"

if [[ "$QUICK_MODE" == false ]]; then
    print_scanning "/Applications for unused apps"
    echo ""
    now_epoch=$(date +%s)
    unused_found=false
    no_data_count=0

    while IFS= read -r app; do
        [[ -d "$app" ]] || continue
        app_name=$(basename "$app")

        # Get last used date via Spotlight -- skip apps with no data
        last_used=$(mdls -name kMDItemLastUsedDate -raw "$app" 2>/dev/null || true)
        if [[ "$last_used" == "(null)" ]] || [[ -z "$last_used" ]] || [[ "$last_used" == *"could not find"* ]]; then
            no_data_count=$(( no_data_count + 1 ))
            continue
        fi

        last_used_epoch=$(date -j -f "%Y-%m-%d %H:%M:%S %z" "$last_used" +%s 2>/dev/null || echo "0")
        last_used_str="${last_used%% *}"

        if (( last_used_epoch == 0 )); then
            no_data_count=$(( no_data_count + 1 ))
            continue
        fi

        age_days=$(( (now_epoch - last_used_epoch) / 86400 ))

        if (( age_days > 180 )); then
            if [[ "$unused_found" == false ]]; then
                echo "  ${DIM}  Apps not opened in over 180 days:${RESET}"
                unused_found=true
            fi
            kb=$(du -sk "$app" 2>/dev/null | awk '{print $1}')
            bytes=$(( kb * 1024 ))
            hr=$(format_size "$bytes")
            tag=$(safety_tag "review")
            printf "  %s %-32s %10s   ${DIM}Last used: %s${RESET}\n" "$tag" "${app_name}" "$hr" "$last_used_str"
        fi
    done < <(find /Applications -maxdepth 1 -name "*.app" 2>/dev/null | sort)

    if [[ "$unused_found" == false ]]; then
        echo "  ${DIM}  No unused apps detected (based on Spotlight data).${RESET}"
    fi
    if (( no_data_count > 0 )); then
        print_note "${no_data_count} apps had no Spotlight usage data and were skipped"
    fi
    print_note "Use AppCleaner (free) for thorough app removal"
else
    print_skip "Unused app scan (--quick mode)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# LARGE FILE FINDER
# ═══════════════════════════════════════════════════════════════════════════════

print_header "LARGE FILE FINDER (>${LARGE_FILE_THRESHOLD_MB}MB)" "🔍"

large_total=0

if [[ "$QUICK_MODE" == false ]]; then
    print_scanning "home directory for large files"
    threshold_bytes=$(( LARGE_FILE_THRESHOLD_MB * 1048576 ))

    large_files=$(find "$HOME" \
        -not -path "*/Photos Library.photoslibrary/*" \
        -not -path "*/.photoslibrary/*" \
        -not -path "*/Time Machine*" \
        -not -path "*/.Trash/*" \
        -maxdepth 8 -type f -size "+${LARGE_FILE_THRESHOLD_MB}M" 2>/dev/null | head -50)

    if [[ -n "$large_files" ]]; then
        echo ""
        while IFS= read -r f; do
            bytes=$(stat -f "%z" "$f" 2>/dev/null || echo "0")
            mod=$(stat -f "%Sm" -t "%Y-%m-%d" "$f" 2>/dev/null || echo "???")
            echo "$bytes $mod $f"
        done <<< "$large_files" | sort -rn | head -20 | while read -r bytes mod path; do
            hr=$(format_size "$bytes")
            display_path="${path/#$HOME/~}"
            printf "  %10s   ${DIM}%s${RESET}  %s\n" "$hr" "$mod" "$display_path"
        done
    else
        echo "  ${DIM}  No files over ${LARGE_FILE_THRESHOLD_MB}MB found.${RESET}"
    fi

    # Re-sum outside the pipe for accurate total
    if [[ -n "$large_files" ]]; then
        while IFS= read -r f; do
            bytes=$(stat -f "%z" "$f" 2>/dev/null || echo "0")
            large_total=$(( large_total + bytes ))
        done <<< "$large_files"
    fi

    add_summary "Large Files (>${LARGE_FILE_THRESHOLD_MB}MB)" "$large_total" "Review"
else
    print_skip "Large file scan (--quick mode)"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# TOP 20 DIRECTORIES IN HOME
# ═══════════════════════════════════════════════════════════════════════════════

print_header "TOP 20 LARGEST DIRECTORIES" "📊"

echo "  ${DIM}  Home directory:${RESET}"
du -sk "$HOME"/*/ 2>/dev/null | sort -rn | head -20 | while read -r kb dir; do
    dir_name=$(basename "$dir")
    size_hr=$(format_size $(( kb * 1024 )))
    printf "            %-40s %8s\n" "$dir_name/" "$size_hr"
done

echo ""
echo "  ${DIM}  ~/Library:${RESET}"
du -sk "$HOME/Library"/*/ 2>/dev/null | sort -rn | head -20 | while read -r kb dir; do
    dir_name=$(basename "$dir")
    size_hr=$(format_size $(( kb * 1024 )))
    printf "            %-40s %8s\n" "$dir_name/" "$size_hr"
done

# ═══════════════════════════════════════════════════════════════════════════════
# SUMMARY TABLE
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo ""
echo ""
echo "  ${BOLD}${GREEN}HONEYCRISP SUMMARY${RESET}"
echo "  ${BOLD}-------------------------------------------------------${RESET}"
printf "  %-32s  %10s   %-10s\n" "Category" "Found" "Safety"
echo "  ${DIM}--------------------------------  ----------   ----------${RESET}"

# Format safety label with color
color_safety() {
    case "$1" in
        Safe)    printf "${GREEN}%-10s${RESET}" "Safe" ;;
        Review)  printf "${YELLOW}%-10s${RESET}" "Review" ;;
        Caution) printf "${RED}%-10s${RESET}" "Caution" ;;
        *)       printf "%-10s" "$1" ;;
    esac
}

# Sort categories by size descending using a temp approach
summary_sort_data=""
for i in "${!SUMMARY_CATS[@]}"; do
    summary_sort_data+="${SUMMARY_SIZES[$i]} ${i}"$'\n'
done
while read -r _sz idx; do
    [[ -z "$idx" ]] && continue
    cat="${SUMMARY_CATS[$idx]}"
    size="${SUMMARY_SIZES[$idx]}"
    safety="${SUMMARY_SAFETY_LABELS[$idx]}"
    if (( size > 0 )); then
        hr=$(format_size "$size")
        safety_colored=$(color_safety "$safety")
        printf "  %-32s  %10s   %s\n" "${cat:0:32}" "$hr" "$safety_colored"
    fi
done <<< "$(echo "$summary_sort_data" | sort -rn)"

echo "  ${BOLD}-------------------------------------------------------${RESET}"
grand_hr=$(format_size "$GRAND_TOTAL_BYTES")
printf "  ${BOLD}%-32s  %10s${RESET}\n" "TOTAL POTENTIAL SAVINGS" "$grand_hr"

# ═══════════════════════════════════════════════════════════════════════════════
# NEXT STEPS
# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo ""
echo "  ${BOLD}${CYAN}-------------------------------------------------------${RESET}"
echo "  ${BOLD}${CYAN}WHAT TO DO NEXT${RESET}"
echo "  ${BOLD}${CYAN}-------------------------------------------------------${RESET}"
echo ""
echo "  ${BOLD}Caches${RESET}"
echo "    Safe to delete manually or via System Settings → General → Storage."
echo "    Apps will rebuild their caches as needed."
echo ""
echo "  ${BOLD}iOS Backups${RESET}"
echo "    Open Finder → your device → Manage Backups, or browse:"
echo "    ~/Library/Application Support/MobileSync/Backup"
echo ""
echo "  ${BOLD}Xcode DerivedData${RESET}"
echo "    Xcode → Settings → Locations → Derived Data → click arrow → delete."
echo "    Or: rm -rf ~/Library/Developer/Xcode/DerivedData"
echo ""
echo "  ${BOLD}node_modules${RESET}"
echo "    Delete and regenerate with 'npm install' in each project."
echo "    Bulk delete: find ~ -name 'node_modules' -type d -prune -maxdepth 6 -exec rm -rf {} +"
echo ""
echo "  ${BOLD}Homebrew${RESET}"
echo "    brew cleanup --prune=all"
echo ""
echo "  ${BOLD}Trash${RESET}"
echo "    Finder → Empty Trash, or: rm -rf ~/.Trash/*"
echo ""
echo "  ${BOLD}Simulator Runtimes${RESET}"
echo "    xcrun simctl delete unavailable"
echo "    Xcode → Settings → Platforms → remove old runtimes"
echo ""
echo "  ${BOLD}Language Packs${RESET}"
echo "    Use Monolingual app (free, open source) to safely remove unused"
echo "    language files from applications."
echo ""
echo "  ${BOLD}Large Files${RESET}"
echo "    Review the list above and move to external storage or delete if unneeded."
echo ""
echo "  ${BOLD}Old/Unused Apps${RESET}"
echo "    Use AppCleaner (free) for thorough removal including support files."
echo ""
echo "  ${BOLD}Docker${RESET}"
echo "    docker system prune — removes unused images, containers, and build cache."
echo ""
echo "  ${BOLD}Disk Images & Installers${RESET}"
echo "    Review .dmg/.pkg/.iso files in Downloads — delete after installation."
echo ""
echo ""
echo "  ${DIM}Honeycrisp v${VERSION} -- scan complete.${RESET}"
echo "  ${DIM}Remember: this tool only reports. No files were modified.${RESET}"
echo ""
