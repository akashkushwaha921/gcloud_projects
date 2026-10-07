#!/bin/bash

# ==========================================================
# Nmap Setup + Authorized Network Scanner
# Use ONLY on systems/networks you own or have permission to scan.
# ==========================================================

set -e

REPORT_DIR="./nmap_reports"
mkdir -p "$REPORT_DIR"

echo "=========================================="
echo "        NMAP SETUP & SCAN TOOL"
echo "=========================================="

# ----------------------------------------------------------
# 1. Check / Install Nmap
# ----------------------------------------------------------

if command -v nmap >/dev/null 2>&1; then
    echo "[+] Nmap is already installed."
else
    echo "[+] Nmap not found. Installing..."

    if command -v apt >/dev/null 2>&1; then
        sudo apt update
        sudo apt install -y nmap

    elif command -v dnf >/dev/null 2>&1; then
        sudo dnf install -y nmap

    elif command -v yum >/dev/null 2>&1; then
        sudo yum install -y nmap

    elif command -v pacman >/dev/null 2>&1; then
        sudo pacman -Sy --noconfirm nmap

    else
        echo "[!] Could not detect a supported package manager."
        echo "Install Nmap manually and run this script again."
        exit 1
    fi
fi

echo
nmap --version | head -n 1
echo

# ----------------------------------------------------------
# 2. Get Target
# ----------------------------------------------------------

read -rp "Enter authorized target IP/CIDR (example: 192.168.1.10 or 192.168.1.0/24): " TARGET

if [[ -z "$TARGET" ]]; then
    echo "[!] Target cannot be empty."
    exit 1
fi

# Basic protection against shell metacharacters
if [[ ! "$TARGET" =~ ^[0-9a-fA-F:./-]+$ ]]; then
    echo "[!] Invalid IP/CIDR format."
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

REPORT="$REPORT_DIR/nmap_report_${TIMESTAMP}.txt"
XML_REPORT="$REPORT_DIR/nmap_report_${TIMESTAMP}.xml"

echo
echo "Target : $TARGET"
echo "Report : $REPORT"
echo

# ----------------------------------------------------------
# 3. Host Discovery
# ----------------------------------------------------------

echo "==========================================" | tee "$REPORT"
echo "NMAP NETWORK SCAN REPORT" | tee -a "$REPORT"
echo "==========================================" | tee -a "$REPORT"
echo "Target: $TARGET" | tee -a "$REPORT"
echo "Date: $(date)" | tee -a "$REPORT"
echo | tee -a "$REPORT"

echo "[1] Host Discovery" | tee -a "$REPORT"
echo "------------------------------------------" | tee -a "$REPORT"

nmap -sn "$TARGET" | tee -a "$REPORT"

# ----------------------------------------------------------
# 4. TCP Port + Service Scan
# ----------------------------------------------------------

echo | tee -a "$REPORT"
echo "[2] TCP Port and Service Detection" | tee -a "$REPORT"
echo "------------------------------------------" | tee -a "$REPORT"

nmap -sV --top-ports 1000 "$TARGET" | tee -a "$REPORT"

# ----------------------------------------------------------
# 5. OS Detection
# ----------------------------------------------------------

echo | tee -a "$REPORT"
echo "[3] OS Detection" | tee -a "$REPORT"
echo "------------------------------------------" | tee -a "$REPORT"

if [[ "$TARGET" != *"/"* ]]; then
    sudo nmap -O "$TARGET" | tee -a "$REPORT"
else
    echo "OS detection skipped for CIDR/network target."
    echo "Run against an individual authorized IP if required." | tee -a "$REPORT"
fi

# ----------------------------------------------------------
# 6. XML Report
# ----------------------------------------------------------

echo
echo "[4] Creating XML report..."

nmap -sV --top-ports 1000 "$TARGET" -oX "$XML_REPORT"

# ----------------------------------------------------------
# 7. Summary
# ----------------------------------------------------------

echo | tee -a "$REPORT"
echo "==========================================" | tee -a "$REPORT"
echo "SCAN COMPLETED" | tee -a "$REPORT"
echo "==========================================" | tee -a "$REPORT"

echo "Text report : $REPORT"
echo "XML report  : $XML_REPORT"

echo
echo "[+] Done."
