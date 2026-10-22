#!/usr/bin/env bash
# recon_nmap.sh
# Simple interactive wrapper around nmap for authorized vulnerability discovery
# Usage: chmod +x recon_nmap.sh && ./recon_nmap.sh
#
# Requirements: Nmap, Nikto(Optional), curl, zip.
#
# Author:Fawwaz Ayomide Akinsanya
# Linkedin: https://www.linkedin.com/in/ayomide-akinsanya-1a080743a
# X(Formerly Twitter): Castemper_szn
#
# An Entry level Cybesecurity project designed for Beginner Cybersecurity Analysts to learn and master the sue of Nmap and system vulbnerabilities.)


set -euo pipefail
IFS=$'\n\t'

# --- Helper functions -------------------------------------------------------
timestamp() { date +"%Y%m%d-%H%M%S"; }

check_requirements() {
  if ! command -v nmap >/dev/null 2>&1; then
    echo "ERROR: nmap is required but not found. Install nmap and re-run."
    exit 2
  fi
}

safe_confirm() {
  # Make user explicitly confirm they have permission to scan the target.
  echo
  echo ">>> LEGAL WARNING: Only scan targets you own or have explicit permission to test."
  read -rp "Type 'I HAVE PERMISSION' to continue or anything else to abort: " confirm
  if [[ $confirm != "I HAVE PERMISSION" ]]; then
    echo "Aborting. Permission not confirmed."
    exit 3
  fi
}

mk_report_dir() {
  dir="reports/$(date +%Y-%m-%d)"
  mkdir -p "$dir"
  echo "$dir"
}

sanitize_target() {
  # Basic sanitization: trim whitespace
  local t
  t="$(echo "$1" | xargs)"
  echo "$t"
}

print_profiles() {
  cat <<'PROFILES'
Choose a scan profile:
  1) quick     - default NSE scripts + version detection (fast)
  2) vuln-deep - full port scan + vuln scripts (slower, thorough)
  3) full-port - comprehensive TCP port scan (all ports)
  4) web-only  - http/https focused checks (nikto if installed)
  5) custom    - enter custom nmap flags
PROFILES
}

run_nmap_quick() {
  local target="$1" outpref="$2"
  echo "[*] Running quick scan (default scripts + service/version detection)..."
  nmap -sC -sV -oA "$outpref-quick" "$target"
}

run_nmap_vuln_deep() {
  local target="$1" outpref="$2"
  echo "[*] Running vuln-deep (all ports, aggressive, NSE vuln scripts)... (may take long)"
  nmap -p- -sS -T4 -A --script "vuln,auth,default" -oA "$outpref-vulndeep" "$target"
}

run_nmap_fullport() {
  local target="$1" outpref="$2"
  echo "[*] Running full-port TCP SYN scan (all 65535 ports)..."
  nmap -p- -sS -T4 -oA "$outpref-fullport" "$target"
}

run_nmap_web() {
  local target="$1" outpref="$2"
  echo "[*] Running web-focused nmap scripts..."
  nmap -p 80,443,8080,8443 -sV --script "http-enum,http-vhosts,http-title,http-server-header,http-methods,http-headers,vuln" -oA "$outpref-web" "$target"
}

run_nikto_if_available() {
  local target="$1" outdir="$2"
  if command -v nikto >/dev/null 2>&1; then
    echo "[*] Running nikto (web vulnerability scanner) against $target ..."
    # nikto accepts a URL; try both http and https if host only given
    nikto -host "$target" -output "$outdir/nikto-$target-$(timestamp).txt" || true
  else
    echo "[*] nikto not installed. Skipping nikto scan."
  fi
}

curl_headers() {
  local target="$1" outdir="$2"
  if command -v curl >/dev/null 2>&1; then
    echo "[*] Fetching HTTP headers for $target ..."
    curl -I --max-time 15 "http://$target" > "$outdir/curl-http-$target-$(timestamp).txt" 2>/dev/null || true
    curl -I --max-time 15 "https://$target" > "$outdir/curl-https-$target-$(timestamp).txt" 2>/dev/null || true
  fi
}

summarize_findings() {
  local outdir="$1" summaryfile="$2"
  echo "[*] Generating quick summary..."
  # Grep for keywords in nmap greppable or xml text
  {
    echo "SUMMARY for reports in $outdir"
    echo "Generated at: $(date -u)"
    echo "--------------------------------------------------"
    echo
    echo "---- Nmap Vulnerable / CVE / VULNERABLE lines ----"
    grep -iE "vuln|vulnerab|cve|exploit|critical|high|CVSS" "$outdir"/*.{gnmap,nmap,xml,txt} 2>/dev/null || true
    echo
    echo "---- HTTP titles / server headers (if present) ----"
    grep -iE "Server:|Title:|X-Powered-By|Set-Cookie" "$outdir"/* 2>/dev/null | head -n 200 || true
  } > "$summaryfile"
  echo "[*] Summary saved to $summaryfile"
}

package_report() {
  local outdir="$1"
  if command -v zip >/dev/null 2>&1; then
    zip -r "$outdir.zip" "$outdir" >/dev/null 2>&1 || true
    echo "[*] Packaged report: $outdir.zip"
  else
    echo "[*] zip not installed; report directory remains at $outdir"
  fi
}

# --- Main ------------------------------------------------------------------
main() {
  check_requirements

  echo " Simple Nmap Wrapper for Authorized Scanning "
  read -rp "Enter target (IP or hostname): " raw_target
  target="$(sanitize_target "$raw_target")"
  if [[ -z "$target" ]]; then
    echo "No target given. Exiting."
    exit 1
  fi

  safe_confirm

  echo
  print_profiles
  read -rp "Select profile [1-5] (default 1): " profile
  profile="${profile:-1}"

  report_dir="$(mk_report_dir)"
  ts="$(timestamp)"
  # create a sanitized filename prefix
  safe_name="$(echo "$target" | sed -E 's/[:\/]/_/g')"
  outpref="$report_dir/${safe_name}-$ts"

  # run the selected scans
  case "$profile" in
    1)
      run_nmap_quick "$target" "$outpref"
      ;;
    2)
      run_nmap_vuln_deep "$target" "$outpref"
      ;;
    3)
      run_nmap_fullport "$target" "$outpref"
      ;;
    4)
      run_nmap_web "$target" "$outpref"
      run_nikto_if_available "$target" "$report_dir"
      ;;
    5)
      read -rp "Enter custom nmap flags (e.g. -p80,443 -sV --script vuln): " custom_flags
      echo "[*] Running: nmap $custom_flags -oA \"$outpref-custom\" $target"
      # shellcheck disable=SC2086
      nmap $custom_flags -oA "$outpref-custom" "$target"
      ;;
    *)
      echo "Invalid selection. Running quick scan by default."
      run_nmap_quick "$target" "$outpref"
      ;;
  esac

  # Always try some basic helpers
  run_nmap_web "$target" "$outpref" || true
  run_nikto_if_available "$target" "$report_dir" || true
  curl_headers "$target" "$report_dir" || true

  # produce a one-file summary
  summary_file="$report_dir/${safe_name}-${ts}-SUMMARY.txt"
  summarize_findings "$report_dir" "$summary_file"

  package_report "$report_dir"

  echo
  echo "Done. Reports are in: $report_dir"
  echo "Open the summary: $summary_file"
  echo "Remember: only share results with authorized parties."
}

main "$@"



