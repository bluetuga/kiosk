# Plano: Construção ISO CERCIFAF Kiosk no macOS (via Docker)

## Contexto
- **Host:** macOS (Darwin) ARM64 (Apple Silicon), sem Docker, sem Debian
- **Projeto:** Debian 13 Trixie **amd64** kiosk ISO (live-build)
- **Restrição:** `.archive/` ignorado
- **Objetivo:** `build.sh` trata tudo: deteta macOS, usa Docker, gera `output/cercifaf-kiosk-amd64.iso`
- **CRÍTICO:** ARM64 host ≠ amd64 target. Container deve usar `--platform linux/amd64`.

---

## Decisões Resolvidas

| Decisão | Escolha |
|---|---|
| Ambiente de build no Mac | Docker Desktop (`debian:13-slim`) |
| Arquitetura do container | `linux/amd64` (via `--platform linux/amd64`) |
| Fase 1 (assets + config) | No host (macOS) |
| Fase 2 (lb config + lb build) | No container Docker |
| Imagem Docker | `debian:13-slim` (slim + apt install) |
| Script | `build.sh` modificado (detetção de OS) |
| Diretório temporário do contentor | Montagem bind do projecto em `/workspace` |

---

## Gaps Encontrados no `build.sh` Original

1. **Bug mkdir:** Linha 35 não cria `config/includes.chroot/opt/cercifaf`, mas linhas 37-42 fazem `cp` para lá. Corrigir adicionando `mkdir -p`.
2. **Serviços systemd não ativados:** `cercifaf-schedule.timer` e `cercifaf-shutdown.timer` são criados em `etc/systemd/system/` mas nunca são enabled. Criar hook `config/hooks/live/99-enable-timers.hook.chroot` que execute `systemctl enable` para ambos os timers.
3. **Backup desnecessário:** Linha 95 `cp config/auto/config /tmp/cercifaf-auto-config` — remover.
4. **Screensaver não configurado:** `swayidle` está no package list (linha 63) mas não há configuração de idle detection ou lançamento do mpv. Ver `docs/SPEC-v1.0.md` secção "Screensaver". (Marcado como out-of-scope no plano, mas afeta a v1.0.)

---

## Tarefas

### 1. Instalar Docker Desktop no Mac
```bash
brew install --cask docker
open -a Docker
```
Aguardar `docker info` correr sem erro.

### 2. Corrigir bug em `build.sh`
A linha 35 do build.sh atual:
```bash
mkdir -p config/package-lists config/includes.chroot config/hooks/live config/includes.binary output
```
não cria `config/includes.chroot/opt/cercifaf`, mas as linhas 37-42 fazem `cp` para esse diretório. Adicionar `mkdir -p config/includes.chroot/opt/cercifaf` antes dos comandos `cp`.

### 3. Estruturar `build.sh` modificado

O `build.sh` deve:

#### a. Detetar OS
```bash
if [[ "$(uname -s)" == "Darwin" ]]; then
  BUILD_IN_DOCKER=true
else
  BUILD_IN_DOCKER=false
fi
```

#### b. Validações de pré-requisitos
- **macOS (`BUILD_IN_DOCKER=true`):**
  - Verificar `docker` com `command -v docker`
  - Verificar daemon ativo com `docker info`
  - Não exigir `sudo` (Docker no macOS não precisa)
  - Não verificar `lb` (não existe no host)

- **Linux (`BUILD_IN_DOCKER=false`):**
  - Manter: `[[ $EUID -eq 0 ]]`
  - Manter: `command -v lb`

#### c. Fase 1 — Host (igual para ambos os OS)
1. `mkdir -p output assets`
2. Definir função `download()` (curl) — funciona igual no host
3. `rm -f` assets antigos
4. Download do wallpaper → **falha deliberada se 404**
5. Tentar `screensaver.webm` → fallback `screensaver.mp4`
6. `rm -rf config cache chroot binary bootstrap.log build.log`
7. `mkdir -p` com as diretorias incluindo `config/includes.chroot/opt/cercifaf` **(corrigir bug)**
8. `cp assets/*` para `config/includes.chroot/opt/cercifaf/`
9. Gerar `config/package-lists/cercifaf.list.chroot` (mesmo conteúdo)
10. Gerar `config/auto/config` (mesmo conteúdo, `lb config ...`)
11. `chmod +x config/auto/config`
12. **Remover linha desnecessária:** apagar `cp config/auto/config /tmp/cercifaf-auto-config` do build.sh
13. Gerar serviços systemd e scripts na `config/includes.chroot/` (mesmo conteúdo)
14. **Criar hook para ativar timers systemd:** `config/hooks/live/99-enable-timers.hook.chroot` com conteúdo:
    ```bash
    #!/bin/bash
    set -e
    systemctl enable cercifaf-schedule.timer
    systemctl enable cercifaf-shutdown.timer
    ```
15. Validar: `test -f config/includes.chroot/opt/cercifaf/wallpaper.png`

#### d. Fase 2 — Build
- **Linux (nativo):**
  ```bash
  ./config/auto/config
  lb build 2>&1 | tee build.log
  ```
- **macOS (Docker):**
  ```bash
  docker run --rm \
    --name cercifaf-kiosk-build \
    --privileged \
    --platform linux/amd64 \
    -v "${PROJECT_DIR}:/workspace" \
    -w /workspace \
    -e HOST_UID=$(id -u) \
    -e HOST_GID=$(id -g) \
    debian:13-slim \
    bash -c "\
      apt-get update && \
      apt-get install -y --no-install-recommends \
        live-build debootstrap squashfs-tools xorriso \
        grub-pc-bin grub-efi-amd64-bin mtools dosfstools curl && \
      ./config/auto/config && \
      lb build 2>&1 | tee build.log && \
      chown -R ${HOST_UID}:${HOST_GID} /workspace"
  ```
  - O container corre como root (padrão).
  - `--privileged` garante que operações de baixo nível do `debootstrap`/`lb build` funcionem.
  - Variáveis de ambiente `HOST_UID`/`HOST_GID` permitem `chown` final para corrigir propriedade dos arquivos.
  - Tudo escrito no volume (`config/`, `build.log`, ISO) visível no host via mount.

#### e. Pós-build (igual para ambos)
1. Localizar ISO: `find . -maxdepth 1 -type f -name 'cercifaf-kiosk-amd64.iso'`
2. Copiar para `output/cercifaf-kiosk-amd64.iso`
3. Gerar `output/cercifaf-kiosk-amd64.iso.sha256`
4. Imprimir "BUILD OK"

### 4. Atualizar `clean.sh`
- **macOS:** pular `lb clean --purge`; apenas `rm -rf output cache chroot binary config/bootstrap config/build config/chroot`.
- **Linux:** manter `lb clean --purge || true`.

### 5. Atualizar `test.sh` (opcional)
- Instalar QEMU via Homebrew: `brew install qemu`
- Ajustar para usar o QEMU do Homebrew (já está no PATH).

### 6. Atualizar `README.md`
- Adicionar secção "Build no macOS" com os passos abaixo.

---

## Fluxo de Execução no Mac

```
$ brew install --cask docker
$ open -a Docker         # aguardar daemon iniciar
$ ./build.sh              # build.sh deteta macOS, usa Docker (sem sudo)
```

---

## Riscos & Mitigações

| Risco | Mitigação |
|---|---|
| Docker Desktop não ativo | `build.sh` verifica `docker info` e aborta com mensagem |
| Assets retornam 404 | `build.sh` falha deliberadamente (wallpaper); fallback MP4 para screensaver |
| Build demora 60-120 min (devido ao `--platform linux/amd64` no Apple Silicon) | Container)| Container mantém mount ativo; log em `build.log`. Reiniciar laptop durante build aborta. |
| Permissões de ficheiros | Docker Desktop monta volumes com UID do host; `--privileged` + `chown` final garante que arquivos sejam propriedades do usuário host |
| ISO não criada | `build.sh` procura ISO após build; aborta se não existir |

---

## Validação

1. `ls -la output/cercifaf-kiosk-amd64.iso` — ficheiro existe e > 0 bytes
2. `shasum -a 256 output/cercifaf-kiosk-amd64.iso` — coincide com `.sha256`
3. `file output/cercifaf-kiosk-amd64.iso` — mostra "ISO 9660" ou similar

---

## Out of Scope

- Corrigir o screensaver (falta config `swayidle` na v1.0 build.sh)
- `test.sh` no Mac (requer QEMU via Homebrew, tratado como opcional)
- Publicar assets no servidor `cercifaf.org.pt` (prerequisito externo)
