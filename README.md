# Total War: SHOGUN 2 Native Linux Fix Guide

This repository contains two ways to get the native Linux version of Total War: SHOGUN 2 working again on modern Ubuntu-based distributions:

1. **Automatic script method (recommended)** — one command, mostly automated.
2. **Manual method** — step-by-step build instructions for people who want full control.

Tested on:
- Linux Mint 22.1 / 22.3
- Ubuntu 22.04 / 24.04
- Should work on most Ubuntu-based distributions

---

# What this fixes

Modern Linux systems break the old native SHOGUN 2 build for several reasons:

- W^X kernel enforcement (`mprotect` issue)
- Missing old OpenSSL libraries
- Missing old libcurl symbols
- Removed GConf libraries
- glibc 2.34+ `dlopen` compatibility issues

This repository rebuilds/provides the missing compatibility pieces.

---

# What still does NOT work

Because the game depends on OpenSSL 1.0.2:

- Multiplayer: ❌
- Leaderboards: ❌

SEGA servers require modern TLS support that OpenSSL 1.0.2 does not have.

Single-player works correctly.

---

# Requirements

Before using either method:

- Steam must be installed as the native `.deb` version (NOT Flatpak)
- Check with:

```bash
which steam
```

Expected output:

```bash
/usr/games/steam
```

Also:

- SHOGUN 2 must be installed
- In Steam → right click game → Properties → Betas
- Select:

```text
linux-pre-2022-update
```

And:

- Compatibility tab → make sure Proton / Steam Play is DISABLED

---

# Method 1 — Automatic Script (Recommended)

The easiest method.

The script:

- installs required packages
- builds all compatibility libraries
- copies required game files
- prints the correct Steam launch options

---

## Step 1 — Download or clone the repository

```bash
git clone <YOUR_REPO_URL>
cd <YOUR_REPO_NAME>
```

Or simply download the files manually.

---

## Step 2 — Make the script executable

```bash
chmod +x shogun2-native-fix-v2.sh
```

---

## Step 3 — Run the script

```bash
./shogun2-native-fix-v2.sh
```

The script will:

1. Build `libc_mprotect.so`
2. Build OpenSSL 1.0.2
3. Build libcurl 7.40
4. Build a libgconf compatibility stub
5. Install required 32-bit packages
6. Copy `private_symbol_hack.so`
7. Print the exact Steam launch option to paste

---

## Script phases

You can also run specific phases manually.

### Phase 1 — W^X fix

```bash
./shogun2-native-fix-v2.sh --phase 1
```

### Phase 2 — OpenSSL + libcurl + GConf

```bash
./shogun2-native-fix-v2.sh --phase 2
```

### Phase 3 — Dependencies + private_symbol_hack

```bash
./shogun2-native-fix-v2.sh --phase 3
```

### Phase 4 — Print launch options

```bash
./shogun2-native-fix-v2.sh --phase 4
```

---

## Useful script commands

### Show installation status

```bash
./shogun2-native-fix-v2.sh --status
```

### Diagnose launch failures

```bash
./shogun2-native-fix-v2.sh --diagnose
```

### Preview actions without changing anything

```bash
./shogun2-native-fix-v2.sh --dry-run
```

---

## Final Steam setup

After the script finishes:

### In Steam → SHOGUN 2 → Properties

#### Betas

Select:

```text
linux-pre-2022-update
```

#### Compatibility

Make sure:

```text
Force Steam Play compatibility tool
```

is UNCHECKED.

#### Launch Options

Paste the line printed by the script.

---

## Launch the game

- Make sure Steam is running
- Click Play
- The Feral launcher should appear
- Click PLAY

---

# Method 2 — Full Manual Guide

Use this if:

- you want to understand every step
- you don't trust automation
- you want to debug or customize the process

Everything below is the full manual build process.

---

# Step-by-step manual guide

Tested on Linux Mint 22.1/22.3 and Ubuntu 22.04/24.04.

---

## Step 1 — install build tools and 32-bit libraries

```bash
sudo apt install gcc gcc-multilib make wget perl pkg-config build-essential \
  libgl1-mesa-dri:i386 libgl1:i386 libc6:i386 \
  libopenal1:i386 libnss3:i386 libnspr4:i386 \
  libsdl2-ttf-2.0-0:i386 libgdk-pixbuf-2.0-0:i386 \
  libxss1:i386 libxtst6:i386
```

### Ubuntu 22.04

```bash
sudo apt install libgtk2.0-0:i386
```

### Ubuntu 24.04 / Mint 22

```bash
sudo apt install libgtk2.0-0t64:i386
```

### NVIDIA users

Find your driver version:

```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
```

Example:

```text
595.71.05
```

Install the matching 32-bit GL package:

```bash
sudo apt install libnvidia-gl-595:i386
```

---

## Step 2 — create working directories

```bash
mkdir -p ~/.local/share/shogun2-native-fix/lib32
mkdir -p ~/.local/share/shogun2-native-fix/src
```

---

## Step 3 — build libc_mprotect.so

Modern kernels block writable+executable memory.
SHOGUN 2 still expects it.

Create the source:

```bash
cat > ~/.local/share/shogun2-native-fix/src/libc_mprotect.c << 'EOF'
#define _GNU_SOURCE
#include <sys/mman.h>
#include <unistd.h>
#include <sys/syscall.h>
int mprotect(void *addr, size_t len, int prot) {
    if (prot == PROT_EXEC) prot |= PROT_READ;
    return syscall(__NR_mprotect, addr, len, prot);
}
EOF
```

Compile:

```bash
gcc -m32 -shared -fPIC -O2 \
    -o ~/.local/share/shogun2-native-fix/lib32/libc_mprotect.so \
    ~/.local/share/shogun2-native-fix/src/libc_mprotect.c
```

Verify:

```bash
file ~/.local/share/shogun2-native-fix/lib32/libc_mprotect.so
```

Expected:

```text
ELF 32-bit LSB shared object, Intel 80386
```

---

## Step 4 — build OpenSSL 1.0.2u

The game needs old sonames:

- `libssl.so.37`
- `libcrypto.so.36`

These no longer exist on modern Ubuntu.

Download:

```bash
cd ~/.local/share/shogun2-native-fix/src

wget -O openssl-1.0.2u.tar.gz \
    https://ftp.nluug.nl/security/openssl/openssl-1.0.2u.tar.gz
```

Extract:

```bash
tar -xzf openssl-1.0.2u.tar.gz
cd openssl-1.0.2u
```

Configure:

```bash
./Configure linux-elf shared no-asm \
    --prefix="$HOME/.local/share/shogun2-native-fix/openssl-install" \
    --openssldir="$HOME/.local/share/shogun2-native-fix/openssl-install/ssl" \
    -Wl,-rpath="$HOME/.local/share/shogun2-native-fix/lib32" \
    -Wl,-z,noexecstack
```

Build:

```bash
make depend

make -j$(nproc) \
    CFLAG="-Wno-error -fPIC -m32 -DOPENSSL_PIC -DOPENSSL_THREADS -D_REENTRANT -DDSO_DLFCN -DHAVE_DLFCN_H -DL_ENDIAN -O3 -Wall"
```

Copy libraries:

```bash
cp -P libssl.so* libcrypto.so* ~/.local/share/shogun2-native-fix/lib32/
```

Create old soname symlinks:

```bash
cd ~/.local/share/shogun2-native-fix/lib32
ln -sf libssl.so.1.0.0 libssl.so.37
ln -sf libcrypto.so.1.0.0 libcrypto.so.36
```

---

## Step 5 — build libcurl 7.40

```bash
cd ~/.local/share/shogun2-native-fix/src

wget -O curl-7.40.0.tar.gz https://curl.se/download/curl-7.40.0.tar.gz

tar -xzf curl-7.40.0.tar.gz
cd curl-7.40.0
```

Configure:

```bash
OPENSSL_SRC="$HOME/.local/share/shogun2-native-fix/src/openssl-1.0.2u"
LIB32="$HOME/.local/share/shogun2-native-fix/lib32"

CFLAGS="-m32 -I$OPENSSL_SRC/include" \
LDFLAGS="-m32 -L$OPENSSL_SRC -Wl,-rpath=$LIB32" \
LIBS="-ldl" \
./configure \
    --prefix="$HOME/.local/share/shogun2-native-fix/curl-install" \
    --with-ssl="$OPENSSL_SRC" \
    --disable-static \
    --enable-shared \
    --host=i686-pc-linux-gnu
```

Build:

```bash
make -j$(nproc)
```

Copy libraries:

```bash
cp -P lib/.libs/libcurl.so* ~/.local/share/shogun2-native-fix/lib32/
```

---

## Step 6 — build libgconf stub

```bash
cat > ~/.local/share/shogun2-native-fix/src/gconf_stub.c << 'EOF'
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
```

Compile:

```bash
gcc -m32 -shared -fPIC -O2 \
    -o ~/.local/share/shogun2-native-fix/lib32/libgconf-2.so.4 \
    ~/.local/share/shogun2-native-fix/src/gconf_stub.c
```

---

## Step 7 — copy private_symbol_hack.so

```bash
cp ~/.steam/debian-installation/steamapps/common/"Total War SHOGUN 2"/lib/private_symbol_hack.so \
   ~/.local/share/shogun2-native-fix/lib32/
```

Verify:

```bash
file ~/.local/share/shogun2-native-fix/lib32/private_symbol_hack.so
```

Expected:

```text
ELF 32-bit LSB shared object, Intel 80386
```

---

## Step 8 — verify installed files

```bash
ls -la ~/.local/share/shogun2-native-fix/lib32/
```

Expected files:

```text
libc_mprotect.so
libcrypto.so -> libcrypto.so.1.0.0
libcrypto.so.1.0.0
libcrypto.so.36 -> libcrypto.so.1.0.0
libssl.so -> libssl.so.1.0.0
libssl.so.1.0.0
libssl.so.37 -> libssl.so.1.0.0
libcurl.so -> libcurl.so.4.3.0
libcurl.so.4 -> libcurl.so.4.3.0
libcurl.so.4.3.0
libgconf-2.so.4
private_symbol_hack.so
```

---

## Step 9 — Steam launch options

In Steam:

- Right click SHOGUN 2
- Properties
- General
- Launch Options

Paste:

```text
SteamAppId=34330 GameAppId=34330 GAME_LAUNCH_PREFIX="env LD_LIBRARY_PATH=/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32:../lib/i686" LD_PRELOAD="/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/private_symbol_hack.so:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libc_mprotect.so:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libcurl.so.4.3.0:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libssl.so.1.0.0:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libcrypto.so.1.0.0" %command%
```

Or auto-generate the correct line:

```bash
LIB32="$HOME/.local/share/shogun2-native-fix/lib32"

echo "SteamAppId=34330 GameAppId=34330 GAME_LAUNCH_PREFIX=\"env LD_LIBRARY_PATH=${LIB32}:../lib/i686\" LD_PRELOAD=\"${LIB32}/private_symbol_hack.so:${LIB32}/libc_mprotect.so:${LIB32}/libcurl.so.4.3.0:${LIB32}/libssl.so.1.0.0:${LIB32}/libcrypto.so.1.0.0\" %command%"
```

---

## Step 10 — launch

- Start Steam
- Launch the game
- The Feral launcher should appear
- Click PLAY

If the game crashes:

```bash
tail -50 ~/.steam/debian-installation/logs/console_log.txt
```

---

# Uninstall

```bash
rm -rf ~/.local/share/shogun2-native-fix/
```

Then remove the Steam launch option.

No system files are modified beyond installed apt packages.

