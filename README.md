# Total War: SHOGUN 2 — Native Linux Fix Guide

 ## Warning !!!
> Multiplayer will **not** work with this method. This is only for single-player.  
> Also, this isn’t the best way to play SHOGUN 2 on Linux—using Proton is far simpler and more reliable.  
> This was made almost as a "science project" and out of spite!!! (Yeah, SEGA really did us dirty with that native port.)

This guide helps you resurrect the native Linux version of Total War: SHOGUN 2 on modern Ubuntu-based systems (tested on Mint 22.1/22.3, Ubuntu 22.04/24.04). If you value your free time, just enable Proton and walk away happy.

---

## Requirements

- Steam installed from the `.deb` (the Flatpak just adds problems)
- SHOGUN 2 set to the `linux-pre-2022-update` branch  
  (Steam → right-click the game → Properties → Game Versions & Betas → pick that branch)
- Proton/Steam Play must be **off** for this game

---

## Script Method (Recommended)

Fastest way is to let the script do everything for you.

1. Download or clone this repository.
2. Open a terminal in the repo folder and run:
    ```sh
    chmod +x shogun2-native-fix-v2.sh
    ./shogun2-native-fix-v2.sh
    ```
3. The script handles package installs, building libraries, copying everything, and even prints exactly what to put as your Steam launch option.

- If you want to see what happens before anything changes:  
  `./shogun2-native-fix-v2.sh --dry-run`
- Check what’s installed so far:  
  `./shogun2-native-fix-v2.sh --status`
- For troubleshooting:  
  `./shogun2-native-fix-v2.sh --diagnose`

---

## Manual Method

If the script fails or you just dont trust me :( and want to do it yourself

### Install packages and dependencies

```sh
sudo apt update
sudo apt install gcc gcc-multilib make wget perl pkg-config build-essential \
  libgl1-mesa-dri:i386 libgl1:i386 libc6:i386 \
  libopenal1:i386 libnss3:i386 libnspr4:i386 \
  libsdl2-ttf-2.0-0:i386 libgdk-pixbuf-2.0-0:i386 \
  libxss1:i386 libxtst6:i386
```

If you’re on Ubuntu 22.04:
```sh
sudo apt install libgtk2.0-0:i386
```
On Ubuntu 24.04 or Mint 22, because someone needed to rename it:
```sh
sudo apt install libgtk2.0-0t64:i386
```

NVIDIA users **NEED** to do this !!!
```sh
nvidia-smi --query-gpu=driver_version --format=csv,noheader
sudo apt install libnvidia-gl-XXX:i386
```
(Replace `XXX` with your driver version.)

---

### Make directories

```sh
mkdir -p ~/.local/share/shogun2-native-fix/lib32
mkdir -p ~/.local/share/shogun2-native-fix/src
```

---

### Compile kernel compatibility shim

```sh
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

---

### Build OpenSSL 1.0.2u

```sh
cd ~/.local/share/shogun2-native-fix/src
wget -O openssl-1.0.2u.tar.gz https://ftp.nluug.nl/security/openssl/openssl-1.0.2u.tar.gz
tar -xzf openssl-1.0.2u.tar.gz
cd openssl-1.0.2u

./Configure linux-elf shared no-asm \
    --prefix="$HOME/.local/share/shogun2-native-fix/openssl-install" \
    --openssldir="$HOME/.local/share/shogun2-native-fix/openssl-install/ssl" \
    -Wl,-rpath="$HOME/.local/share/shogun2-native-fix/lib32" \
    -Wl,-z,noexecstack

make depend
make -j$(nproc) \
    CFLAG="-Wno-error -fPIC -m32 -DOPENSSL_PIC -DOPENSSL_THREADS -D_REENTRANT -DDSO_DLFCN -DHAVE_DLFCN_H -DL_ENDIAN -O3 -Wall"

cp -P libssl.so* libcrypto.so* ~/.local/share/shogun2-native-fix/lib32/

cd ~/.local/share/shogun2-native-fix/lib32
ln -sf libssl.so.1.0.0 libssl.so.37
ln -sf libcrypto.so.1.0.0 libcrypto.so.36
```

---

### Build libcurl 7.40

```sh
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

### Build libgconf stub

```sh
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

### Copy private_symbol_hack.so

```sh
cp ~/.steam/debian-installation/steamapps/common/"Total War SHOGUN 2"/lib/private_symbol_hack.so \
   ~/.local/share/shogun2-native-fix/lib32/
```
(Make sure the Steam path is correct for your setup.)

---

### Check the result

Quick directory check:
```sh
ls -la ~/.local/share/shogun2-native-fix/lib32/
```
You should see all those `.so` files—if anything is missing, something went wrong

---

### Steam Launch Option

In Steam (right-click game → Properties → Launch Options):

```
SteamAppId=34330 GameAppId=34330 GAME_LAUNCH_PREFIX="env LD_LIBRARY_PATH=/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32:../lib/i686" LD_PRELOAD="/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/private_symbol_hack.so:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libc_mprotect.so:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libcurl.so.4.3.0:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libssl.so.1.0.0:/home/YOUR_USERNAME/.local/share/shogun2-native-fix/lib32/libcrypto.so.1.0.0" %command%
```
Replace `/home/YOUR_USERNAME` with your actual username

---

### Running the game

Start SHOGUN 2 from the Steam library.  
If it crashes, check `~/.steam/debian-installation/logs/console_log.txt` for hints.  
If it still won't launch: maybe just try Proton , i really dont know...

---

### Uninstall

To remove everything:
```sh
rm -rf ~/.local/share/shogun2-native-fix/
```
And clear your Steam Launch Option. No system files will be harmed, just whatever you installed via apt.

---

If SEGA (ever) updates their port to use modern libraries and dependencies, you can ignore all the above. Until then… good luck!
