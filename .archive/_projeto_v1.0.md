A v1.0 pode ser construída com **Debian 13 Trixie + live-build + Debian Installer live + Cage + Chromium**. Isto é adequado ao objetivo: o `live-build` permite automatizar a imagem através de `config/`, e `--debian-installer live` faz o instalador colocar o próprio sistema live no disco. ([live-team.pages.debian.net][1])

Também confirmei que `cage`, `chromium`, `swayidle` e `mpv` existem nos repositórios Debian 13; Cage é especificamente um compositor Wayland para kiosk. ([Debian Packages][2])

### Projeto v1.0

Preparei a estrutura real:

```text
cercifaf-kiosk-v1.0/
├── build.sh
├── test.sh
├── clean.sh
├── README.md
│
├── docs/
│   └── SPEC-v1.0.md
│
├── config/
│   ├── auto/
│   │   └── config
│   ├── package-lists/
│   │   └── cercifaf.list.chroot
│   ├── hooks/
│   │   └── live/
│   └── includes.chroot/
│
└── assets/
```

O `build.sh` trata de:

1. verificar dependências;
2. descarregar o wallpaper;
3. tentar `screensaver.webm`;
4. usar `screensaver.mp4` como fallback;
5. configurar Debian Trixie amd64;
6. instalar Chromium/Cage/Wayland;
7. configurar Plymouth;
8. criar o utilizador kiosk;
9. configurar autologin;
10. configurar os serviços systemd;
11. configurar horário `Europe/Lisbon`;
12. configurar `09:00–17:00`;
13. criar o shutdown das 17:00;
14. desligar automaticamente se arrancar fora do horário;
15. configurar screensaver de 5 minutos;
16. gerar ISO híbrida UEFI/BIOS;
17. gerar SHA256.

### Screensaver

Nesta versão já não é apenas um placeholder.

```text
Chromium
   │
   │ 5 min sem interação
   ▼
swayidle
   │
   ▼
mata Chromium
   │
   ▼
mpv
   │
   └── screensaver.webm
         loop infinito
   │
   │ interação
   ▼
mata mpv
   │
   ▼
Chromium
   │
   ▼
https://cercifaf.org.pt/
```

`swayidle` é próprio para deteção de idle em Wayland. ([Debian Packages][3])

### Horário

Há duas camadas:

```text
UEFI/BIOS RTC
    ↓
liga PC às 09:00
    ↓
Linux
    ↓
kiosk
    ↓
17:00
    ↓
systemd
    ↓
poweroff
```

E ainda:

```text
PC ligado manualmente às 22:00
        ↓
schedule-check
        ↓
fora do horário
        ↓
poweroff
```

A configuração RTC continua dependente do suporte do firmware do computador; o Linux não consegue ligar um PC completamente desligado sem suporte de hardware/firmware.

### Instalação

A ISO será:

```text
cercifaf-kiosk-amd64.iso
```

e pode ser gravada numa pen com Rufus, Balena Etcher ou semelhante:

```text
USB
 ↓
Boot
 ↓
Debian Installer
 ↓
Instalar o sistema
 ↓
SSD
 ↓
Reboot
 ↓
CERCIFAF Kiosk
```

O `live-build` suporta explicitamente `--debian-installer live`, cujo `live-installer` instala o sistema live no disco. ([Manpages Debian][4])

### Download do projeto

[**Download cercifaf-kiosk-v1.0-project.zip**](sandbox:/mnt/data/cercifaf-kiosk-v1.0-project.zip)

### Como gerar a primeira ISO

Num **Debian 13 amd64** dedicado ou numa VM Debian 13:

```bash
unzip cercifaf-kiosk-v1.0-project.zip
cd cercifaf-kiosk-v1.0

sudo apt update

sudo apt install -y \
    live-build \
    debootstrap \
    squashfs-tools \
    xorriso \
    grub-pc-bin \
    grub-efi-amd64-bin \
    mtools \
    dosfstools \
    qemu-system-x86 \
    curl

sudo ./build.sh
```

No final:

```text
output/cercifaf-kiosk-amd64.iso
output/cercifaf-kiosk-amd64.iso.sha256
```

**Há uma condição antes do primeiro build:** o `build.sh` vai validar os teus três recursos no domínio `cercifaf.org.pt`. Se algum deles continuar a devolver `404`, o build para deliberadamente em vez de criar uma ISO incompleta.

A arquitetura está agora suficientemente concreta para passar da especificação para **build → QEMU → teste em hardware real → correções v1.1**.

[1]: https://live-team.pages.debian.net/live-manual/html/live-manual.en.html?utm_source=chatgpt.com "Debian Live Manual"
[2]: https://packages.debian.org/trixie/amd64/x11/cage?utm_source=chatgpt.com "Debian -- Details of package cage in trixie"
[3]: https://packages.debian.org/trixie/swayidle?utm_source=chatgpt.com "Debian -- Details of package swayidle in trixie"
[4]: https://manpages.debian.org/bookworm/live-build/lb_config.1.en.html?utm_source=chatgpt.com "lb_config(1) — live-build — Debian bookworm — Debian Manpages"
