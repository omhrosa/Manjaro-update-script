#!/bin/bash
# System update/maintenance script for Manjaro.



# Define UI colors
cyan='\033[38;5;38m'
red='\033[38;5;162m'
yellow='\033[38;5;178m'
orange='\033[38;5;173m'
green='\033[38;5;77m'
purple='\033[38;5;105m'
blue='\033[38;5;39m'
reset='\033[0m'

# Progress UI config
PROG_WIDTH=20
total_steps=5
current_step=0
TITLE_PREFIX="Update"



# Set terminal window title without polluting logs.
# Uses OSC sequences written to /dev/tty for safety.
set_term_title() {
  local tty="/dev/tty"
  local title="$1"
  printf '\033]0;%s\007' "$title" >"$tty"
}



# Initialize the progress UI and set the initial title.
# Keeps terminal scrollback intact (no scroll-region hacks).
progress_ui_init() {
  show_progress "$current_step" "$total_steps"
}

# Finalize the progress UI state.
# Leaves the terminal title in a clean, predictable state.
progress_ui_end() {
  set_term_title "${TITLE_PREFIX}"
}



# Compute and render the progress bar title string.
# Updates the terminal title with percent and bar state.
show_progress() {
  local current="$1"
  local total="$2"
  (( total <= 0 )) && total=1
  (( current < 0 )) && current=0
  (( current > total )) && current=$total
  local percent=$(( 100 * current / total ))
  local filled=$(( PROG_WIDTH * current / total ))
  local empty=$(( PROG_WIDTH - filled ))
  local done_sub_bar todo_sub_bar text
  done_sub_bar=$(printf "%${filled}s" "" | tr " " "#")
  todo_sub_bar=$(printf "%${empty}s" "" | tr " " "-")
  text="[${done_sub_bar}${todo_sub_bar}] ${percent}%"
  set_term_title "${TITLE_PREFIX}  ${text}"
}



# Print the startup banner.
echo -ne "${cyan}"
echo '    888     888               888          888                 .d8888b.                   d8b          888   '
echo '    888     888               888          888                d88P  Y88b                  Y8P          888   '
echo '    888     888               888          888                Y88b.                                    888   '
echo '    888     888 88888b.   .d88888  8888b.  888888 .d88b.       "Y888b.    .d8888b 888d888 888 88888b.  888888'
echo '    888     888 888 "88b d88" 888     "88b 888   d8P  Y8b         "Y88b. d88P"    888P"   888 888 "88b 888   '
echo '    888     888 888  888 888  888 .d888888 888   88888888           "888 888      888     888 888  888 888   '
echo '    Y88b. .d88P 888 d88P Y88b 888 888  888 Y88b. Y8b.         Y88b  d88P Y88b.    888     888 888 d88P Y88b. '
echo '    "Y88888P"  88888P"   "Y88888 "Y888888  "Y888 "Y8888       "Y8888P"   "Y8888P 888     888 88888P"   "Y888"'
echo '                888                                                                           888            '
echo '                888                                                                           888            '
echo '                888                                                                                          '
echo -ne "${reset}"
echo -e "\n\n"
echo -ne "${yellow}"



# Prompt for sudo once and validate privileges.
sudo -v

# Handle cleanup and log finalization on exit or interruption.
# Stops sudo keepalive, cleans tmp logs, and restores stdio.
on_exit() {
  local rc=$?
  progress_ui_end
  [[ -n "${SUDOREFRESHPID:-}" ]] && kill "$SUDOREFRESHPID" 2>/dev/null || true
  if [[ -z "${log_path:-}" || ! -f "${log_path:-}" ]]; then
    rm -rf /tmp/manjaro 2>/dev/null || true
    exit "$rc"
  fi
  if { true >&3; } 2>/dev/null && { true >&4; } 2>/dev/null; then
    exec 1>&3 2>&4
  fi
  local dt="${datetime_str:-$(date +'%F_%H-%M-%S')}"
  final_filename="Update-${dt}.log"
  cleaned_tmp="/tmp/manjaro/cleaned_tmp.log"
  sed -E 's/\x1B\[[0-9;?]*[A-Za-z]//g; s/\x1B\][^\x07\x1B]*(\x07|\x1B\\)//g' "$log_path" | \
  tr -cd '\11\12\15\40-\176' | \
  awk '
BEGIN { skip = 0 }
/^ *8.888888888e+09/ { skip = 1 }
skip && /88P" */ { skip = 0; next }
skip == 0 { print }
' > "$cleaned_tmp"
  find "$HOME" -maxdepth 1 -type f -name 'Update-*.log' -exec rm -f {} \;
  cp -f "$cleaned_tmp" "$HOME/$final_filename"
  rm -rf /tmp/manjaro
  exit "$rc"
}

# Arm exit traps after defining cleanup.
# Ensures logs and temp files are always finalized safely.
trap on_exit EXIT INT TERM

# Keep sudo alive during the run (killed by on_exit trap).
(while sleep 60; do sudo -n -v || exit; done) &
SUDOREFRESHPID=$!
clear



# Clock sanity gate
clock_sanity_gate() {
  local max_drift_ms=5000   # 5 seconds, strict
  local auto_tried=false
  local drift_ms ans

  get_drift_ms() {
    [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null)" == "yes" ]] || return 1

    # Parse: Offset: +9.083ms -> "9.083"
    local ms
    ms="$(timedatectl timesync-status 2>/dev/null | awk '/Offset:/{
      v=$2; gsub(/[+]|ms/,"",v); print v
    }')"
    [[ -n "$ms" ]] || return 1

    # Convert to integer milliseconds (absolute), rounded
    awk -v o="$ms" 'BEGIN{
      if (o < 0) o = -o;
      printf "%.0f\n", o
    }'
  }

  while true; do
    if drift_ms="$(get_drift_ms)"; then
      (( drift_ms <= max_drift_ms )) && return 0
      echo "ERROR: Clock drift ~${drift_ms}ms (limit ${max_drift_ms}ms). Updates will fail (PGP/HTTPS)."
    else
      echo "ERROR: Clock not synchronized (can't read NTP offset)."
    fi

    if [[ "$auto_tried" == false ]]; then
      auto_tried=true
      echo "Trying one automatic NTP resync..."
      sudo systemctl restart systemd-timesyncd || true
      sleep 5
      continue
    fi

    read -rp "Retry NTP (r)esync or (e)xit? " ans
    case "${ans,,}" in
      r) sudo systemctl restart systemd-timesyncd || true; sleep 5 ;;
      e) echo "Exiting. Fix time sync and rerun."; exit 1 ;;
      *) echo "Invalid choice. Exiting."; exit 1 ;;
    esac
  done
}

clock_sanity_gate
clear



# Verify all hard dependencies up front and fail fast if missing.
# Offers one-shot install of missing repo/AUR packages, or exits.
deps_check_and_install() {
  # Collect missing commands and map them to packages.
  local -a repo_pkgs=()
  local -a aur_pkgs=()
  local -a missing_cmds=()
  local need_yay=0
  local cmd

  # Commands used by the script (explicitly checked)
  for cmd in \
    pacman-mirrors curl smartctl snapper grub-mkconfig flatpak yay gext checkrebuild fuser \
    python3 timedatectl findmnt lsblk realpath script mhwd-kernel meld gnome-text-editor xdg-open \
    awk sed tr find grep sort comm stat df \
  ; do
    command -v "$cmd" >/dev/null 2>&1 || missing_cmds+=("$cmd")
  done

  ((${#missing_cmds[@]}==0)) && return 0

  command -v yay >/dev/null 2>&1 || need_yay=1

  for cmd in "${missing_cmds[@]}"; do
    case "$cmd" in
      # Existing mappings
      smartctl) repo_pkgs+=(smartmontools) ;;
      snapper) repo_pkgs+=(snapper) ;;
      grub-mkconfig) repo_pkgs+=(grub) ;;
      pacman-mirrors) repo_pkgs+=(pacman-mirrors) ;;
      curl) repo_pkgs+=(curl) ;;
      flatpak) repo_pkgs+=(flatpak) ;;
      yay) repo_pkgs+=(yay) ;;
      gext) aur_pkgs+=(gnome-extensions-cli) ;;
      checkrebuild) aur_pkgs+=(rebuild-detector) ;;
      fuser) repo_pkgs+=(psmisc) ;;

      # Added mappings (repo)
      python3) repo_pkgs+=(python) ;;
      timedatectl) repo_pkgs+=(systemd) ;;

      findmnt|lsblk|script) repo_pkgs+=(util-linux) ;;
      mhwd-kernel) repo_pkgs+=(mhwd) ;;
      xdg-open) repo_pkgs+=(xdg-utils) ;;
      meld) repo_pkgs+=(meld) ;;
      gnome-text-editor) repo_pkgs+=(gnome-text-editor) ;;

      awk) repo_pkgs+=(gawk) ;;
      sed) repo_pkgs+=(sed) ;;
      grep) repo_pkgs+=(grep) ;;
      find) repo_pkgs+=(findutils) ;;

      # Coreutils-provided commands
      realpath|stat|df|tr|sort|comm) repo_pkgs+=(coreutils) ;;

      # If something unexpected is missing, be explicit
      *) ;;
    esac
  done

  # De-duplicate
  local -a uniq_repo=() uniq_aur=()
  local p
  for p in "${repo_pkgs[@]}"; do
    [[ " ${uniq_repo[*]} " == *" $p "* ]] || uniq_repo+=("$p")
  done
  for p in "${aur_pkgs[@]}"; do
    [[ " ${uniq_aur[*]} " == *" $p "* ]] || uniq_aur+=("$p")
  done

  echo
  echo -e "${yellow}Missing hard dependencies detected.${reset}"
  echo -e "${orange}Missing commands:${reset} ${missing_cmds[*]}"
  ((${#uniq_repo[@]})) && echo -e "${orange}Repo packages:${reset} ${uniq_repo[*]}"
  ((${#uniq_aur[@]})) && echo -e "${orange}AUR packages:${reset} ${uniq_aur[*]}"
  echo -ne "${yellow}Install all missing dependencies now? [y/N]: ${reset}"
  read -r ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]] || return 1

  # Install yay first, then install repo deps and finally AUR deps.
  sudo pacman -Syy --noconfirm || return 1
  if ((need_yay)); then
    sudo pacman -S --needed --noconfirm yay || return 1
    # Remove yay from repo list so it isn't reinstalled
    local -a tmp=()
    for p in "${uniq_repo[@]}"; do
      [[ "$p" == "yay" ]] || tmp+=("$p")
    done
    uniq_repo=("${tmp[@]}")
  fi

  if ((${#uniq_repo[@]})); then
    sudo pacman -S --needed --noconfirm "${uniq_repo[@]}" || return 1
  fi
  if ((${#uniq_aur[@]})); then
    yay -S --needed --noconfirm "${uniq_aur[@]}" || return 1
  fi

  return 0
}
deps_check_and_install || exit 1



echo -ne "${reset}"
clear
progress_ui_init
show_progress "$current_step" "$total_steps"



# Initialize tmp workspace and enable logging.
# Duplicates output to screen while tee-ing to a tmpfs log.
rm -rf /tmp/manjaro
mkdir -p /tmp/manjaro
exec 3>&1 4>&2
log_dir="/tmp/manjaro/"
datetime_str=$(LC_TIME=el_GR.UTF-8 date +'%A_%d_%B_%I-%M%p')
log_file="Update-${datetime_str}.log"
log_path="${log_dir}${log_file}"
exec > >(tee -a "$log_path") 2>&1



# Report how long it has been since the last successful run.
# Uses the newest Update-*.log timestamp as the reference.
log_file=$(find "$HOME" -maxdepth 1 -type f -name 'Update-*.log' -printf '%T@ %p\n' 2>/dev/null | sort -nr | awk 'NR==1 {print $2}')
if [[ -f "$log_file" ]]; then
  file_time=$(stat -c %Y "$log_file")
  now_time=$(date +%s)
  seconds_diff=$(( now_time - file_time ))
  days=$(( seconds_diff / 86400 ))
  hours=$(( (seconds_diff % 86400) / 3600 ))
echo -e "${blue}Time since last update: ${orange}${days}${reset} days and ${orange}${hours}${reset} hours"
else
  echo -e "${red}No update logs found.${reset}"
fi
echo
echo



# Gate the run on basic NVMe SMART health.
# Avoids performing upgrades when storage is already unhealthy.
echo -e "\n${orange}Checking NVMe SMART health...${reset}"
root_src="$(findmnt -n -o SOURCE / 2>/dev/null)"
root_src="${root_src%%[*}"
[[ -n "$root_src" && "$root_src" == /dev/* ]] && root_src="$(realpath "$root_src" 2>/dev/null || echo "$root_src")"
disk="$root_src"
while true; do
pk="$(lsblk -no PKNAME "$disk" 2>/dev/null | head -n 1)"
[[ -z "$pk" ]] && break
disk="/dev/$pk"
done
if [[ -z "$disk" || "$disk" != /dev/* ]]; then
echo -e "\n${red}Error: could not detect OS disk device for /.${reset}"
echo -e "\n${red}Exiting script...${reset}"
read -r
exit 1
fi
SMART_DEV="$disk"
if [[ "$SMART_DEV" =~ ^/dev/nvme[0-9]+n[0-9]+p[0-9]+$ ]]; then
SMART_DEV="${SMART_DEV%p*}"
fi
echo
echo -e "Device: ${blue}${SMART_DEV}${reset}"
while true; do
out="$(sudo smartctl -a "$SMART_DEV" 2>/dev/null)"
st=$?
if (( st == 0 )); then
break
fi
echo -e "\n${red}Error: smartctl failed on ${SMART_DEV}.${reset}"
while true; do
echo
echo -ne "${yellow}(r)etry SMART check or (e)xit script: ${reset}"
read -r choice
echo
case "${choice,,}" in
r) break ;;
e)
echo -e "${red}Exiting script...${reset}"
exit 1
;;
*)
echo -e "${red}Please answer with (r)etry or (e)xit.${reset}"
;;
esac
done
done
crit="$(printf '%s\n' "$out" | grep -m1 -oP 'Critical Warning:\s*\K0x[0-9a-fA-F]+' || true)"
temp="$(printf '%s\n' "$out" | grep -m1 -oP 'Temperature:\s*\K[0-9]+' || true)"
spare="$(printf '%s\n' "$out" | grep -m1 -oP 'Available Spare:\s*\K[0-9]+' || true)"
thresh="$(printf '%s\n' "$out" | grep -m1 -oP 'Available Spare Threshold:\s*\K[0-9]+' || true)"
used="$(printf '%s\n' "$out" | grep -m1 -oP 'Percentage Used:\s*\K[0-9]+' || true)"
media_err="$(printf '%s\n' "$out" | grep -m1 -oP 'Media and Data Integrity Errors:\s*\K[0-9]+' || true)"
err_log="$(printf '%s\n' "$out" | grep -m1 -oP 'Error Information Log Entries:\s*\K[0-9]+' || true)"
crit="${crit:-0x00}"
temp="${temp:-NA}"
spare="${spare:-NA}"
thresh="${thresh:-NA}"
used="${used:-NA}"
media_err="${media_err:-NA}"
err_log="${err_log:-NA}"
health_ok=true
health_warn=false
if [[ "$spare" != "NA" && "$thresh" != "NA" ]] && (( spare < thresh )); then
health_ok=false
fi
if [[ "$crit" != "0x00" ]]; then
health_warn=true
fi
if [[ "$media_err" != "NA" ]] && (( media_err > 0 )); then
health_warn=true
fi
{
  echo "SMART full stats:"
  echo "Critical Warning: $crit"
  echo "Temperature: $temp C"
  echo "Available Spare: $spare%  Threshold: $thresh%"
  echo "Percentage Used: $used%"
  echo "Media/Data Integrity Errors: $media_err"
  echo "Error Log Entries: $err_log"
  echo
} >> "$log_path"
if [[ "$health_ok" == false ]]; then
echo -e "\n${red}SMART health looks BAD (Available Spare below threshold).${reset}"
echo
echo -e "Critical Warning:${reset} ${orange}${crit}${reset}"
echo -e "Temperature:${reset} ${orange}${temp}${reset} C"
echo -e "Available Spare:${reset} ${orange}${spare}${reset}%  Threshold:${reset} ${orange}${thresh}${reset}%"
echo -e "Percentage Used:${reset} ${orange}${used}${reset}%"
echo -e "Media/Data Integrity Errors:${reset} ${orange}${media_err}${reset}"
echo -e "Error Log Entries:${reset} ${orange}${err_log}${reset}"
while true; do
echo
echo -ne "${yellow}(r)etry SMART check or (e)xit script: ${reset}"
read -r choice
echo
case "${choice,,}" in
r) break ;;
e)
echo -e "${red}Exiting script...${reset}"
exit 1
;;
*)
echo -e "${red}Please answer with (r)etry or (e)xit.${reset}"
;;
esac
done
fi
if [[ "$health_warn" == true ]]; then
echo -e "\n${yellow}SMART reports warnings. Backups recommended.${reset}"
echo
echo -e "Critical Warning:${reset} ${orange}${crit}${reset}"
echo -e "Temperature:${reset} ${orange}${temp}${reset} C"
echo -e "Available Spare:${reset} ${orange}${spare}${reset}%  Threshold:${reset} ${orange}${thresh}${reset}%"
echo -e "Percentage Used:${reset} ${orange}${used}${reset}%"
echo -e "Media/Data Integrity Errors:${reset} ${orange}${media_err}${reset}"
echo -e "Error Log Entries:${reset} ${orange}${err_log}${reset}"
echo -ne "${yellow}Proceed anyway? (y)es or (e)xit script: ${reset}"
read -r go
echo
if [[ "${go,,}" != "y" ]]; then
echo -e "${red}Exiting script...${reset}"
exit 1
fi
else
echo -e "\n${green}SMART OK (temp ${temp}C, used ${used}%)${reset}"
fi
echo -e "\n"
echo -e "\n${orange}Checking for btrfs snapshots...${reset}"
if [[ ! -d "/.snapshots" ]]; then
echo -e "\n${red}Error: /.snapshots not found.${reset}"
echo -e "${yellow}Btrfs snapshots are not mounted/configured for root.${reset}"
echo -e "\n${red}Exiting script...${reset}"
read -r
exit 1
fi



# Btrfs snapshots handling
SNAPPER_CONFIG="$(
sudo snapper --csvout --separator '|' --no-headers list-configs --columns config,subvolume 2>/dev/null \
| awk -F'|' '$2=="/"{print $1; exit}'
)"
SNAPPER_CONFIG="${SNAPPER_CONFIG:-root}"
cutoff_epoch="$(date -d '7 days ago' +%s)"

# Helper function: get_recent_snapshots_sorted.
get_recent_snapshots_sorted() {
local out
while true; do
out="$(sudo snapper -c "$SNAPPER_CONFIG" --csvout --separator '|' --no-headers list --columns number,date,description 2>/dev/null)"
local status=$?
if (( status == 0 )); then
break
fi
echo -e "\n${red}Error: snapper list failed (config: ${SNAPPER_CONFIG}).${reset}"
while true; do
echo
echo -ne "${yellow}(r)etry or (e)xit script: ${reset}"
read -r choice
echo
case "${choice,,}" in
r) break ;;
e)
echo -e "${red}Exiting script...${reset}"
exit 1
;;
*)
echo -e "${red}Please answer with (r)etry or (e)xit.${reset}"
;;
esac
done
done
printf '%s\n' "$out" \
| awk -F'|' '$1 ~ /^[0-9]+$/ && $1 != "0" {print $1 "|" $2 "|" $3}' \
| while IFS='|' read -r num sdate desc; do
local snap_epoch
snap_epoch="$(date -d "$sdate" +%s 2>/dev/null || echo 0)"
if (( snap_epoch >= cutoff_epoch )); then
printf '%s|%s|%s|%s\n' "$snap_epoch" "$num" "$sdate" "$desc"
fi
done \
| sort -nr
}
mapfile -t recent_lines < <(get_recent_snapshots_sorted)
if (( ${#recent_lines[@]} > 0 )); then
echo -e "\n${green}Found Btrfs snapshot 7 days or newer, continuing...${reset}"
for line in "${recent_lines[@]}"; do
IFS='|' read -r epoch num sdate desc <<< "$line"
echo -e "${reset}${num}${reset}  ${sdate}  ${desc}"
done
echo -e "\n\n"
else
echo -e "\n${yellow}No snapshots found from the last 7 days.${reset}"
snapshot_desc="Update-$(date +%F_%H-%M-%S)"
new_num=""
while true; do
echo -e "\n${cyan}Creating snapshot: ${orange}${snapshot_desc}${reset}"
new_num="$(sudo snapper -c "$SNAPPER_CONFIG" create --description "$snapshot_desc" --print-number 2>/dev/null)"
snap_status=$?
if (( snap_status == 0 )) && [[ "$new_num" =~ ^[0-9]+$ ]]; then
echo -e "\n${green}Snapshot created: #${new_num} ${orange}${snapshot_desc}${reset}"
break
fi
echo -e "\n${red}Error: snapper snapshot creation failed.${reset}"
while true; do
echo
echo -ne "${yellow}(r)etry snapshot or (e)xit script: ${reset}"
read -r choice
echo
case "${choice,,}" in
r) break ;;
e)
echo -e "${red}Exiting script...${reset}"
exit 1
;;
*)
echo -e "${red}Please answer with (r)etry or (e)xit.${reset}"
;;
esac
done
done
while true; do
echo -e "\n${cyan}Updating GRUB config...${reset}"
if sudo grub-mkconfig -o /boot/grub/grub.cfg; then
echo -e "\n${green}GRUB updated successfully.${reset}"
echo -e "\n\n"
break
fi
echo -e "\n${red}Error: grub-mkconfig failed.${reset}"
while true; do
echo
echo -ne "${yellow}(r)etry grub update or (e)xit script: ${reset}"
read -r choice
echo
case "${choice,,}" in
r) break ;;
e)
echo -e "${red}Exiting script...${reset}"
exit 1
;;
*)
echo -e "${red}Please answer with (r)etry or (e)xit.${reset}"
;;
esac
done
done
fi



# Manjaro forum stats
CATEGORY_JSON="/tmp/manjaro/category.json"
TOPIC_JSON="/tmp/manjaro/topic.json"
if ! curl -fsSL -A 'Mozilla/5.0' \
  "https://forum.manjaro.org/c/announcements/stable-updates/12.json" \
  -o "$CATEGORY_JSON"; then
  FIRST_TOPIC_URL=""
  TOPIC_JSON_URL=""
  VOTERS=0
  NO_ISSUE_VOTES=0
else
  FIRST_TOPIC_URL="$(
    python3 - <<'PY' "$CATEGORY_JSON" 2>/dev/null
import json,sys
d=json.load(open(sys.argv[1]))
topics=sorted(d["topic_list"]["topics"], key=lambda t: t.get("created_at",""), reverse=True)
for t in topics:
    if not t.get("pinned", False):
        print(f'https://forum.manjaro.org/t/{t["slug"]}/{t["id"]}')
        break
PY
  )"
  if [[ -n "$FIRST_TOPIC_URL" ]]; then
    TOPIC_JSON_URL="${FIRST_TOPIC_URL}.json"
    if curl -fsSL -A 'Mozilla/5.0' "$TOPIC_JSON_URL" -o "$TOPIC_JSON"; then
      read -r VOTERS NO_ISSUE_VOTES <<<"$(
        python3 - <<'PY' "$TOPIC_JSON" 2>/dev/null
import json,sys
d=json.load(open(sys.argv[1]))
posts=d.get("post_stream",{}).get("posts",[])
poll=None
for p in posts:
    pls=p.get("polls") or []
    if pls:
        poll=pls[0]
        break
if not poll:
    print("0 0"); raise SystemExit
voters=int(poll.get("voters",0) or 0)
no_issue=0
for opt in poll.get("options",[]):
    txt=(opt.get("html","") or "").lower()
    if "no issu" in txt or "smooth" in txt:
        no_issue=int(opt.get("votes",0) or 0)
        break
print(voters, no_issue)
PY
      )"
      VOTERS="${VOTERS:-0}"
      NO_ISSUE_VOTES="${NO_ISSUE_VOTES:-0}"
    else
      VOTERS=0
      NO_ISSUE_VOTES=0
    fi
  else
    TOPIC_JSON_URL=""
    VOTERS=0
    NO_ISSUE_VOTES=0
  fi
fi
if [[ -n "$VOTERS" && "$VOTERS" -ne 0 ]]; then
  NO_ISSUE_PERCENT=$(( (100 * NO_ISSUE_VOTES + VOTERS/2) / VOTERS ))
  PERCENT_TEXT="${NO_ISSUE_PERCENT}"
else
  NO_ISSUE_PERCENT=-1
  PERCENT_TEXT="N/A"
fi
echo -e "No issue: ${orange}${PERCENT_TEXT}${reset}%  Total votes: ${VOTERS:-0}"
echo
echo
echo
aur_count=$(pacman -Qm | wc -l)
extensions_count=$(gext list | wc -l)
flatpak_count=$(flatpak list --app --columns=application 2>/dev/null | wc -l)
echo -e "${reset}Aur: ${orange}${aur_count}${reset}  Extensions: ${orange}${extensions_count}${reset}  Flatpaks: ${flatpak_count}"
read total used avail <<< $(df / --block-size=1 | awk 'NR==2 {print $2, $3, $4}')
percent=$(awk -v u="$used" -v t="$total" 'BEGIN { printf "%.1f", (u/t)*100 }')
used_gb=$(awk -v u="$used" 'BEGIN { printf "%.1f", u/1e9 }')
explicit_count=$(pacman -Qe | wc -l)
echo -e "${reset}Disk used: ${orange}${used_gb}${reset}GB (${percent}% full)  Programs: ${explicit_count}"



# Run a command with consistent logging and error handling.
# Shows status, captures failures, and preserves exit codes.
run_command() {
  local pretty="$*"
  echo -e "\n\n\n${cyan}Running: ${pretty}${reset}"
  if (( $# == 0 )); then
    echo -e "${red}Error: run_command called with no arguments.${reset}"
    return 1
  fi
  local status=0
  "$@"
  status=$?
  if (( status != 0 )); then
    echo -e "${red}Error: Command '${pretty}' failed with exit code ${status}${reset}"
    return 1
  fi
  echo -e "${green}Command '${pretty}' completed successfully.${reset}"
  return 0
}



# Helper function: prompt_for_db_lock_resolution.
prompt_for_db_lock_resolution() {
  while [[ -f /var/lib/pacman/db.lck ]]; do
    echo > /dev/tty
    echo -ne "${yellow}Pacman database is locked. (r)etry  (d)elete lock  (e)xit:${reset} " > /dev/tty
    read -r choice < /dev/tty
    echo > /dev/tty
    case "${choice,,}" in
      r)
        echo -e "${cyan}Retrying in 5 seconds...${reset}" > /dev/tty
        sleep 5
        ;;
      d)
        echo -e "${cyan}Checking who holds the lock...${reset}" > /dev/tty
        if sudo fuser -v /var/lib/pacman/db.lck >/dev/tty 2>&1; then
          echo -e "${red}Lock appears to be in use. Not deleting.${reset}" > /dev/tty
          echo -e "${yellow}Close pamac/Octopi or kill the shown PID, then retry.${reset}" > /dev/tty
        else
          echo -e "${cyan}No process reported. Deleting lock file...${reset}" > /dev/tty
          if sudo rm -f /var/lib/pacman/db.lck; then
            echo -e "${green}Lock file deleted.${reset}" > /dev/tty
          else
            echo -e "${red}Failed to delete lock file.${reset}" > /dev/tty
          fi
        fi
        ;;
      e)
        echo -e "${red}Exiting due to pacman lock.${reset}" > /dev/tty
        exit 1
        ;;
      *)
        echo -e "${red}Invalid choice. Try again.${reset}" > /dev/tty
        ;;
    esac
  done
}
if (( NO_ISSUE_PERCENT < 85 || VOTERS < 200 )); then
  echo -ne "${red}Low 'No issue' percentage or low Voters count. (y)es to open Manjaro topic or any other key to continue: ${reset}"
  read -r REPLY
  if [[ "${REPLY,,}" == "y" ]]; then
    xdg-open "$FIRST_TOPIC_URL" >/dev/null 2>&1 &
  fi
  echo -e "\n\n"
fi
echo -e "\n\n"
echo -ne "${yellow}Proceed with the update? (n)o or any other key: ${reset}"
read -rp "" update
if [[ "${update,,}" = "n" ]]; then
  exit
fi



echo -e "\n\n\n\n${purple}$(printf '%*s' 49 '' | tr ' ' '-') Mirrors refresh $(printf '%*s' 49 '' | tr ' ' '-')${reset}"



# Refresh and validate mirror configuration for stable updates.
# Rebuilds a sane mirrorlist and warns if the result is too small.
refresh_mirrors=true
MIRRORLIST="/etc/pacman.d/mirrorlist"
if [[ -f "$MIRRORLIST" ]]; then
  mirrorlist_age=$(( $(date +%s) - $(stat -c %Y "$MIRRORLIST") ))
  if (( mirrorlist_age < 7200 )); then
    echo -e "\n\n\n"
    echo -ne "${yellow}Mirrorlist refreshed within the last 2 hours. (r)efresh anyway or any other key to continue: ${reset}"
    read -r mirror_recent_choice
    if [[ "${mirror_recent_choice,,}" != "r" ]]; then
      refresh_mirrors=false
    fi
  fi
fi
if [[ "$refresh_mirrors" == true ]]; then
while true; do
  if run_command sudo pacman-mirrors --fasttrack 10 --api --protocols all --set-branch stable; then
    MIRRORLIST="/etc/pacman.d/mirrorlist"
    mirror_count=$(grep -c '^Server *= *' "$MIRRORLIST")
    echo
    echo -e "${reset}Mirrors saved: ${orange}$mirror_count${reset}"
    if (( mirror_count >= 6 )); then
      break
    else
      if [[ -z "${mirror_prompt_shown:-}" ]]; then
        echo
        echo -ne "${red}Synced mirrors are less than 6.  ${yellow}(o)pen Manjaro status of mirrors page, or any other key to continue: ${reset}"
        read -r open_status
        if [[ "${open_status,,}" == "o" ]]; then
          xdg-open "https://repo.manjaro.org/" >/dev/null 2>&1 &
        fi
        mirror_prompt_shown=1
      fi
      echo
      echo -e "${red}Mirror count too low.${reset}"
    fi
  else
    echo
    echo -e "${red}Failed to refresh mirrors.${reset}"
  fi
  while true; do
    echo
    echo -ne "${yellow}(r)etry Fasttrack  (u)se Global mirrors  (c)ontinue script  or (e)xit: ${reset}"
    read -r choice
    case "${choice,,}" in
      r)
        break  # restart fasttrack attempt
        ;;
      u)
        if run_command sudo pacman-mirrors --country all --api --protocols all --set-branch stable; then
          MIRRORLIST="/etc/pacman.d/mirrorlist"
          mirror_count=$(grep -c '^Server *= *' "$MIRRORLIST")
          echo
          echo -e "${reset}Mirrors saved: ${orange}$mirror_count${reset}"
          if (( mirror_count >= 6 )); then
            break 2  # done with mirror setup, exit both loops
          else
            echo
            echo -e "${red}Mirror count too low.${reset}"
          fi
        else
          echo
          echo -e "${red}Global mirrors refresh failed.${reset}"
        fi
        ;;
      c)
        echo
        echo -e "${cyan}Continuing script despite mirror issues...${reset}"
        break 2  # break out of both loops, continue script
        ;;
      e)
        echo -e "${red}Exiting.${reset}"
        exit 1
        ;;
      *)
        echo
        echo -e "${red}Invalid choice. Please try again.${reset}"
        ;;
    esac
  done
done
fi



((++current_step)); show_progress $current_step $total_steps
echo -e "\n\n\n\n${purple}$(printf '%*s' 48 '' | tr ' ' '-') Packages updates $(printf '%*s' 49 '' | tr ' ' '-')${reset}"
echo -e "\n\n\n"



# Dry run to check imminent updates volume
echo -e "${yellow}Checking real update size (dry run)...${reset}"
prompt_for_db_lock_resolution
sudo pacman -Syy --noconfirm >/dev/null
mapfile -t repo_up < <(pacman -Qu 2>/dev/null)
total_bytes=0
if (( ${#repo_up[@]} == 0 )); then
  echo -e "Packages to update (repo): 0"
  echo -e "Total download size (repo): 0.00 MiB"
else
  echo -e "Packages to update (repo): ${#repo_up[@]}"
  printf '%s\n' "${repo_up[@]}" | sed 's/^/  - /'
  total_bytes="$(sudo pacman -Sup --print-format '%s\n' 2>/dev/null | awk '{s+=$1} END{print s+0}')"
  awk -v b="$total_bytes" 'BEGIN{printf "Total download size (repo): %.2f MiB\n", b/1024/1024}'
fi
threshold_bytes=$((300 * 1024 * 1024))
if (( total_bytes >= threshold_bytes )); then
  echo
  echo -ne "${yellow}Proceed with the update? (n)o or any other key: ${reset}"
  read -rp "" update
  if [[ "${update,,}" = "n" ]]; then
    exit
  fi
fi



# Helper function: replace_aur_with_repo.
replace_aur_with_repo() {
echo -e "\n\n\n"
echo -e "${cyan}Checking for AUR packages that now exist in Manjaro repos...${reset}"

local exclude_file="$HOME/.aur_excluded_pkg"
sudo -u "$USER" touch "$exclude_file"

declare -A excluded=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  excluded["$line"]=1
done < "$exclude_file"

local default_suffixes=(
"-git" "-bin" "-vcs" "-aur" "-devel" "-nightly" "-wayland" "-stable" "-legacy"
"-nox" "-gtk2" "-gtk3" "-gtk4" "-qt4" "-qt5" "-qt6" "-beta" "-alpha"
)
local suffixes=("${default_suffixes[@]}")

if [[ ! -f /tmp/manjaro/repo_pkgs.txt ]]; then
  echo -e "${red}Repo package list file /tmp/manjaro/repo_pkgs.txt not found! Run pacman -Sl to generate it.${reset}"
  return 1
fi

mapfile -t repo_pkgs < "/tmp/manjaro/repo_pkgs.txt"
mapfile -t aur_pkgs < <(pacman -Qm | awk '{print $1}' | sort)

if (( ${#aur_pkgs[@]} == 0 )); then
  echo
  echo -e "${orange}No AUR packages detected.${green} Nothing to check.${reset}"
  return 0
fi

# Shared replacement list (parent scope)
local -a to_replace=()

# Helper function: add_to_exclude_file.
add_to_exclude_file() {
  local pkg="$1"
  if ! grep -qxF "$pkg" "$exclude_file"; then
    printf '%s\n' "$pkg" >> "$exclude_file"
  fi
  excluded["$pkg"]=1
}

# Helper function: fuzzy_match.
fuzzy_match() {
  local aur_pkg="$1"
  local aur_base="$2"
  local aur_base_esc
  aur_base_esc=$(printf '%s' "$aur_base" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g')

  mapfile -t matches < <(
    printf '%s\n' "${repo_pkgs[@]}" |
    grep -iE "(^|[-_])${aur_base_esc}($|[-_])"
  )

  if (( ${#matches[@]} == 0 )); then
    echo ""
    return
  fi

  {
    echo
    echo -e "${yellow}Fuzzy matches for '$aur_base' (from AUR '$aur_pkg'):${reset}"
    local i=1
    for match in "${matches[@]}"; do
      echo " [$i] $match"
      ((i++))
    done
    echo " [0] Skip"
    echo " [x] Exclude '$aur_pkg' permanently"
  } > /dev/tty

  local choice
  while true; do
    echo -ne "${cyan}Choose number / 0 / x: ${reset}" > /dev/tty
    read -r choice < /dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice < i )); then
      break
    elif [[ "${choice,,}" == "x" ]]; then
      break
    fi
  done

  if [[ "${choice,,}" == "x" ]]; then
    add_to_exclude_file "$aur_pkg"
    echo ""
  elif (( choice == 0 )); then
    echo ""
  else
    echo "${matches[choice-1]}"
  fi
}

# Helper function: find_aur_replacements.
find_aur_replacements() {
  local aur_pkgs=("$@")
  to_replace=()   # reset shared array

  for aur in "${aur_pkgs[@]}"; do
    if [[ -n "${excluded[$aur]:-}" ]]; then
      echo -e "Excluded from replacement (persistent):${blue} ${aur}${reset}"
      continue
    fi

    local base="$aur"
    for suf in "${suffixes[@]}"; do
      if [[ "$aur" == *"$suf" ]]; then
        base="${aur%"$suf"}"
        break
      fi
    done

    if [[ " ${repo_pkgs[*]} " == *" $base "* ]]; then
      to_replace+=("$aur|$base")
    else
      local matched_pkg
      matched_pkg="$(fuzzy_match "$aur" "$base")"
      [[ -n "$matched_pkg" ]] && to_replace+=("$aur|$matched_pkg") || true
    fi
  done
}

find_aur_replacements "${aur_pkgs[@]}"

local valid_replace=()
for entry in "${to_replace[@]}"; do
  local aur="${entry%%|*}"
  local base="${entry##*|}"
  [[ -n "$aur" && -n "$base" ]] && valid_replace+=("$entry")
done

if (( ${#valid_replace[@]} == 0 )); then
  echo -e "${orange}No AUR packages found in official repos (after exclusions).${cyan} Nothing to replace.${reset}"
  return 0
fi

echo
echo -e "${yellow}The following AUR packages are now in the official repos:${reset}"
printf "%-30s %-30s\n" "AUR Package" "Repo Package"
printf "%-30s %-30s\n" "-----------" "------------"

for entry in "${valid_replace[@]}"; do
  local aur="${entry%%|*}"
  local base="${entry##*|}"
  printf "%-30s %-30s\n" "$aur" "$base"
done

echo
echo -ne "${cyan}Proceed with replacing them? (y)es or any other key to skip: ${reset}"
read -r choice < /dev/tty

if [[ "$choice" =~ ^[Yy]$ ]]; then
  for entry in "${valid_replace[@]}"; do
    local aur="${entry%%|*}"
    local base="${entry##*|}"

    echo -e "${cyan}Removing AUR package: $aur...${reset}"
    if ! run_command yay -Rns --noconfirm "$aur"; then
      echo -e "${red}Failed to remove $aur. Skipping this package.${reset}"
      continue
    fi

    echo -e "${cyan}Installing repo package: $base...${reset}"
    prompt_for_db_lock_resolution
    if ! run_command sudo pacman -S --noconfirm "$base"; then
      echo -e "${red}Failed to install $base. Attempting to reinstall $aur...${reset}"
      run_command yay -S --noconfirm "$aur"
      continue
    fi

    echo -e "${green}Replaced $aur with $base successfully.${reset}"
  done

  echo
  echo -e "${green}All replacements completed.${reset}"
else
  echo
  echo -e "${red}Replacement operation skipped by user.${reset}"
fi
}



# Helper function: replace_flatpaks_with_repo.
replace_flatpaks_with_repo() {
echo -e "\n\n\n"
echo -e "${cyan}Checking for Flatpak apps that also exist as Manjaro repo packages...${reset}"

local exclude_file="$HOME/.flatpak_excluded_app"
touch "$exclude_file"

local -a to_replace=()
declare -A excluded=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  excluded["$line"]=1
done < "$exclude_file"

local default_suffixes=(
"-git" "-bin" "-vcs" "-aur" "-devel" "-nightly" "-wayland" "-stable" "-legacy"
"-nox" "-gtk2" "-gtk3" "-gtk4" "-qt4" "-qt5" "-qt6" "-beta" "-alpha"
)
local suffixes=("${default_suffixes[@]}")

if [[ ! -f /tmp/manjaro/repo_pkgs.txt ]]; then
  echo -e "${red}Repo package list file /tmp/manjaro/repo_pkgs.txt not found! Run pacman -Sl to generate it.${reset}"
  return 1
fi

mapfile -t repo_pkgs < "/tmp/manjaro/repo_pkgs.txt"

mapfile -t flatpak_rows < <(
  flatpak list --app --columns=application,origin,installation 2>/dev/null |
  awk 'NF{print $1 "|" $2 "|" $3}' | sort -u
)

if (( ${#flatpak_rows[@]} == 0 )); then
  echo
  echo -e "${orange}No Flatpaks detected.${green} Nothing to check.${reset}"
  return 0
fi

# --- Flatpak-scoped helper functions ---

fp_add_to_exclude_file() {
  local appid="$1"
  if ! grep -qxF "$appid" "$exclude_file"; then
    printf '%s\n' "$appid" >> "$exclude_file"
  fi
  excluded["$appid"]=1
}

fp_flatpak_base_from_appid() {
  local appid="$1"
  local last="${appid##*.}"
  local base="$last"
  case "$last" in
    Client|client|Desktop|desktop|App|app)
      local prev="${appid%.*}"
      base="${prev##*.}"
    ;;
  esac
  local suf
  for suf in "${suffixes[@]}"; do
    if [[ "$base" == *"$suf" ]]; then
      base="${base%"$suf"}"
      break
    fi
  done
  printf '%s' "$base"
}

fp_fuzzy_match() {
  local appid="$1"
  local base="$2"
  local base_esc
  base_esc=$(printf '%s' "$base" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g')

  mapfile -t matches < <(
    printf '%s\n' "${repo_pkgs[@]}" | grep -iE "(^|[-_])${base_esc}($|[-_])"
  )

  if (( ${#matches[@]} == 0 )); then
    echo ""
    return
  fi

  {
    echo
    echo -e "${yellow}Fuzzy matches for '$base' (from Flatpak '$appid'):${reset}"
    local i=1
    for match in "${matches[@]}"; do
      echo " [$i] $match"
      ((i++))
    done
    echo " [0] Skip"
    echo " [x] Exclude '$appid' permanently"
  } > /dev/tty

  local choice
  while true; do
    echo -ne "${cyan}Choose number / 0 / x: ${reset}" > /dev/tty
    read -r choice < /dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice < i )); then
      break
    elif [[ "${choice,,}" == "x" ]]; then
      break
    fi
  done

  if [[ "${choice,,}" == "x" ]]; then
    fp_add_to_exclude_file "$appid"
    echo ""
  elif (( choice == 0 )); then
    echo ""
  else
    echo "${matches[choice-1]}"
  fi
}

fp_find_flatpak_replacements() {
  local rows=("$@")
  to_replace=()
  local row appid origin install base matched_pkg

  for row in "${rows[@]}"; do
    appid="${row%%|*}"
    origin="${row#*|}"; origin="${origin%%|*}"
    install="${row##*|}"

    if [[ -n "${excluded[$appid]:-}" ]]; then
      echo -e "Excluded from replacement (persistent):${blue} ${appid}${reset}"
      continue
    fi

    base="$(fp_flatpak_base_from_appid "$appid")"

    if [[ " ${repo_pkgs[*]} " == *" $base "* ]]; then
      to_replace+=("$appid|$origin|$install|$base")
    else
      matched_pkg="$(fp_fuzzy_match "$appid" "$base")"
      [[ -n "$matched_pkg" ]] && to_replace+=("$appid|$origin|$install|$matched_pkg") || true
    fi
  done
}

fp_find_flatpak_replacements "${flatpak_rows[@]}"

local valid_replace=()
local entry appid origin install repo_pkg

for entry in "${to_replace[@]}"; do
  appid="$(cut -d'|' -f1 <<<"$entry")"
  origin="$(cut -d'|' -f2 <<<"$entry")"
  install="$(cut -d'|' -f3 <<<"$entry")"
  repo_pkg="$(cut -d'|' -f4- <<<"$entry")"
  [[ -n "$appid" && -n "$repo_pkg" ]] && valid_replace+=("$entry")
done

if (( ${#valid_replace[@]} == 0 )); then
  echo -e "${orange}No Flatpaks found with matching Manjaro repo packages (after exclusions).${cyan} Nothing to replace.${reset}"
  return 0
fi

echo
echo -e "${yellow}The following Flatpaks appear to exist as Manjaro repo packages:${reset}"
printf "%-45s %-8s %-20s %-30s\n" "Flatpak AppID" "Scope" "Origin" "Repo Package"
printf "%-45s %-8s %-20s %-30s\n" "-----------" "-----" "------" "------------"

for entry in "${valid_replace[@]}"; do
  appid="$(cut -d'|' -f1 <<<"$entry")"
  origin="$(cut -d'|' -f2 <<<"$entry")"
  install="$(cut -d'|' -f3 <<<"$entry")"
  repo_pkg="$(cut -d'|' -f4- <<<"$entry")"
  printf "%-45s %-8s %-20s %-30s\n" "$appid" "$install" "${origin:-NA}" "$repo_pkg"
done

echo
echo -ne "${cyan}Proceed with replacing them? (y)es or any other key to skip: ${reset}"
read -r choice < /dev/tty

if [[ "$choice" =~ ^[Yy]$ ]]; then
  for entry in "${valid_replace[@]}"; do
    appid="$(cut -d'|' -f1 <<<"$entry")"
    origin="$(cut -d'|' -f2 <<<"$entry")"
    install="$(cut -d'|' -f3 <<<"$entry")"
    repo_pkg="$(cut -d'|' -f4- <<<"$entry")"

    echo -e "${cyan}Removing Flatpak app: $appid...${reset}"
    if [[ "$install" == "user" ]]; then
      run_command flatpak uninstall -y --user "$appid" || continue
    else
      run_command sudo flatpak uninstall -y --system "$appid" || continue
    fi

    echo -e "${cyan}Installing repo package: $repo_pkg...${reset}"
    prompt_for_db_lock_resolution
    if ! run_command sudo pacman -S --noconfirm "$repo_pkg"; then
      echo -e "${red}Failed to install $repo_pkg. Attempting to reinstall Flatpak $appid...${reset}"
      if [[ -n "$origin" && "$origin" != "NA" ]]; then
        [[ "$install" == "user" ]] && run_command flatpak install -y --user "$origin" "$appid" \
                                   || run_command sudo flatpak install -y --system "$origin" "$appid"
      fi
      continue
    fi

    echo -e "${green}Replaced Flatpak $appid with repo package $repo_pkg successfully.${reset}"
  done
  echo -e "${green}All Flatpak replacements completed.${reset}"
else
  echo -e "${red}Replacement operation skipped by user.${reset}"
fi
}



# Orchestrate the full update flow across pacman, AUR, and Flatpak.
perform_updates() {
  echo
  prompt_for_db_lock_resolution

  # ---- Pacman repo update loop (hard gate) ----
  while true; do
    local pacman_tmp_log="/tmp/manjaro/pacman_attempt.log"
    : > "$pacman_tmp_log"

    local had_pipefail=0
    set -o | grep -q 'pipefail[[:space:]]*on' && had_pipefail=1
    set -o pipefail

    local pacman_log="/var/log/pacman.log"
    local log_start
    log_start=$(wc -l < "$pacman_log" 2>/dev/null || echo 0)

    echo -e "\n\n\n${cyan}Running: sudo pacman -Syyu --noconfirm >&3 2>&4${reset}"
    sudo pacman -Syyu --noconfirm >&3 2>&4
    local status=$?
    if (( status == 0 )); then
  echo -e "${green}Command 'sudo pacman -Syyu --noconfirm >&3 2>&4' completed successfully.${reset}"
else
  echo -e "${red}Command 'sudo pacman -Syyu --noconfirm >&3 2>&4' failed with exit code ${status}.${reset}"
fi

    [[ -r "$pacman_log" ]] || : > "$pacman_tmp_log"
    tail -n +"$((log_start + 1))" "$pacman_log" > "$pacman_tmp_log" 2>/dev/null
    cat "$pacman_tmp_log" >> "$log_path"
    if (( status == 0 )); then
      (( had_pipefail == 0 )) && set +o pipefail
      break
    fi

    (( had_pipefail == 0 )) && set +o pipefail

    # ---- Failure classification ----
    if grep -qiE '(signature.*(could not be verified|invalid|unknown|revoked|failed)|invalid.*signature|failed to verify signature|keyring|gpgme|gpg:|public key|unknown trust|marginal trust|trust database|expired key|revoked key)' "$pacman_tmp_log"; then
      echo
      echo -e "${red}PGP / signature error detected.${reset}"
      echo
      echo "Choose recovery action:"
      echo "  [r] Refresh keyring (non-destructive)"
      echo "  [n] Nuke keyring and rebuild"
      echo "  [e] Exit"
      read -rp "> " ans
      case "${ans,,}" in
        r)
          echo -e "${cyan}Refreshing keyring...${reset}"
          sudo pacman -Syy --noconfirm archlinux-keyring manjaro-keyring || true
          sudo pacman-key --refresh-keys || true
          continue
          ;;
        n)
          echo -e "${yellow}Nuking keyring and rebuilding...${reset}"
          sudo rm -rf /etc/pacman.d/gnupg
          sudo pacman-key --init
          sudo pacman-key --populate archlinux manjaro
          continue
          ;;
        e)
          echo -e "${red}Aborting.${reset}"
          return 1
          ;;
        *)
          echo -e "${red}Invalid choice. Aborting.${reset}"
          return 1
          ;;
      esac
    else
      echo
      echo -e "${red}Pacman failed (non-PGP error).${reset}"
      echo "Choose action:"
      echo "  [r] Retry"
      echo "  [e] Exit"
      read -rp "> " ans
      case "${ans,,}" in
        r) continue ;;
        e) return 1 ;;
        *) echo -e "${red}Invalid choice. Exiting.${reset}"; return 1 ;;
      esac
    fi
  done

  # ---- Repo package list (warning only) ----
  mkdir -p /tmp/manjaro
  if ! pacman -Slq | sort -u > /tmp/manjaro/repo_pkgs.txt; then
    echo
    echo -e "${yellow}WARNING: Failed to generate repo package list.${reset}"
  fi

  # ---- Replace AUR with repo ----
  replace_aur_with_repo

  # ---- Yay update (best effort) ----
  prompt_for_db_lock_resolution
  while true; do
    if run_command yay -Syu --devel --timeupdate --noconfirm --cleanafter --editmenu=false --combinedupgrade; then
      break
    fi
    echo
    echo -e "${red}Yay update failed.${reset}"
    echo "Choose action:"
    echo "  [r] Retry yay"
    echo "  [c] Continue without yay"
    read -rp "> " ans
    case "${ans,,}" in
      r) continue ;;
      c) break ;;
      *) break ;;
    esac
  done

  return 0
}



# Helper function: rebuild_aur_if_needed.
rebuild_aur_if_needed() {
  echo -e "\n\n"
  echo -e "${cyan}Checking for packages that need rebuild (rebuild-detector)...${reset}"
  mapfile -t need_rebuild < <(checkrebuild 2>/dev/null | awk '$1=="foreign"{print $2}' | sort -u)
  if (( ${#need_rebuild[@]} == 0 )); then
    echo -e "${green}No rebuilds needed.${reset}"
    return 0
  fi
    local -A is_aur=()
  while read -r p _; do
    [[ -n "$p" ]] && is_aur["$p"]=1
  done < <(pacman -Qm)
  local -a aur_to_rebuild=()
  for p in "${need_rebuild[@]}"; do
    if [[ -n "${is_aur[$p]:-}" ]]; then
      aur_to_rebuild+=("$p")
    fi
  done
  if (( ${#aur_to_rebuild[@]} == 0 )); then
    echo -e "${yellow}Rebuild-detector flagged packages, but none are installed AUR packages. Skipping yay rebuild.${reset}"
    echo -e "${blue}Flagged:${reset} ${need_rebuild[*]}"
    return 0
  fi
  echo -e "${orange}AUR packages to rebuild:${reset} ${aur_to_rebuild[*]}"
  if ! run_command yay -S --noconfirm --rebuild --rebuildtree --cleanafter --editmenu=false "${aur_to_rebuild[@]}"; then
    echo
    echo -e "${red}AUR rebuild step failed.${reset}"
    return 1
  fi
  echo -e "${green}AUR rebuild step completed.${reset}"
  return 0
}
# ---- Call site: hard gate updates, then rebuild ----
if ! perform_updates; then
  echo -e "${red}Update stage failed. Exiting.${reset}"
  exit 1
fi
rebuild_aur_if_needed || echo -e "${yellow}Rebuild skipped/failed.${reset}"



((++current_step)); show_progress $current_step $total_steps
echo -e "\n\n\n\n${purple}$(printf '%*s' 43 '' | tr ' ' '-') Extensions-Flatpaks updates $(printf '%*s' 43 '' | tr ' ' '-')${reset}"



# Extensions updates
if ! run_command gext update -y; then
  echo
  echo -e "${red}User extensions updates failed, continuing...${reset}"
fi
replace_flatpaks_with_repo
if ! run_command sudo flatpak update -y; then
  echo
  echo -e "${red}Flatpak update (sudo) failed, continuing...${reset}"
fi
if ! run_command flatpak update -y; then
  echo
  echo -e "${red}Flatpak update (user) failed, continuing...${reset}"
fi



((++current_step)); show_progress $current_step $total_steps
echo -e "\n\n\n\n${purple}$(printf '%*s' 49 '' | tr ' ' '-') Cleanup-Repairs $(printf '%*s' 49 '' | tr ' ' '-')${reset}"
echo -e "\n\n\n"



# Pacman  orphaned packages
echo -e "${cyan}Checking for orphaned packages...${reset}"
mapfile -t orphaned_packages < <(sudo pacman -Qtdq)
if [ ${#orphaned_packages[@]} -ne 0 ]; then
  prompt_for_db_lock_resolution
  if sudo pacman -Rns --noconfirm "${orphaned_packages[@]}"; then
    echo
    echo -e "${green}Orphaned packages removed.${reset}"
  else
    echo
    echo -e "${red}Failed to remove orphaned packages, continuing...${reset}"
  fi
else
  echo
  echo -e "${cyan}No orphaned packages found.${reset}"
fi
prompt_for_db_lock_resolution
if ! run_command bash -c "yes | sudo pacman -Scc"; then
  echo
  echo -e "${red}Failed to clean package cache with pacman -Scc, trying manual cache deletion...${reset}"
  run_command sudo rm -rf /var/cache/pacman/pkg/*
fi



# Flatpak cleanup
if ! run_command flatpak uninstall --unused -y; then
  echo
  echo -e "${red}Flatpak clean orphaned components failed, continuing...${reset}"
fi
echo -e "\n\n\n"
echo -e "${cyan}Running: flatpak uninstall --delete-data -y${reset}\n"
flatpak uninstall --delete-data -y
status=$?
if (( status == 0 )); then
echo -e "${green}Command 'flatpak uninstall --delete-data -y' completed successfully.${reset}"
else
echo
echo -e "${red}Error: Command 'flatpak uninstall --delete-data -y' failed with exit code ${status}${reset}"
echo
echo -e "${red}Flatpak unowned app data cleanup failed, continuing...${reset}"
fi
echo -e "\n\n\n"
echo -e "${cyan}Checking for leftover Flatpak app data...${reset}"
mapfile -t leftover_apps < <(comm -23 <(ls ~/.var/app | sort) <(flatpak list --app --columns=application | sort))
if [ ${#leftover_apps[@]} -ne 0 ]; then
  if rm -rf -- "${leftover_apps[@]/#/$HOME/.var/app/}"; then
    echo
    echo -e "${green}Leftover Flatpak app data deleted.${reset}"
  else
    echo
    echo -e "${red}Failed to remove some leftover Flatpak app data, continuing...${reset}"
  fi
else
  echo
  echo -e "${cyan}No leftover Flatpak app data found.${reset}"
fi
echo -e "\n\n\n"
echo -e "${cyan}Checking Flatpak exports (user) for broken symlinks...${reset}"
if [[ -d "$HOME/.local/share/flatpak/exports" ]]; then
  mapfile -t broken_user < <(find "$HOME/.local/share/flatpak/exports" -xtype l 2>/dev/null)
  if (( ${#broken_user[@]} > 0 )); then
    echo
    echo -e "${yellow}Broken user export links found:${reset}"
    printf '%s\n' "${broken_user[@]}"
    if find "$HOME/.local/share/flatpak/exports" -xtype l -delete 2>/dev/null; then
      echo
      echo -e "${green}Removed ${#broken_user[@]} broken Flatpak export links (user).${reset}"
    else
      echo
      echo -e "${red}Failed to remove some broken Flatpak export links (user), continuing...${reset}"
    fi
  else
    echo
    echo -e "${cyan}No broken Flatpak export links (user) found.${reset}"
  fi
else
  echo
  echo -e "${cyan}No Flatpak exports directory (user) found.${reset}"
fi
echo -e "\n\n\n"
echo -e "${cyan}Checking Flatpak exports (system) for broken symlinks...${reset}"
if sudo test -d /var/lib/flatpak/exports; then
  mapfile -t broken_sys < <(sudo find /var/lib/flatpak/exports -xtype l 2>/dev/null)
  if (( ${#broken_sys[@]} > 0 )); then
    echo
    echo -e "${yellow}Broken system export links found:${reset}"
    printf '%s\n' "${broken_sys[@]}"
    if sudo find /var/lib/flatpak/exports -xtype l -delete 2>/dev/null; then
      echo
      echo -e "${green}Removed ${#broken_sys[@]} broken Flatpak export links (system).${reset}"
    else
      echo
      echo -e "${red}Failed to remove some broken Flatpak export links (system), continuing...${reset}"
    fi
  else
    echo
    echo -e "${cyan}No broken Flatpak export links (system) found.${reset}"
  fi
else
  echo
  echo -e "${cyan}No Flatpak exports directory (system) found.${reset}"
fi
echo -e "\n\n\n"
echo -e "${cyan}Checking for orphaned Flatpak overrides (user)...${reset}"
if [[ -d "$HOME/.local/share/flatpak/overrides" ]]; then
  mapfile -t orphan_overrides_user < <(
    find "$HOME/.local/share/flatpak/overrides" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null \
    | while read -r appid; do
        flatpak info "$appid" >/dev/null 2>&1 || echo "$appid"
      done
  )
  if (( ${#orphan_overrides_user[@]} > 0 )); then
    echo
    echo -e "${yellow}Orphaned user overrides:${reset}"
    printf '%s\n' "${orphan_overrides_user[@]}"
    if ! run_command bash -c "rm -f -- $(printf '%q ' "${orphan_overrides_user[@]/#/$HOME/.local/share/flatpak/overrides/}")"; then
      echo
      echo -e "${red}Failed to remove some user overrides, continuing...${reset}"
    else
      echo
      echo -e "${green}Orphaned user overrides removed.${reset}"
    fi
  else
    echo
    echo -e "${cyan}No orphaned user overrides found.${reset}"
  fi
else
  echo
  echo -e "${cyan}No user overrides directory found.${reset}"
fi
echo -e "\n\n\n"
echo -e "${cyan}Checking for orphaned Flatpak overrides (system)...${reset}"
if [[ -d "/var/lib/flatpak/overrides" ]]; then
  mapfile -t orphan_overrides_sys < <(
    sudo find /var/lib/flatpak/overrides -maxdepth 1 -type f -printf '%f\n' 2>/dev/null \
    | while read -r appid; do
        sudo flatpak info "$appid" >/dev/null 2>&1 || echo "$appid"
      done
  )
  if (( ${#orphan_overrides_sys[@]} > 0 )); then
    echo
    echo -e "${yellow}Orphaned system overrides:${reset}"
    printf '%s\n' "${orphan_overrides_sys[@]}"
    if ! run_command bash -c "sudo rm -f -- $(printf '%q ' "${orphan_overrides_sys[@]/#//var/lib/flatpak/overrides/}")"; then
      echo
      echo -e "${red}Failed to remove some system overrides, continuing...${reset}"
    else
      echo
      echo -e "${green}Orphaned system overrides removed.${reset}"
    fi
  else
    echo
    echo -e "${cyan}No orphaned system overrides found.${reset}"
  fi
else
  echo
  echo -e "${cyan}No system overrides directory found.${reset}"
fi
echo -e "\n\n\n"
echo -e "${cyan}Checking Flatpak remotes for unused entries...${reset}"
echo



# Helper function: cleanup_flatpak_remotes.
cleanup_flatpak_remotes() {
local scope="$1"   # "user" or "system"
local list_cmd remote_del_cmd
if [[ "$scope" == "user" ]]; then
list_cmd=(flatpak --user)
remote_del_cmd=(flatpak --user remote-delete --force)
else
list_cmd=(sudo flatpak --system)
remote_del_cmd=(sudo flatpak --system remote-delete --force)
fi
mapfile -t all_remotes < <("${list_cmd[@]}" remote-list --columns=name 2>/dev/null | sort -u)
mapfile -t used_origins < <("${list_cmd[@]}" list --app --columns=origin 2>/dev/null | sort -u)
if (( ${#all_remotes[@]} == 0 )); then
echo -e "${cyan}No ${scope} Flatpak remotes found.${reset}"
return 0
fi
declare -A used=()
for o in "${used_origins[@]}"; do
[[ -n "$o" ]] && used["$o"]=1
done
unused=()
for r in "${all_remotes[@]}"; do
[[ -n "$r" ]] || continue
if [[ -z "${used[$r]:-}" ]]; then
unused+=("$r")
fi
done
if (( ${#unused[@]} == 0 )); then
echo -e "${cyan}No unused ${scope} Flatpak remotes detected.${reset}"
return 0
fi
echo
echo -e "${yellow}Unused ${scope} Flatpak remotes:${reset}"
printf '%s\n' "${unused[@]}"
echo
echo -ne "${yellow}Remove these remotes? (y)es or any other key to skip: ${reset}"
read -r ans
echo
if [[ "${ans,,}" != "y" ]]; then
echo -e "${cyan}Skipping ${scope} remotes cleanup.${reset}"
return 0
fi
for r in "${unused[@]}"; do
echo -e "${cyan}Removing ${scope} remote: ${orange}${r}${reset}"
if ! "${remote_del_cmd[@]}" "$r"; then
echo -e "${red}Failed to remove remote: ${r}${reset}"
fi
done
echo -e "${green}${scope} remotes cleanup done.${reset}"
}
cleanup_flatpak_remotes user
echo
cleanup_flatpak_remotes system
echo -e "\n\n\n"



# Cleaning unwanted Manjaro Gnome extensions
echo -e "${cyan}Checking for unwanted Manjaro Gnome extensions...${reset}"
mapfile -t unwanted_exts < <(find /usr/share/gnome-shell/extensions/ \
  -mindepth 1 -maxdepth 1 -type d \
  ! -iname '*pamac*')
if [[ ${#unwanted_exts[@]} -eq 0 ]]; then
  echo
  echo -e "${cyan}No Manjaro Gnome extensions found.${reset}"
else
  if sudo rm -rf "${unwanted_exts[@]}"; then
    echo
    echo -e "${green}Manjaro Gnome extensions deleted.${reset}"
  else
    echo
    echo -e "${red}Failed to delete Manjaro Gnome extensions, continuing...${reset}"
  fi
fi
echo -e "\n\n\n"



# Cleaning thumbnails, screenshots, downloads, and trash
echo -e "${cyan}Checking thumbnails, screenshots, downloads, and trash...${reset}"
echo
TARGETS=(
  "$HOME/.cache/thumbnails"
  "$HOME/Screenshots"
  "$HOME/Downloads"
)
TRASH_SUBFOLDERS=(files info expunged)
for SUB in "${TRASH_SUBFOLDERS[@]}"; do
    TARGETS+=("$HOME/.local/share/Trash/$SUB")
done
for DIR in "${TARGETS[@]}"; do
    if [ -d "$DIR" ]; then
        if find "$DIR" -mindepth 1 -print -quit 2>/dev/null | read -r _; then
            if find "$DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} + 2>/dev/null; then
                echo -e "${green}Cleaned: $DIR${reset}"
            else
                echo -e "${red}Failed to clean: $DIR${reset}"
            fi
        else
            echo -e "${cyan}Nothing to clean in: $DIR${reset}"
        fi
    else
        echo -e "${yellow}Directory not found: $DIR${reset}"
    fi
done
echo -e "\n\n\n"
echo -e "${cyan}Checking orphaned app configs...${reset}\n"



# Clean Home folder leftovers 
normalize_key() { tr '[:upper:]' '[:lower:]' <<<"$1" | sed 's/[^a-z0-9]//g'; }
EXCLUDE_FILE="$HOME/.orphaned_home_apps.exclude"
touch "$EXCLUDE_FILE"
chmod 600 "$EXCLUDE_FILE"
declare -A EXCLUDED_PATHS=()
while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
  EXCLUDED_PATHS["$line"]=1
done < "$EXCLUDE_FILE"

# Helper function: exclude_path
exclude_path() {
  local p="$1"
  [[ -n "${EXCLUDED_PATHS[$p]:-}" ]] && return 0
  printf '%s\n' "$p" >> "$EXCLUDE_FILE"
  EXCLUDED_PATHS["$p"]=1
}
declare -A INSTALLED_SET=()
while IFS= read -r pkg; do
  k=$(normalize_key "$pkg")
  [[ -n "$k" ]] && INSTALLED_SET["$k"]=1
done < <(pacman -Qq 2>/dev/null || true)
while IFS= read -r appid; do
  [[ -z "$appid" ]] && continue
  k_full=$(normalize_key "$appid")
  k_last=$(normalize_key "${appid##*.}")
  [[ -n "$k_full" ]] && INSTALLED_SET["$k_full"]=1
  [[ -n "$k_last" ]] && INSTALLED_SET["$k_last"]=1
done < <(flatpak list --app --columns=application 2>/dev/null || true)
SCAN_DIRS=("$HOME/.config" "$HOME/.cache" "$HOME/.local/share" "$HOME/.local/state")
KEEP_BASENAMES=("Trash" "dconf" "gtk-3.0" "gtk-4.0" "fontconfig" "pulse" "pipewire")

# Helper function: is_kept_basename.
is_kept_basename() {
  local b="$1"
  for k in "${KEEP_BASENAMES[@]}"; do [[ "$b" == "$k" ]] && return 0; done
  return 1
}
: "${ORPHAN_FUZZY:=1}"

# Helper function: matches_installed.
matches_installed() {
  local base="$1"
  local key
  key=$(normalize_key "$base")
  [[ ${#key} -lt 3 ]] && return 0
  [[ -n "${INSTALLED_SET[$key]:-}" ]] && return 0
  if (( ORPHAN_FUZZY == 1 )); then
    local k
    for k in "${!INSTALLED_SET[@]}"; do
      [[ ${#k} -lt 4 ]] && continue
      [[ "$key" == *"$k"* || "$k" == *"$key"* ]] && return 0
    done
  fi
  return 1
}
CANDIDATES=()
for dir in "${SCAN_DIRS[@]}"; do
  [[ -d "$dir" ]] || continue
  while IFS= read -r -d '' entry; do
    base=${entry##*/}
    is_kept_basename "$base" && continue
    matches_installed "$base" && continue
    entry_real=$(realpath -e -- "$entry" 2>/dev/null || printf '%s' "$entry")
    [[ -n "${EXCLUDED_PATHS[$entry_real]:-}" ]] && continue
    CANDIDATES+=("$entry_real")
  done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null)
done
mkdir -p /tmp/manjaro
outfile=$(mktemp -p /tmp/manjaro orphaned_home_apps.XXXXXX.txt 2>/dev/null || echo "/tmp/manjaro/orphaned_home_apps.txt")
printf "%s\n" "${CANDIDATES[@]}" > "$outfile"
DELETED_ANY=false
if (( ${#CANDIDATES[@]} == 0 )); then
  echo -e "${cyan}No orphaned app configs detected.${reset}"
else
  echo -e "${orange}Probable orphaned app directories found (${#CANDIDATES[@]}).${reset}"
  echo -e "${blue}Saved list:${reset} $outfile"
  echo -e "${blue}Exclude list:${reset} $EXCLUDE_FILE\n"
  for candidate in "${CANDIDATES[@]}"; do
    [[ -d "$candidate" ]] || continue
    cand_real=$(realpath -e -- "$candidate" 2>/dev/null || printf '%s' "$candidate")
    case "$cand_real" in
      "$HOME/.config/"*|"$HOME/.cache/"*|"$HOME/.local/share/"*|"$HOME/.local/state/"*) ;;
      *)
        echo -e "${red}Refusing to touch outside scan roots:${reset} $cand_real\n"
        continue
        ;;
    esac
    echo -e "$cand_real"
    echo -ne "${yellow}(e)xclude forever  (d)elete permanently  (s)kip: ${reset}"
    read -r action
    echo
    case "${action,,}" in
      e|"")
        exclude_path "$cand_real"
        echo -e "${green}Excluded:${reset} $cand_real"
        ;;
      d)
        if rm -rf -- "$cand_real"; then
          echo -e "${green}Deleted:${reset} $cand_real"
          DELETED_ANY=true
        else
          echo -e "${red}Failed to delete:${reset} $cand_real"
        fi
        ;;
      *)
        echo -e "${cyan}Skipped:${reset} $cand_real"
        ;;
    esac
    echo
  done
fi
if $DELETED_ANY; then
  echo -e "${green}Orphaned app configs cleaned.${reset}"
fi



# Clean yay package cache
if ! run_command bash -c "yes | yay -Scc"; then
  echo
  echo -e "${red}Failed to clean package cache with yay -Scc, trying manual cache deletion...${reset}"
  run_command rm -rf "$HOME/.cache/yay/"*
fi



((++current_step)); show_progress $current_step $total_steps
echo -e "\n\n\n\n${purple}$(printf '%*s' 44 '' | tr ' ' '-') .Pacsave .Pacnew handling $(printf '%*s' 44 '' | tr ' ' '-')${reset}"
echo -e "\n\n\n"



# Pacnew Pacsave handling
mapfile -t pac_files < <(
  sudo find / \
    \( -path "/.snapshots" -prune \) -o \
    -regextype posix-extended -regex ".+\.pac(new|save)" -print 2>/dev/null
)
echo -e "${cyan}Checking for .pacnew and .pacsave files...${reset}"
if [ "${#pac_files[@]}" -eq 0 ]; then
  echo
  echo -e "${cyan}No .pacnew or .pacsave found.${reset}"
else
  echo
  echo -e "${red}Found: ${#pac_files[@]} files${reset}"
  printf '%s\n' "${pac_files[@]}"
  echo
  echo -ne "${yellow}Deal with .pacsave/.pacnew? (n)o or any other key: ${reset}"
  read -r choice
  if [[ ! "$choice" =~ ^[Nn]$ ]]; then
    echo
    echo -ne "${yellow}Press Enter to review...${reset}"
    read -r
    echo
    rm -rf ~/meld-temp
    mkdir -p ~/meld-temp
    sudo chown "$USER":"$USER" ~/meld-temp
    chmod 700 ~/meld-temp
    declare -A siblings
    for pac_file in "${pac_files[@]}"; do
      dir=$(dirname "$pac_file")
      base=$(basename "$pac_file")
      base_name="${base%.pacnew}"
      base_name="${base_name%.pacsave}"
      for match in "$dir"/"$base_name"*; do
        [[ "$match" == "$pac_file" ]] && continue
        [[ "$match" == *.pacnew || "$match" == *.pacsave ]] && continue
        if [[ -f "$match" ]]; then
          siblings["$pac_file"]="$match"
          for old_backup in "$match".backup-*; do
            [[ -e "$old_backup" ]] && sudo rm -f "$old_backup"
          done
          backup="${match}.backup-$(date +%Y%m%d-%H%M%S)"
          echo -e "${cyan}Backing up sibling:${reset} $match -> $backup"
          sudo cp -a "$match" "$backup"
          break
        fi
      done
    done
    for pac_file in "${pac_files[@]}"; do
      dest=~/meld-temp"${pac_file}"
      mkdir -p "$(dirname "$dest")"
      sudo cp -a "$pac_file" "$dest"
      sudo chown "$USER":"$USER" "$dest"
      sibling="${siblings[$pac_file]}"
      if [[ -n "$sibling" ]]; then
        sibling_dest=~/meld-temp"${sibling}"
        mkdir -p "$(dirname "$sibling_dest")"
        sudo cp -a "$sibling" "$sibling_dest"
        sudo chown "$USER":"$USER" "$sibling_dest"
      fi
    done
    declare -A processed
    for pac_file in "${pac_files[@]}"; do
      [[ ${processed["$pac_file"]} ]] && continue
      temp_file=~/meld-temp"${pac_file}"
      sibling="${siblings[$pac_file]}"
      sibling_temp=~/meld-temp"${sibling}"
      echo
      echo -e "${cyan}Processing:${reset} $temp_file"
      echo
      if [[ -n "$sibling" && -f "$sibling_temp" ]]; then
        echo -e "${cyan}Launching meld for:$reset\n$temp_file\n$sibling_temp"
        meld "$sibling_temp" "$temp_file"
        processed["$pac_file"]=1
        processed["$sibling"]=1
      else
        echo -e "${cyan}Opening in gnome-text-editor:$reset $temp_file"
        gnome-text-editor "$temp_file" &> /dev/null
        processed["$pac_file"]=1
      fi
      if [[ "$pac_file" == *.pacnew || "$pac_file" == *.pacsave ]]; then
        echo
        echo -ne "${red}Delete $temp_file? (y)es or any other key: ${reset}"
        read -r del
        echo
        if [[ "$del" =~ ^[Yy]$ ]]; then
          rm -v "$temp_file"
        fi
      fi
      echo
      echo -ne "${yellow}Press Enter to continue to next file...${reset}"
      read -r
      echo
    done
    echo -ne "${yellow}Finalize all changes to files? (y)es or any key to continue with the script: ${reset}"
    read -r sync
    echo
    if [[ "${sync,,}" == "y" ]]; then
      for pac_file in "${pac_files[@]}"; do
        original_file="$pac_file"
        temp_file=~/meld-temp"${pac_file}"
        if [[ -f "$temp_file" ]]; then
          if ! cmp -s "$temp_file" "$original_file"; then
            echo -e "${cyan}Copying back: $temp_file → $original_file${reset}"
            sudo cp -a "$temp_file" "$original_file"
          else
            echo -e "${cyan}Unchanged:${reset} $original_file"
          fi
        else
          echo -e "${red}Removing: $original_file${reset}"
          sudo rm -f "$original_file"
        fi
      done
      total_count=0
      updated_count=0
      unchanged_count=0
      for pac_file in "${pac_files[@]}"; do
        sibling="${siblings[$pac_file]}"
        if [[ -n "$sibling" ]]; then
          ((total_count++))
          sibling_temp=~/meld-temp"${sibling}"
          if [[ -f "$sibling_temp" ]]; then
            if ! cmp -s "$sibling_temp" "$sibling"; then
              echo
              echo -e "${cyan}Copying back: $sibling_temp → $sibling${reset}"
              sudo cp -a "$sibling_temp" "$sibling"
              ((updated_count++))
            else
              echo
              echo -e "${yellow}Unchanged:${reset} $sibling"
              ((unchanged_count++))
            fi
          else
            echo
            echo -e "${red}Removing sibling: $sibling${reset}"
            sudo rm -f "$sibling"
          fi
        fi
      done
      if (( total_count > 0 )); then
        echo
        echo -e "${cyan}Config files sync summary:${reset}  ${blue}Total: $total_count${reset}  ${green}Updated: $updated_count${reset}  ${yellow}Unchanged: $unchanged_count${reset}"
      fi
    else
      echo
      echo -e "\n${cyan}Continuing without syncing changes...${reset}"
    fi
    rm -rf ~/meld-temp
    echo -e "\n\n\n"
  else
    echo
    echo -e "${cyan}Skipping .pacnew/.pacsave handling${reset}"
  fi
fi



# Old Backups Cleanup
echo
echo
echo -e "${cyan}Checking for .pacnew, .pacsave, and config backup files older than 30 days...${reset}"
today=$(date +%s)
cutoff_days=30
cutoff_secs=$((cutoff_days * 86400))

# Helper function: find_old_files.
find_old_files() {
  while read -r file; do
    if [[ "$file" =~ \.backup-([0-9]{8})- ]]; then
      file_date="${BASH_REMATCH[1]}"
      file_epoch=$(date -d "${file_date}" +%s 2>/dev/null)
      if (( today - file_epoch > cutoff_secs )); then
        echo "$file"
      fi
    elif [[ "$file" =~ \.(pacnew|pacsave)$ ]]; then
      if [ "$(stat -c %Y "$file")" -lt $((today - cutoff_secs)) ]; then
        echo "$file"
      fi
    fi
  done
}
mapfile -t pac_files < <(
  sudo find / \
    \( -path "/.snapshots" -prune \) -o \
    -type f \( -name "*.pacnew" -o -name "*.pacsave" -o -name "*.backup-[0-9]*" \) -print 2>/dev/null |
  find_old_files
)
if [ "${#pac_files[@]}" -eq 0 ]; then
  echo
  echo -e "${cyan}No files found${reset}"
else
  echo
  echo -e "${red}Found: ${#pac_files[@]} files${reset}"
  printf '%s\n' "${pac_files[@]}"
  echo
  deleted_count=0
  skipped_count=0
  for file in "${pac_files[@]}"; do
    echo -ne "${yellow}Delete $file? (y)es or any other key: ${reset}"
    read -r confirm
    echo
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
      sudo rm -f "$file"
      echo -e "${red}Deleted: $file${reset}"
      ((deleted_count++))
    else
      echo -e "${blue}Skipped: $file${reset}"
      ((skipped_count++))
    fi
  done
  echo -e "\n${cyan}Cleanup summary:${reset}  ${cyan}Total: $((deleted_count + skipped_count))${reset}  ${red}Deleted: $deleted_count${reset}   ${yellow}Skipped: $skipped_count${reset}"
fi



((++current_step)); show_progress $current_step $total_steps
echo -e "\n\n\n\n${purple}$(printf '%*s' 55 '' | tr ' ' '-') End $(printf '%*s' 55 '' | tr ' ' '-')${reset}"
echo -e "\n\n\n"



# Stats after updates
explicit_count2=$(pacman -Qe | wc -l)
read total used avail <<< $(df / --block-size=1 | awk 'NR==2 {print $2, $3, $4}')
percent=$(awk -v u="$used" -v t="$total" 'BEGIN { printf "%.1f", (u/t)*100 }')
used_gb2=$(awk -v u="$used" 'BEGIN { printf "%.1f", u/1e9 }')
explicit_diff=$((explicit_count2 - explicit_count))
used_diff=$(awk -v u1="$used_gb2" -v u2="$used_gb" 'BEGIN { d = u1 - u2; printf "%+.1f", d }')
echo -e "${reset}Disk used: ${used_gb2}GB${reset}  diff: ${orange}${used_diff}${reset}GB"
echo -e "${reset}Programs: ${explicit_count2}${reset}  diff: ${orange}${explicit_diff}${reset}"
echo



# Helper function: list_flatpaks_with_repo_check.
list_flatpaks_with_repo_check() {
    local repo_file="/tmp/manjaro/repo_pkgs.txt"
    if [[ ! -f "$repo_file" ]]; then
        echo -e "${red}Repo package list not found! Run pacman -Sl > $repo_file first.${reset}"
        return 1
    fi
    local repo_file_lower="/tmp/manjaro/repo_pkgs_lower.txt"
    if [[ ! -f "$repo_file_lower" || "$repo_file_lower" -ot "$repo_file" ]]; then
        tr '[:upper:]' '[:lower:]' < "$repo_file" > "$repo_file_lower"
    fi
    mapfile -t flatpaks < <(flatpak list --app --columns=application 2>/dev/null | sort)
    if (( ${#flatpaks[@]} == 0 )); then
        echo -e "${orange}No Flatpaks installed.${reset}"
        return 0
    fi
    echo -e "${cyan}Flatpaks:  ${orange}${#flatpaks[@]}${reset}"
    for app in "${flatpaks[@]}"; do
        local app_base="${app##*.}"
        if grep -qiF "$app_base" "$repo_file_lower"; then
            echo -e "${app} ${orange}   in Manjaro repos${reset}"
        else
            echo "$app"
        fi
    done
    echo
}



# Helper function: list_aur_with_repo_check.
list_aur_with_repo_check() {
    local repo_file="/tmp/manjaro/repo_pkgs.txt"
    if [[ ! -f "$repo_file" ]]; then
        echo -e "${red}Repo package list not found! Run pacman -Sl > $repo_file first.${reset}"
        return 1
    fi
    local repo_file_lower="/tmp/manjaro/repo_pkgs_lower.txt"
    if [[ ! -f "$repo_file_lower" || "$repo_file_lower" -ot "$repo_file" ]]; then
        tr '[:upper:]' '[:lower:]' < "$repo_file" > "$repo_file_lower"
    fi
    local defaultsuffixes=(
        -git -bin -vcs -aur -devel -nightly -wayland -stable -legacy -nox
        -gtk2 -gtk3 -gtk4 -qt4 -qt5 -qt6 -beta -alpha
    )
    local suffixes=("${defaultsuffixes[@]}")
    mapfile -t aurpkgs < <(pacman -Qm | awk '{print $1}' | sort)
    if (( ${#aurpkgs[@]} == 0 )); then
        echo -e "${orange}No AUR packages installed.${reset}"
        return 0
    fi
    echo -e "${cyan}AUR packages:  ${orange}${#aurpkgs[@]}${reset}"
    for pkg in "${aurpkgs[@]}"; do
        local base="$pkg"
        local suf
        for suf in "${suffixes[@]}"; do
            if [[ "$base" == *"$suf" ]]; then
                base="${base%$suf}"
                break
            fi
        done
        if grep -qiF "$base" "$repo_file_lower" || grep -qiF "$pkg" "$repo_file_lower"; then
            echo -e "${pkg} ${orange}   in Manjaro repos${reset}"
        else
            echo "$pkg"
        fi
    done
    echo
}
list_aur_with_repo_check
list_flatpaks_with_repo_check



# Helper function: check_newer_manjaro_lts_kernel.
check_newer_manjaro_lts_kernel() {
  _k_mm() {
    local k="${1#linux}" major minor
    if ((${#k} == 2)); then
      major="${k:0:1}"
      minor="${k:1:1}"
    else
      major="${k:0:${#k}-2}"
      minor="${k: -2}"
    fi
    printf '%d.%d\n' "$((10#$major))" "$((10#$minor))"
  }
  local lts_mm
  if ! lts_mm="$(
    curl -fsSL 'https://www.kernel.org/releases.json' |
    python3 -c 'import json,sys
d=json.load(sys.stdin)
out=set()
for r in d.get("releases",[]):
    if r.get("moniker")=="longterm" and not r.get("iseol",False):
        v=r.get("version","")
        out.add(".".join(v.split(".")[:2]))
print("\n".join(sorted(out, key=lambda s: tuple(map(int,s.split("."))))))
'
  )"; then
    return 0  # stay silent on network/parse errors
  fi
  mapfile -t avail < <(mhwd-kernel -l  | grep -oE 'linux[0-9]+' | sort -u)
  mapfile -t inst  < <(mhwd-kernel -li | grep -oE 'linux[0-9]+' | sort -u)
  local latest_avail_line latest_avail_mm latest_avail_k
  latest_avail_line="$(
    for k in "${avail[@]}"; do
      mm="$(_k_mm "$k")"
      grep -qxF "$mm" <<<"$lts_mm" || continue
      printf '%s %s\n' "$mm" "$k"
    done | sort -V | tail -n1
  )"
  [[ -n "$latest_avail_line" ]] || return 0
  read -r latest_avail_mm latest_avail_k <<<"$latest_avail_line"
  local latest_inst_line latest_inst_mm latest_inst_k
  latest_inst_line="$(
    for k in "${inst[@]}"; do
      mm="$(_k_mm "$k")"
      grep -qxF "$mm" <<<"$lts_mm" || continue
      printf '%s %s\n' "$mm" "$k"
    done | sort -V | tail -n1
  )"
  if [[ -n "$latest_inst_line" ]]; then
    read -r latest_inst_mm latest_inst_k <<<"$latest_inst_line"
  else
    latest_inst_mm=""
    latest_inst_k=""
  fi
  if [[ -z "$latest_inst_mm" ]] || \
     [[ "$(printf '%s\n%s\n' "$latest_inst_mm" "$latest_avail_mm" | sort -V | tail -n1)" != "$latest_inst_mm" ]]; then
    echo -e "${red}Newer LTS kernel series available: ${orange}${latest_avail_k}${reset} (installed LTS: ${latest_inst_k:-none})"
  fi
}
check_newer_manjaro_lts_kernel
 read -r </dev/tty
