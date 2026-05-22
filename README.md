# Step by step guide — everything you need to paste into a terminal

Tested on Linux Mint 22.1/22.3 and Ubuntu 22.04/24.04. Should work on any Ubuntu-based distro.

**Requirements before starting:**
- Steam installed as a native .deb (NOT Flatpak). Check: `which steam` should return `/usr/games/steam`
- Shogun 2 installed and on the `linux-pre-2022-update` beta branch (Steam → right click game → Properties → Betas)
- Compatibility tab: make sure Proton is **disabled**

---

## Step 1 — install build tools and 32-bit libraries

```bash
sudo apt install gcc gcc-multilib make wget perl pkg-config build-essential \
  libgl1-mesa-dri:i386 libgl1:i386 libc6:i386 \
  libopenal1:i386 libnss3:i386 libnspr4:i386 \
  libsdl2-ttf-2.0-0:i386 libgdk-pixbuf-2.0-0:i386 \
  libxss1:i386 libxtst6:i386
```

**If you have Ubuntu 22.04:**
```bash
sudo apt install libgtk2.0-0:i386
```

**If you have Ubuntu 24.04 / Mint 22:**
```bash
sudo apt install libgtk2.0-0t64:i386
```

**If you have an NVIDIA GPU** — find your driver version and install the 32-bit GL library:
```bash
nvidia-smi --query-gpu=driver_version --format=csv,noheader
# example output: 595.71.05
# use the first number (595 in this case):
sudo apt install libnvidia-gl-595:i386
```

---

## Step 2 — create the working directory

```bash
mkdir -p ~/.local/share/shogun2-native-fix/lib32
mkdir -p ~/.local/share/shogun2-native-fix/src
```

---

## Step 3 — build libc_mprotect.so

Modern kernels don't let programs have memory that's both writable and executable at the same time. Shogun 2 needs that. This shim intercepts the call and makes it work.

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

gcc -m32 -shared -fPIC -O2 \
    -o ~/.local/share/shogun2-native-fix/lib32/libc_mprotect.so \
    ~/.local/share/shogun2-native-fix/src/libc_mprotect.c
```

Check it worked:
```bash
file ~/.local/share/shogun2-native-fix/lib32/libc_mprotect.so
# should say: ELF 32-bit LSB shared object, Intel 80386
```

---

## Step 4 — build OpenSSL 1.0.2u (32-bit)

The game needs `libssl.so.37` and `libcrypto.so.36` — old Ubuntu 12.04 era sonames that don't exist anymore. We compile the old OpenSSL ourselves.

This takes about 5-8 minutes.

```bash
cd ~/.local/share/shogun2-native-fix/src

wget -O openssl-1.0.2u.tar.gz \
    https://ftp.nluug.nl/security/openssl/openssl-1.0.2u.tar.gz

tar -xzf openssl-1.0.2u.tar.gz
cd openssl-1.0.2u
```

Configure it (the `no-asm` flag is important — without it you get a link error on modern GCC):
```bash
./Configure linux-elf shared no-asm \
    --prefix="$HOME/.local/share/shogun2-native-fix/openssl-install" \
    --openssldir="$HOME/.local/share/shogun2-native-fix/openssl-install/ssl" \
    -Wl,-rpath="$HOME/.local/share/shogun2-native-fix/lib32" \
    -Wl,-z,noexecstack
```

Build it (use `CFLAG=` not `CFLAGS=` — this matters, they're different things in OpenSSL 1.0.2):
```bash
make depend

make -j$(nproc) \
    CFLAG="-Wno-error -fPIC -m32 -DOPENSSL_PIC -DOPENSSL_THREADS -D_REENTRANT -DDSO_DLFCN -DHAVE_DLFCN_H -DL_ENDIAN -O3 -Wall"
```

Copy the libraries and create the old soname symlinks:
```bash
cp -P libssl.so* libcrypto.so* ~/.local/share/shogun2-native-fix/lib32/

cd ~/.local/share/shogun2-native-fix/lib32
ln -sf libssl.so.1.0.0 libssl.so.37
ln -sf libcrypto.so.1.0.0 libcrypto.so.36
```

Check:
```bash
ls -la ~/.local/share/shogun2-native-fix/lib32/libssl* ~/.local/share/shogun2-native-fix/lib32/libcrypto*
# should see libssl.so.1.0.0, libssl.so.37 -> libssl.so.1.0.0, etc.
```

---

## Step 5 — build libcurl 7.40

The steam runtime ships an old libcurl that's missing the `CURL_OPENSSL_4` symbol the game needs. We compile our own linked against the OpenSSL we just built.

```bash
cd ~/.local/share/shogun2-native-fix/src

wget -O curl-7.40.0.tar.gz https://curl.se/download/curl-7.40.0.tar.gz
tar -xzf curl-7.40.0.tar.gz
cd curl-7.40.0

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

make -j$(nproc)

cp -P lib/.libs/libcurl.so* ~/.local/share/shogun2-native-fix/lib32/
```

---

## Step 6 — build libgconf stub

GConf was removed from Ubuntu 22.04+. The Feral in-game browser references it. These stubs are empty — they just stop the game from refusing to load.

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

gcc -m32 -shared -fPIC -O2 \
    -o ~/.local/share/shogun2-native-fix/lib32/libgconf-2.so.4 \
    ~/.local/share/shogun2-native-fix/src/gconf_stub.c
```

---

## Step 7 — copy private_symbol_hack.so from the game

Feral already includes a fix for the glibc 2.34+ `dlopen` issue in the game files. We just need to copy it somewhere without spaces in the path (because "Total War SHOGUN 2" has spaces that break LD_PRELOAD).

```bash
cp ~/.steam/debian-installation/steamapps/common/"Total War SHOGUN 2"/lib/private_symbol_hack.so \
   ~/.local/share/shogun2-native-fix/lib32/
```

Check:
```bash
file ~/.local/share/shogun2-native-fix/lib32/private_symbol_hack.so
# should say: ELF 32-bit LSB shared object, Intel 80386
```

---

## Step 8 — verify everything is in place

```bash
ls -la ~/.local/share/shogun2-native-fix/lib32/
```

You should see these files:
```
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

## Step 9 — Steam launch option

In Steam, right-click Shogun 2 → Properties → General → Launch Options.

Paste this (it's one long line — replace `YOUR_USERNAME` with your actual username):

```
SteamAppId=34330 GameAppId=34330 GAME_LAUNCH_PREFIX="env LD_LIBRARY_PATH=/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32:../lib/i686" LD_PRELOAD="/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/private_symbol_hack.so:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libc_mprotect.so:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libcurl.so.4.3.0:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libssl.so.1.0.0:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libcrypto.so.1.0.0" %command%
```

Or run this to generate the exact line with your username filled in automatically:

```bash
LIB32="$HOME/.local/share/shogun2-native-fix/lib32"
echo "SteamAppId=34330 GameAppId=34330 GAME_LAUNCH_PREFIX=\"env LD_LIBRARY_PATH=${LIB32}:../lib/i686\" LD_PRELOAD=\"${LIB32}/private_symbol_hack.so:${LIB32}/libc_mprotect.so:${LIB32}/libcurl.so.4.3.0:${LIB32}/libssl.so.1.0.0:${LIB32}/libcrypto.so.1.0.0\" %command%"
```

Copy-paste whatever it prints directly into Steam.

---

## Step 10 — launch

Make sure Steam is open and logged in, then hit Play in Steam.

The Feral options window should appear. Click PLAY.

If it crashes, check the Steam log:
```bash
tail -50 ~/.steam/debian-installation/logs/console_log.txt
```

---

## To uninstall

```bash
rm -rf ~/.local/share/shogun2-native-fix/
```

Then remove the launch option from Steam. Nothing else was touched.
