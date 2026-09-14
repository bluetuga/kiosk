Sim. Com esses requisitos, faria uma **ISO própria de Kiosk CERCIFAF**, baseada em Debian 13, com instalação por USB e sem desktop tradicional.

A arquitetura fica suficientemente simples para manter e suficientemente robusta para instalar em vários computadores.

## 1. Especificação final

### Hardware alvo

```text
PC x86_64
UEFI
SSD/HDD
Ethernet ou Wi-Fi
Monitor HDMI/DisplayPort
```

Prioridade a UEFI, mas podemos deixar suporte Legacy BIOS se houver computadores antigos.

### Sistema

```text
Debian 13 minimal
        ↓
systemd
        ↓
Wayland
        ↓
Cage
        ↓
Chromium
        ↓
CERCIFAF
```

Debian 13 é atualmente a versão estável disponível. ([Debian][1])

Não instalaria:

* GNOME
* KDE
* XFCE
* NetworkManager completo se não for necessário
* LibreOffice
* aplicações desktop
* login gráfico
* gestor de janelas tradicional

---

# 2. Comportamento do Kiosk

## Arranque

```text
PC liga
   ↓
UEFI
   ↓
GRUB
   ↓
Linux
   ↓
Plymouth
   ↓
Wallpaper CERCIFAF
   ↓
Cage
   ↓
Chromium
   ↓
www.cercifaf.org.pt
```

O website visível será:

**[https://www.cercifaf.org.pt/](https://www.cercifaf.org.pt/)** ([CERCIFAF][2])

O site atual apresenta a informação institucional da CERCIFAF e a área de contacto indica também o horário Seg–Sex 09:00–17:00. ([CERCIFAF][2])

---

# 3. Wallpaper

Configuração:

```yaml
display:
    wallpaper: "https://cercifaf.pt/kiosk/wallpapers/wallpaper.png"
```

Mas há uma alteração importante que recomendo:

**não depender da Internet para o wallpaper.**

Durante a construção da ISO:

```text
https://cercifaf.pt/kiosk/wallpapers/wallpaper.png
                         ↓
              /opt/cercifaf/wallpaper.png
```

A imagem fica incorporada na ISO/sistema instalado.

Assim, mesmo que a Internet esteja temporariamente indisponível:

```text
PC
 ↓
Linux
 ↓
Wallpaper CERCIFAF
```

continua a funcionar.

**Nota:** neste momento os três URLs que forneceste para os recursos devolvem `404` ao serem consultados externamente. 

Portanto, antes da construção final, esses ficheiros terão de estar efetivamente publicados nesses caminhos.

---

# 4. Screensaver

Aqui faria uma solução melhor do que um screensaver tradicional.

Depois de, por exemplo, **5 minutos sem interação**:

```text
Chromium
   ↓
screensaver
   ↓
vídeo CERCIFAF
```

Preferência:

```text
screensaver.webm
```

fallback:

```text
screensaver.mp4
```

Mas, novamente, descarregaria o vídeo durante a construção da ISO:

```text
/opt/cercifaf/screensaver.webm
```

Não faria o kiosk depender de um URL externo para o screensaver.

### Funcionamento

```text
Utilizador navega
      ↓
5 minutos sem teclado/mouse/touch
      ↓
Screensaver
      ↓
vídeo em fullscreen
      ↓
qualquer interação
      ↓
volta a www.cercifaf.org.pt
```

O vídeo deve ficar em loop.

---

# 5. Chromium Kiosk

O Chromium será iniciado automaticamente:

```bash
chromium \
    --kiosk \
    --no-first-run \
    --disable-session-crashed-bubble \
    --disable-infobars \
    --noerrdialogs \
    --disable-features=Translate \
    https://www.cercifaf.org.pt/
```

### O utilizador poderá

* clicar;
* escrever;
* pesquisar;
* abrir links;
* navegar para outros websites;
* usar Back/Forward;
* usar scroll;
* utilizar touchscreen.

### Não poderá

* sair para o desktop;
* abrir aplicações Linux;
* abrir terminal;
* aceder ao gestor de ficheiros;
* fechar o kiosk;
* alterar configurações do sistema.

---

# 6. O que eu NÃO bloquearia

Disseste:

> apenas permitir navegar na net

Portanto não faria um whitelist de websites.

Seria:

```text
www.cercifaf.org.pt
       ↓
Internet
       ↓
qualquer website
```

Isto é importante porque um kiosk com whitelist seria bastante diferente de um simples browser kiosk.

---

# 7. Teclado

Bloquearia combinações perigosas:

```text
Ctrl + Alt + F1
Ctrl + Alt + F2
...
Ctrl + Alt + F6

Alt + Tab
Ctrl + Alt + Del
Super
```

Também impediria o acesso ao shell.

Não bloquearia:

```text
Ctrl+C
Ctrl+V
Ctrl+A
Ctrl+F
Backspace
Setas
PageUp
PageDown
```

porque continuam a ser úteis durante a navegação.

---

# 8. Horário

## Segunda a sexta

```text
09:00 → funcionamento
17:00 → shutdown
```

## Sábado

```text
desligado
```

## Domingo

```text
desligado
```

O shutdown pode ser feito através de um `systemd timer` com `OnCalendar`. O systemd suporta expressões de calendário e sincronização com o relógio antes de executar timers baseados em tempo real. ([Manpages Debian][3])

Exemplo:

```ini
[Timer]
OnCalendar=Mon..Fri 17:00:00
AccuracySec=1s
Persistent=false
```

Eu usaria `Persistent=false`.

Isto evita o comportamento indesejado de ligar o PC e imediatamente executar um shutdown por causa de um evento perdido durante o período em que esteve desligado.

---

# 9. Ligar às 09:00

Aqui há uma diferença fundamental:

**Linux não liga um computador que está fisicamente desligado.**

O arranque das 09:00 deve ser feito pelo:

```text
UEFI / BIOS
        ↓
RTC Wake
```

Configuração:

```text
Monday       09:00
Tuesday      09:00
Wednesday    09:00
Thursday     09:00
Friday       09:00
Saturday     disabled
Sunday       disabled
```

O instalador pode ter uma ferramenta para configurar isto automaticamente **se o firmware/hardware suportar a funcionalidade**.

Caso contrário, a configuração é feita uma vez na BIOS.

---

# 10. Problema importante: relógio

O horário depende do relógio do computador.

Por isso a instalação deve configurar:

```text
Timezone:
Europe/Lisbon
```

e:

```text
NTP:
enabled
```

O sistema deve sincronizar o relógio pela Internet.

Isto é particularmente importante para os `OnCalendar` do systemd. ([Manpages Debian][4])

---

# 11. Comportamento se arrancar fora do horário

Eu colocaria uma proteção adicional.

Exemplo:

```text
Terça 22:00
   ↓
alguém liga manualmente o PC
   ↓
Linux arranca
   ↓
verifica horário
   ↓
fora do horário
   ↓
shutdown
```

Portanto o sistema não fica ligado acidentalmente durante a noite.

A regra:

```text
Seg–Sex 09:00 <= hora < 17:00
    → Kiosk

caso contrário
    → shutdown
```

---

# 12. Recuperação do Chromium

O Chromium deve ser um serviço systemd.

```text
kiosk.service
```

Se o Chromium fechar:

```text
Chromium morreu
       ↓
systemd detecta
       ↓
restart
       ↓
Chromium fullscreen
```

Configuração conceptual:

```ini
[Service]
Restart=always
RestartSec=2
```

Assim, não há situação em que o utilizador fique perante um desktop vazio.

---

# 13. Falha de Internet

O kiosk deve arrancar mesmo sem Internet.

Sequência:

```text
Linux
 ↓
Cage
 ↓
Chromium
 ↓
www.cercifaf.org.pt
 ↓
Internet indisponível
```

O Chromium mostrará a página de erro.

Quando a rede voltar:

```text
Chromium
 ↓
reload
 ↓
CERCIFAF
```

Eu adicionaria também um pequeno watchdog de conectividade para recarregar a página se ficar offline durante muito tempo.

---

# 14. Network

Durante a instalação:

```text
Ethernet
   ↓
DHCP
```

Wi-Fi também deve ser suportado.

Para uma instalação institucional, Ethernet seria preferível.

A configuração não deve exigir IP fixo.

```text
DHCP
 ↓
Router
 ↓
Internet
```

---

# 15. ISO

A ISO deve ser **bootável por USB**.

Fluxo:

```text
kiosk-cercifaf.iso
       ↓
Rufus / Balena Etcher / Ventoy
       ↓
USB
       ↓
Boot PC
```

O Debian Live suporta imagens que combinam um sistema live com o Debian Installer, o que é uma boa base para este tipo de ISO personalizada. ([Live Team][5])

---

# 16. Menu da ISO

Eu faria um menu muito simples:

```text
CERCIFAF KIOSK
────────────────────────

[ 1 ] Instalar Kiosk
[ 2 ] Testar Kiosk
[ 3 ] Reboot
[ 4 ] Shutdown
```

### Instalar

```text
Instalar CERCIFAF Kiosk

Disco:
  /dev/nvme0n1  256 GB

[ INSTALAR ]

AVISO:
O disco será apagado.
```

Depois:

```text
Partition
 ↓
Format
 ↓
Install Debian
 ↓
Install Kiosk
 ↓
Configure boot
 ↓
Configure services
 ↓
Configure RTC
 ↓
Install Chromium
 ↓
Finish
```

---

# 17. Estrutura do sistema instalado

Manteria algo próximo disto:

```text
/opt/cercifaf/
├── config.yaml
├── wallpaper.png
├── screensaver.webm
├── scripts/
│   ├── check-schedule.sh
│   ├── start-kiosk.sh
│   └── screensaver.sh
└── www/
```

Systemd:

```text
/etc/systemd/system/
├── cercifaf-kiosk.service
├── cercifaf-kiosk-restart.service
├── cercifaf-shutdown.service
└── cercifaf-shutdown.timer
```

Config:

```text
/etc/cercifaf/kiosk.yaml
```

---

# 18. Configuração

Eu centralizaria tudo:

```yaml
site:
    url: "https://www.cercifaf.org.pt/"

display:
    wallpaper: "/opt/cercifaf/wallpaper.png"

screensaver:
    enabled: true
    timeout: 300
    video: "/opt/cercifaf/screensaver.webm"
    fallback: "/opt/cercifaf/screensaver.mp4"

schedule:
    timezone: "Europe/Lisbon"
    days:
        - monday
        - tuesday
        - wednesday
        - thursday
        - friday
    start: "09:00"
    end: "17:00"

browser:
    kiosk: true
    restart: true
```

Isto permite alterar posteriormente:

```yaml
timeout: 600
```

para:

```text
10 minutos
```

sem reconstruir a ISO.

---

# 19. Atualizações

Não faria o sistema atualizar automaticamente de forma indiscriminada.

Para um kiosk institucional, prefiro:

```text
Debian security updates
        ↓
automáticas
```

e:

```text
Kiosk software
        ↓
versão controlada
```

A atualização da própria configuração pode posteriormente ser feita por:

```text
https://cercifaf.pt/kiosk/
```

ou por USB.

---

# 20. Modo manutenção

É importante ter uma forma de administração sem estragar o kiosk.

Por exemplo:

```text
Ctrl + Alt + F12
```

**não deve estar acessível ao utilizador normal.**

Podemos criar um mecanismo administrativo baseado numa combinação protegida ou, melhor ainda:

```text
USB de manutenção
        ↓
Boot
        ↓
Maintenance mode
```

Para a primeira versão eu manteria simples:

```text
USB Installer
   ├── Install
   ├── Test
   └── Maintenance
```

---

# 21. Segurança

Como o utilizador poderá navegar livremente, há uma questão importante:

**o kiosk não deve ter dados pessoais persistentes.**

Portanto o perfil Chromium deve ser temporário/limpo.

Ao reiniciar:

```text
cookies
history
cache
downloads
local storage
```

podem ser eliminados.

Assim:

```text
Utilizador A
    ↓
navega
    ↓
sai

Utilizador B
    ↓
novo ambiente limpo
```

Não permitiria downloads persistentes no disco.

---

# 22. Impressão

Não adicionaria inicialmente.

Se posteriormente for necessário:

```text
Chromium
 ↓
CUPS
 ↓
impressora
```

Mas não faz parte do requisito atual.

---

# 23. Logs

Apesar de ser minimalista, deve haver logs.

```text
journalctl
```

com eventos:

```text
Kiosk started
Chromium started
Chromium restarted
Network unavailable
Network restored
Screensaver started
Screensaver stopped
Shutdown scheduled
Shutdown executed
```

Isto será bastante útil quando houver vários kiosks.

---

# 24. Identificação da máquina

Cada instalação deveria ter:

```text
KIOSK-ID: CERCIFAF-001
```

guardado em:

```text
/etc/cercifaf/kiosk-id
```

Por exemplo:

```text
CERCIFAF-SEDE-001
CERCIFAF-SEDE-002
CERCIFAF-CACI-001
```

Não é necessário no MVP, mas vale a pena deixar preparado.

---

# 25. Testes antes da ISO final

Criaria uma matriz de testes:

| Teste                       | Resultado esperado     |
| --------------------------- | ---------------------- |
| Boot normal                 | Wallpaper              |
| Chromium                    | Abre automaticamente   |
| URL                         | `www.cercifaf.org.pt`      |
| Fullscreen                  | Sim                    |
| Internet                    | Navegação normal       |
| Back/Forward                | Funciona               |
| Touchscreen                 | Funciona               |
| Teclado                     | Funciona               |
| Alt+Tab                     | Bloqueado              |
| Ctrl+Alt+F1                 | Bloqueado              |
| Chromium crash              | Reinicia               |
| Internet desligada          | Kiosk continua         |
| Internet volta              | Site recupera          |
| 5 min idle                  | Screensaver            |
| Movimento mouse             | Sai screensaver        |
| 17:00                       | Shutdown               |
| Sábado                      | Não funciona           |
| Domingo                     | Não funciona           |
| Boot manual fora do horário | Shutdown               |
| Reboot                      | Kiosk automático       |
| Power loss                  | Recuperação automática |
| RTC                         | Liga às 09:00          |

---

# 26. Estrutura do projeto para construir a ISO

Eu manteria o projeto pequeno:

```text
cercifaf-kiosk/
│
├── README.md
├── Makefile
├── config/
│   └── kiosk.yaml
│
├── assets/
│   ├── wallpaper.png
│   └── screensaver.webm
│
├── packages/
│   └── packages.list
│
├── overlay/
│   ├── etc/
│   │   ├── systemd/
│   │   │   └── system/
│   │   └── cercifaf/
│   │
│   ├── opt/
│   │   └── cercifaf/
│   │
│   └── usr/
│       └── local/
│           └── bin/
│
├── installer/
│   └── ...
│
├── scripts/
│   ├── build.sh
│   ├── test.sh
│   └── clean.sh
│
└── output/
    └── cercifaf-kiosk-amd64.iso
```

Nada de centenas de ficheiros.

---

# 27. Tecnologia para gerar a ISO

Eu utilizaria **Debian Live tooling/live-build**, em vez de criar um instalador Linux completamente nosso.

```text
live-build
    ↓
Debian base
    ↓
packages
    ↓
filesystem overlay
    ↓
systemd services
    ↓
bootloader
    ↓
ISO
```

Isto mantém a construção reproduzível e baseada nas ferramentas oficiais Debian. O Debian disponibiliza tanto imagens de instalação como documentação para construção/personalização do instalador. ([Debian][1])

---

# 28. Fluxo de desenvolvimento

Eu dividiria em **6 fases**.

### Fase 1 — Base

```text
Debian 13
Chromium
Wayland
Cage
systemd
```

Resultado:

```text
Boot → Chromium → CERCIFAF
```

### Fase 2 — Kiosk

Adicionar:

```text
fullscreen
keyboard restrictions
auto restart
temporary profile
```

### Fase 3 — Visual

Adicionar:

```text
Plymouth
wallpaper
screensaver
```

### Fase 4 — Horário

Adicionar:

```text
09:00 → funcionamento
17:00 → shutdown
weekend → off
outside schedule → shutdown
```

### Fase 5 — ISO

Criar:

```text
cercifaf-kiosk.iso
```

com:

```text
Install
Test
Maintenance
```

### Fase 6 — Validação

Testar em:

```text
PC físico 1
PC físico 2
PC antigo
PC UEFI
PC sem Internet
PC com Ethernet
PC com Wi-Fi
```

---

# 29. Um ponto que mudaria na especificação inicial

Eu **não faria o wallpaper aparecer apenas durante o boot**.

Faria:

```text
Boot
 ↓
Plymouth / wallpaper
 ↓
Cage
 ↓
pequeno período de transição
 ↓
Chromium
```

E, se o Chromium estiver a carregar lentamente:

```text
Wallpaper CERCIFAF
        ↓
"Preparar..."
        ↓
www.cercifaf.org.pt
```

Isso evita mostrar durante vários segundos um ecrã preto ou a interface do sistema.

---

# 30. Especificação final

O produto seria:

> **CERCIFAF Kiosk Linux**

```text
Debian 13
│
├── UEFI boot
├── USB installer
├── Automatic boot
├── CERCIFAF wallpaper
├── Wayland + Cage
├── Chromium kiosk
├── www.cercifaf.org.pt
├── Internet unrestricted
├── Temporary browser profile
├── Auto-restart browser
├── Video screensaver
├── Mouse/touch/keyboard
├── Europe/Lisbon
├── Monday-Friday
│     ├── 09:00 ON
│     └── 17:00 OFF
├── Weekend OFF
├── RTC Wake
├── Automatic shutdown
└── Minimal maintenance system
```

**Uma ressalva imediata:** antes de congelarmos a ISO, é preciso corrigir/publicar os três assets que indicaste, porque os URLs fornecidos neste momento retornam `404`: `wallpaper.png`, `screensaver.webm` e `screensaver.mp4`. 

A partir daqui, o passo lógico é transformar este plano numa **especificação técnica v1.0 + estrutura real do projeto + `build.sh` + configuração `live-build` + serviços systemd**, para conseguirmos efetivamente gerar a primeira `cercifaf-kiosk-amd64.iso`.

[1]: https://www.debian.org/distrib/?utm_source=chatgpt.com "Download Debian"
[2]: https://www.cercifaf.org.pt/?utm_source=chatgpt.com "CERCIFAF"
[3]: https://manpages.debian.org/trixie/systemd/systemd.timer.5.en.html?utm_source=chatgpt.com "systemd.timer(5) — systemd — Debian trixie — Debian Manpages"
[4]: https://manpages.debian.org/bookworm/systemd/systemd.timer.5.en.html?utm_source=chatgpt.com "systemd.timer(5) — systemd — Debian bookworm — Debian Manpages"
[5]: https://live-team.pages.debian.net/live-manual/html/live-manual/customizing-installer.en.html?utm_source=chatgpt.com "customizing-installer - Debian Live Manual"
