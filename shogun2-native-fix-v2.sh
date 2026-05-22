#!/usr/bin/env bash
#
# shogun2-native-fix.sh  —  v2.0  (field-tested edition)
#
# Makes Total War: SHOGUN 2's NATIVE LINUX build run again on modern
# Ubuntu/Mint/Pop!_OS systems (glibc 2.34+, Ubuntu 22.04+).
#
# Tested on: Linux Mint 22.3, Ubuntu 24.04, NVIDIA RTX 4070, Steam native
#
# What this fixes:
#   Phase 1 — Build libc_mprotect.so (W^X kernel enforcement fix)
#   Phase 2 — Build OpenSSL 1.0.2 + libcurl 7.40 + libgconf-2 stub
#   Phase 3 — Install apt dependencies + copy private_symbol_hack.so
#   Phase 4 — Print correct Steam launch options
#
# What still won't work after this fix:
#   Multiplayer / leaderboards — OpenSSL 1.0.2 can't do modern TLS,
#   Sega servers reject it. Single-player works fully.
#
# Requirements:
#   - Steam NATIVE (not Flatpak). Check: which steam → /usr/games/steam
#   - Shogun 2 installed on linux-pre-2022-update beta branch
#
# Everything installs to: ~/.local/share/shogun2-native-fix/
# To uninstall: rm -rf ~/.local/share/shogun2-native-fix/
#               and remove the Steam launch option.

set -euo pipefail

readonly SCRIPT_NAME="$(basename "$0")"
readonly INSTALL_PREFIX="$HOME/.local/share/shogun2-native-fix"
readonly LIB32_DIR="$INSTALL_PREFIX/lib32"
readonly SRC_DIR="$INSTALL_PREFIX/src"
readonly STATE_FILE="$INSTALL_PREFIX/.state"

readonly OPENSSL_VERSION="1.0.2u"
readonly OPENSSL_URL="https://ftp.nluug.nl/security/openssl/openssl-${OPENSSL_VERSION}.tar.gz"
readonly OPENSSL_URL_FALLBACK="https://mirrors.dotsrc.org/openssl/source/old/1.0.2/openssl-${OPENSSL_VERSION}.tar.gz"
readonly OPENSSL_SHA256="ecd0c6ffb493dd06707d38b14bb4d8c2288bb7033735606569d8f90f89669d16"
readonly LIBCURL_VERSION="7.40.0"
readonly LIBCURL_URL="https://curl.se/download/curl-${LIBCURL_VERSION}.tar.gz"
readonly LIBCURL_SHA256="c2e0705a13e53f8f924d1eaeb2ab94f59a9e162007c489b9ab0c96238bddf84b"
readonly STEAM_APPID="34330"

if [[ -t 1 ]]; then
    C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[0;33m'
    C_BLUE=$'\033[0;34m'; C_BOLD=$'\033[1m'; C_RESET=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_BOLD=""; C_RESET=""
fi

DRY_RUN=0
PHASE="all"

info()  { echo "${C_BLUE}[info]${C_RESET} $*"; }
ok()    { echo "${C_GREEN}[ ok ]${C_RESET} $*"; }
warn()  { echo "${C_YELLOW}[warn]${C_RESET} $*" >&2; }
err()   { echo "${C_RED}[err ]${C_RESET} $*" >&2; }
step()  { echo; echo "${C_BOLD}==> $*${C_RESET}"; }
run()   { echo "    ${C_BOLD}\$${C_RESET} $*"; [[ $DRY_RUN -eq 0 ]] && "$@"; }

usage() {
    cat <<EOF
${C_BOLD}${SCRIPT_NAME}${C_RESET} — Shogun 2 native Linux fix v2.0 (field-tested)

Usage: ${SCRIPT_NAME} [--phase N | --all | --status | --diagnose] [--dry-run] [--help]

  --phase 1   Build libc_mprotect.so (W^X fix)
  --phase 2   Build OpenSSL 1.0.2 + libcurl 7.40 + libgconf stub
  --phase 3   Install apt deps + copy private_symbol_hack.so
  --phase 4   Print Steam launch options
  --all       Run all phases (default)
  --diagnose  Show Steam log errors
  --status    Show what's been built
  --dry-run   Preview without doing anything
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --phase)    PHASE="$2"; shift 2 ;;
        --all)      PHASE="all"; shift ;;
        --status)   PHASE="status"; shift ;;
        --diagnose) PHASE="diagnose"; shift ;;
        --dry-run)  DRY_RUN=1; shift ;;
        --help|-h)  usage; exit 0 ;;
        *) err "Unknown: $1"; usage; exit 2 ;;
    esac
done

[[ ${EUID} -eq 0 ]] && { err "Do not run as root."; exit 1; }

mark_done() { mkdir -p "$INSTALL_PREFIX"; grep -q "^phase${1}=done$" "$STATE_FILE" 2>/dev/null || echo "phase${1}=done" >> "$STATE_FILE"; }
is_done()   { grep -q "^phase${1}=done$" "$STATE_FILE" 2>/dev/null; }

show_status() {
    step "Status"
    [[ ! -d "$INSTALL_PREFIX" ]] && { info "Nothing installed."; return; }
    for n in 1 2 3 4; do is_done "$n" && ok "Phase $n: done" || warn "Phase $n: not done"; done
    echo; ls -la "$LIB32_DIR/" 2>/dev/null || info "(lib32 empty)"
}

diagnose() {
    step "Diagnosing launch failure"
    local log=""
    for f in \
        "$HOME/.steam/debian-installation/logs/console_log.txt" \
        "$HOME/.steam/steam/logs/console_log.txt" \
        "$HOME/.local/share/Steam/logs/console_log.txt" \
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam/logs/console_log.txt"
    do [[ -f "$f" ]] && { log="$f"; break; }; done
    [[ -z "$log" ]] && { err "Steam log not found."; exit 1; }
    ok "Log: $log"
    tail -50 "$log" | grep -iE "error|failed|undefined symbol|cannot open|libssl|libcurl|mprotect|GLIBC|signal" --color=always || tail -30 "$log"
}


# PHASE 1

phase1() {
    step "Phase 1: libc_mprotect.so"
    is_done 1 && { info "Already done."; return; }

    if [[ $DRY_RUN -eq 0 ]]; then
        local missing=()
        for cmd in gcc make wget perl; do command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd"); done
        echo 'int main(){return 0;}' | gcc -m32 -x c -o /tmp/.s2t - 2>/dev/null || missing+=("gcc-multilib")
        rm -f /tmp/.s2t
        if [[ ${#missing[@]} -gt 0 ]]; then
            warn "Missing: ${missing[*]}"; read -rp "Install? [Y/n] " a
            [[ "${a,,}" =~ ^n ]] && exit 1
            sudo apt install -y "${missing[@]}" build-essential
        fi
    fi
    ok "Build deps present."

    run mkdir -p "$LIB32_DIR" "$SRC_DIR"

    if [[ $DRY_RUN -eq 0 ]]; then
        cat > "$SRC_DIR/libc_mprotect.c" <<'EOF'
#define _GNU_SOURCE
#include <sys/mman.h>
#include <unistd.h>
#include <sys/syscall.h>
int mprotect(void *addr, size_t len, int prot) {
    if (prot == PROT_EXEC) prot |= PROT_READ;
    return syscall(__NR_mprotect, addr, len, prot);
}
EOF
    fi

    run gcc -m32 -shared -fPIC -O2 -o "$LIB32_DIR/libc_mprotect.so" "$SRC_DIR/libc_mprotect.c"
    mark_done 1; ok "Phase 1 done."
}


# PHASE 2

phase2() {
    step "Phase 2: OpenSSL 1.0.2 + libcurl 7.40 + libgconf stub"
    is_done 2 && { info "Already done."; return; }
    run mkdir -p "$LIB32_DIR" "$SRC_DIR"

    local openssl_src="$SRC_DIR/openssl-${OPENSSL_VERSION}"
    local openssl_tarball="$SRC_DIR/openssl-${OPENSSL_VERSION}.tar.gz"

    if [[ $DRY_RUN -eq 0 ]]; then
        # Verify or download OpenSSL
        _verify() {
            gzip -t "$openssl_tarball" 2>/dev/null || { rm -f "$openssl_tarball"; return 1; }
            local s; s=$(sha256sum "$openssl_tarball" | awk '{print $1}')
            [[ "$s" == "$OPENSSL_SHA256" ]] || { rm -f "$openssl_tarball"; return 1; }
        }
        if [[ -f "$openssl_tarball" ]] && ! _verify; then : ; fi
        if [[ ! -f "$openssl_tarball" ]]; then
            info "Downloading OpenSSL ${OPENSSL_VERSION}..."
            wget -q --show-progress -O "$openssl_tarball" "$OPENSSL_URL" && _verify || {
                warn "Primary failed, trying fallback..."
                rm -f "$openssl_tarball"
                wget -q --show-progress -O "$openssl_tarball" "$OPENSSL_URL_FALLBACK" && _verify || {
                    err "Download failed. Get manually:"; err "  wget -O '$openssl_tarball' '$OPENSSL_URL'"
                    exit 1
                }
            }
            ok "OpenSSL downloaded and verified."
        else
            ok "OpenSSL already present."
        fi

        [[ ! -d "$openssl_src" ]] && { info "Extracting..."; tar -xzf "$openssl_tarball" -C "$SRC_DIR"; }

        info "Building OpenSSL (no-asm, 32-bit, ~5 min)..."
        # IMPORTANT: must use no-asm — GCC modern has duplicate bn_sub_part_words
        # IMPORTANT: use CFLAG= not CFLAGS= on make command line
        # IMPORTANT: all three steps must run in same directory
        pushd "$openssl_src" > /dev/null
        ./Configure linux-elf shared no-asm \
            --prefix="$INSTALL_PREFIX/openssl-install" \
            --openssldir="$INSTALL_PREFIX/openssl-install/ssl" \
            -Wl,-rpath="$LIB32_DIR" -Wl,-z,noexecstack \
            > /tmp/openssl-configure.log 2>&1 \
            || { popd>/dev/null; err "Configure failed. See /tmp/openssl-configure.log"; exit 1; }
        make depend >> /tmp/openssl-configure.log 2>&1 \
            || { popd>/dev/null; err "make depend failed."; exit 1; }
        make -j"$(nproc)" \
            CFLAG="-Wno-error -fPIC -m32 -DOPENSSL_PIC -DOPENSSL_THREADS -D_REENTRANT -DDSO_DLFCN -DHAVE_DLFCN_H -DL_ENDIAN -O3 -Wall" \
            > /tmp/openssl-build.log 2>&1 \
            || { popd>/dev/null; err "Build failed. See /tmp/openssl-build.log"; exit 1; }
        popd > /dev/null
        ok "OpenSSL compiled."

        cp -P "$openssl_src/libssl.so"* "$openssl_src/libcrypto.so"* "$LIB32_DIR/"
        (cd "$LIB32_DIR" && ln -sf libssl.so.1.0.0 libssl.so.37 && ln -sf libcrypto.so.1.0.0 libcrypto.so.36)
        ok "OpenSSL libs + soname aliases in place."
    fi

    # libcurl
    local curl_src="$SRC_DIR/curl-${LIBCURL_VERSION}"
    local curl_tarball="$SRC_DIR/curl-${LIBCURL_VERSION}.tar.gz"
    if [[ $DRY_RUN -eq 0 ]]; then
        # Verify or download libcurl
        _verify_curl() {
            gzip -t "$curl_tarball" 2>/dev/null || { rm -f "$curl_tarball"; return 1; }
            local s; s=$(sha256sum "$curl_tarball" | awk '{print $1}')
            [[ "$s" == "$LIBCURL_SHA256" ]] || { rm -f "$curl_tarball"; return 1; }
        }
        if [[ -f "$curl_tarball" ]] && ! _verify_curl; then : ; fi
        if [[ ! -f "$curl_tarball" ]]; then
            info "Downloading libcurl ${LIBCURL_VERSION}..."
            wget -q --show-progress -O "$curl_tarball" "$LIBCURL_URL" && _verify_curl || {
                err "libcurl download or checksum mismatch. Get manually:"
                err "  wget -O '$curl_tarball' '$LIBCURL_URL'"
                err "  Expected SHA256: $LIBCURL_SHA256"
                exit 1
            }
            ok "libcurl downloaded and verified."
        else
            ok "libcurl already present and verified."
        fi
        [[ ! -d "$curl_src" ]] && { info "Extracting libcurl..."; tar -xzf "$curl_tarball" -C "$SRC_DIR"; }
        info "Building libcurl..."
        pushd "$curl_src" > /dev/null
        CFLAGS="-m32 -I$openssl_src/include" \
        LDFLAGS="-m32 -L$openssl_src -Wl,-rpath=$LIB32_DIR" \
        LIBS="-ldl" \
            ./configure --prefix="$INSTALL_PREFIX/curl-install" \
                --with-ssl="$openssl_src" --disable-static --enable-shared \
                --host=i686-pc-linux-gnu > /tmp/curl-configure.log 2>&1 \
            || { popd>/dev/null; err "curl configure failed."; exit 1; }
        make -j"$(nproc)" > /tmp/curl-build.log 2>&1 \
            || { popd>/dev/null; err "curl build failed."; exit 1; }
        popd > /dev/null
        cp -P "$curl_src/lib/.libs/libcurl.so"* "$LIB32_DIR/"
        ok "libcurl in place."
    fi

    # libgconf-2 stub
    info "Building libgconf-2.so.4 stub..."
    if [[ $DRY_RUN -eq 0 ]]; then
        cat > "$SRC_DIR/gconf_stub.c" <<'EOF'
/* Stub for libgconf-2.so.4 — removed from Ubuntu 22.04+
 * Feral's CEF browser (libcef.so) references these symbols.
 * They are never actually called in normal single-player use. */
#include <stdlib.h>
void gconf_client_get_default(void) {}
void gconf_client_get_bool(void) {}
void gconf_client_get_string(void) {}
void gconf_client_get_int(void) {}
void gconf_client_get_list(void) {}
void gconf_client_get(void) {}
void gconf_client_set_bool(void) {}
void gconf_client_set_string(void) {}
void gconf_client_set_int(void) {}
void gconf_client_add_dir(void) {}
void gconf_client_remove_dir(void) {}
void gconf_client_notify_add(void) {}
void gconf_client_notify_remove(void) {}
void gconf_entry_get_key(void) {}
void gconf_entry_get_value(void) {}
void gconf_entry_free(void) {}
void gconf_value_free(void *val) { free(val); }
void gconf_value_get_bool(void) {}
void gconf_value_get_string(void) {}
void gconf_value_get_int(void) {}
void gconf_init(void) {}
void gconf_error_quark(void) {}
EOF
        gcc -m32 -shared -fPIC -O2 -o "$LIB32_DIR/libgconf-2.so.4" "$SRC_DIR/gconf_stub.c"
        ok "libgconf-2.so.4 stub built."
    fi

    mark_done 2; ok "Phase 2 done."
}


# PHASE 3

phase3() {
    step "Phase 3: apt dependencies + private_symbol_hack.so"
    is_done 3 && { info "Already done."; return; }

    # Find game
    local game_dir=""
    for d in \
        "$HOME/.steam/debian-installation/steamapps/common/Total War SHOGUN 2" \
        "$HOME/.steam/steam/steamapps/common/Total War SHOGUN 2" \
        "$HOME/.local/share/Steam/steamapps/common/Total War SHOGUN 2"
    do [[ -f "$d/Shogun2.sh" ]] && { game_dir="$d"; break; }; done

    if [[ -z "$game_dir" ]]; then
        err "Shogun 2 not found. Install it via Steam on the linux-pre-2022-update beta branch."
        exit 1
    fi
    ok "Game found: $game_dir"

    # apt packages
    local pkgs=(
        libgl1-mesa-dri:i386 libgl1:i386 libc6:i386
        libopenal1:i386 libnss3:i386 libnspr4:i386
        libsdl2-ttf-2.0-0:i386 libgdk-pixbuf-2.0-0:i386
        libxss1:i386 libxtst6:i386
    )
    # GTK2 (name varies)
    if apt-cache show libgtk2.0-0t64:i386 &>/dev/null 2>&1; then
        pkgs+=(libgtk2.0-0t64:i386)
    else
        pkgs+=(libgtk2.0-0:i386)
    fi
    # NVIDIA 32-bit GL
    if command -v nvidia-smi &>/dev/null; then
        local drv; drv=$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | cut -d. -f1)
        if [[ -n "$drv" ]] && apt-cache show "libnvidia-gl-${drv}:i386" &>/dev/null 2>&1; then
            pkgs+=("libnvidia-gl-${drv}:i386")
            info "Adding libnvidia-gl-${drv}:i386 for NVIDIA driver ${drv}."
        fi
    fi

    run sudo apt install -y "${pkgs[@]}"
    ok "apt packages installed."

    # Copy private_symbol_hack.so — it's already in the game but the path
    # "Total War SHOGUN 2" has spaces which break LD_PRELOAD parsing.
    local hack="$game_dir/lib/private_symbol_hack.so"
    if [[ -f "$hack" ]]; then
        run mkdir -p "$LIB32_DIR"
        run cp "$hack" "$LIB32_DIR/private_symbol_hack.so"
        ok "private_symbol_hack.so copied to lib32/."
    else
        warn "private_symbol_hack.so not found — glibc 2.34+ dlopen fix may not work."
    fi

    # Save game_dir for phase 4
    grep -q "^game_dir=" "$STATE_FILE" 2>/dev/null || echo "game_dir=$game_dir" >> "$STATE_FILE"

    mark_done 3; ok "Phase 3 done."
}


# PHASE 4

phase4() {
    step "Phase 4: Steam launch options"

    local preload="${LIB32_DIR}/private_symbol_hack.so"
    preload+=":${LIB32_DIR}/libc_mprotect.so"
    preload+=":${LIB32_DIR}/libcurl.so.4.3.0"
    preload+=":${LIB32_DIR}/libssl.so.1.0.0"
    preload+=":${LIB32_DIR}/libcrypto.so.1.0.0"

    local launch="SteamAppId=${STEAM_APPID} GameAppId=${STEAM_APPID} GAME_LAUNCH_PREFIX=\"env LD_LIBRARY_PATH=${LIB32_DIR}:../lib/i686\" LD_PRELOAD=\"${preload}\" %command%"

    mark_done 4

    cat <<EOF

${C_BOLD}════════════════════════════════════════════════════════════${C_RESET}
${C_GREEN}${C_BOLD}  Done! Follow these steps to launch the game:${C_RESET}
${C_BOLD}════════════════════════════════════════════════════════════${C_RESET}

${C_BOLD}1. Steam must be native (not Flatpak):${C_RESET}
   which steam   →   should show /usr/games/steam

${C_BOLD}2. In Steam → Shogun 2 → Properties:${C_RESET}

   ${C_BOLD}Betas:${C_RESET} select ${C_YELLOW}linux-pre-2022-update${C_RESET} and wait for download

   ${C_BOLD}Compatibility:${C_RESET} ${C_YELLOW}uncheck${C_RESET} "Force Steam Play compatibility tool"

   ${C_BOLD}General → Launch Options:${C_RESET} paste this (one line):

   ${C_YELLOW}${launch}${C_RESET}

${C_BOLD}3. Make sure Steam is open, then launch the game.${C_RESET}
   The Feral options window will appear. Click PLAY.

${C_BOLD}Works:${C_RESET}   Single-player ✓   Achievements ✓
${C_BOLD}Broken:${C_RESET}  Multiplayer ✗   Leaderboards ✗  (TLS 1.3 not supported by OpenSSL 1.0.2)

${C_BOLD}Uninstall:${C_RESET}
   rm -rf "${INSTALL_PREFIX}"
   Remove the launch option from Steam.

${C_BOLD}════════════════════════════════════════════════════════════${C_RESET}
EOF
}


# Dispatcher

case "$PHASE" in
    status)   show_status ;;
    diagnose) diagnose ;;
    1) phase1 ;;
    2) phase2 ;;
    3) phase3 ;;
    4) phase4 ;;
    all) phase1; phase2; phase3; phase4 ;;
    *) err "Unknown phase: $PHASE"; usage; exit 2 ;;
esac
