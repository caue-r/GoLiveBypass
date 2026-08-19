#!/usr/bin/env bash
#
# GoLiveBypass - instalador automatico (Linux)
#
# Encontra sozinho o Equicord ou o Vencord que voce ja tem e reaproveita. Se nao achar
# nenhum, instala o Equicord automaticamente. Em qualquer caso, instala o plugin, compila
# e injeta sem perguntar nada.
#
# Uso:
#   ./golivebypass-installer.sh
#   ./golivebypass-installer.sh --source ~/Equicord
#   ./golivebypass-installer.sh --plugin-source ~/GoLiveBypass/goLiveBypass
#   ./golivebypass-installer.sh --install --yes
#   ./golivebypass-installer.sh --uninstall
#
# Obrigado ao Vithor (https://github.com/Vith0r), que escreveu o primeiro instalador do
# GoLiveBypass e abriu o caminho para este aqui.

set -euo pipefail

# Sem isso, a primeira vez que o corepack baixa uma versao do pnpm ele pergunta "Do you want
# to continue? [Y/n]". Sem alguem para responder (por exemplo rodando via curl | bash), o
# script trava ali.
export COREPACK_ENABLE_DOWNLOAD_PROMPT=0

REPO_RAW="https://raw.githubusercontent.com/caue-r/GoLiveBypass/main"
PLUGIN_FILES=("goLiveBypass/index.tsx" "goLiveBypass/native.ts")
PLUGIN_DIR_NAME="goLiveBypass"
EQUICORD_GIT="https://github.com/Equicord/Equicord"

MODE="menu"
SOURCE=""
# Instala o plugin de uma pasta local em vez de baixar do GitHub, para testar uma mudanca
# antes de publicar. Sem isto o instalador sempre traz o que esta no repositorio, e um teste
# feito assim mede a versao errada sem avisar.
PLUGIN_SOURCE=""
ASSUME_YES=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [ -t 1 ]; then
    C_DIM=$'\033[2m'; C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_RED=$'\033[31m'
    C_CYAN=$'\033[36m'; C_BOLD=$'\033[1m'; C_OFF=$'\033[0m'
else
    C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""; C_BOLD=""; C_OFF=""
fi

# Sempre em stderr: estas funcoes sao chamadas de dentro de $(...) e qualquer coisa que
# fosse para stdout seria capturada como se fosse o valor de retorno.
step() { printf '  %s[*] %s%s\n' "$C_DIM" "$1" "$C_OFF" >&2; }
ok()   { printf '  %s[OK] %s%s\n' "$C_GREEN" "$1" "$C_OFF" >&2; }
warn() { printf '  %s[!] %s%s\n' "$C_YELLOW" "$1" "$C_OFF" >&2; }
fail() { printf '\n  %s[X] %s%s\n\n' "$C_RED" "$1" "$C_OFF" >&2; exit 1; }

banner() {
    printf '\n  %sGoLiveBypass%s\n' "$C_CYAN$C_BOLD" "$C_OFF"
    printf '  %sGo Live e camera de volta no Discord%s\n' "$C_DIM" "$C_OFF"
    printf '  %shttps://github.com/bezumiya/GoLiveBypass%s\n\n' "$C_DIM" "$C_OFF"
}

confirm() {
    [ "$ASSUME_YES" -eq 1 ] && return 0
    local answer
    read -r -p "  $1 [s/N] " answer
    [[ "$answer" =~ ^[sSyY] ]]
}

have() { command -v "$1" >/dev/null 2>&1; }

# O endereco da proxy pode carregar usuario e senha, e ele e mostrado na tela. A senha some.
hide_proxy_secret() {
    printf '%s\n' "$1" | sed -E 's#^([a-z0-9]+)://([^:@/]+)(:[^@/]*)?@#\1://\2:***@#'
    return 0
}

# O corepack cria o atalho do pnpm antes de saber que versao usar. Na primeira execucao ele
# busca essa versao no registro do npm e confere a assinatura com chaves embutidas nele; as
# chaves do corepack que vem no Node 22 estao velhas, entao o atalho existe e mesmo assim
# quebra com "Cannot find matching keyid". So testar se o comando existe nao prova nada.
have_pnpm() { have pnpm && pnpm --version >/dev/null 2>&1; }

usage() {
    sed -n '3,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    exit 0
}

while [ $# -gt 0 ]; do
    case "$1" in
        --install) MODE="install" ;;
        --uninstall) MODE="uninstall" ;;
        --source) SOURCE="${2:-}"; shift ;;
        --plugin-source) PLUGIN_SOURCE="${2:-}"; shift ;;
        --yes|-y) ASSUME_YES=1 ;;
        --help|-h) usage ;;
        *) fail "Opcao desconhecida: $1" ;;
    esac
    shift
done

# ----------------------------------------------------------------------------- descoberta

is_checkout() {
    [ -n "${1:-}" ] || return 1
    [ -f "$1/package.json" ] || return 1
    [ -f "$1/src/utils/types.ts" ]
}

# Procura o app.asar de verdade em vez de confiar numa lista de caminhos.
#
# Desde a versao 1.0.136, de maio de 2026, o pacote de Linux do Discord (tar.gz, .deb, o
# oficial do Arch e o RPM) traz SO um bootstrap: o app de verdade, com o app.asar, e baixado na
# primeira execucao para dentro do HOME. Quem so olha /usr/share e /opt nao acha Discord nenhum
# numa instalacao atual.
discord_resources() {
    local raiz sub base

    base="${XDG_CONFIG_HOME:-$HOME/.config}"
    for sub in \
        "$base"/discord/app-*/resources \
        "$base"/discordptb/app-*/resources \
        "$base"/discordcanary/app-*/resources
    do
        if [ -e "$sub/app.asar" ] || [ -e "$sub/_app.asar" ]; then
            printf '%s\n' "$sub"
        fi
    done

    # Pacotes que ainda embutem o app: discord_arch_electron e os AUR de PTB e Canary.
    for raiz in \
        /usr/share/discord /usr/share/discord-ptb /usr/share/discord-canary \
        /usr/lib/discord /usr/lib/discord-ptb /usr/lib/discord-canary /usr/lib64/discord \
        /opt/discord /opt/Discord /opt/discord-ptb /opt/discord-canary \
        /usr/local/share/discord \
        "$HOME/.local/share/discord" "$HOME/Discord" "$HOME/discord" \
        "$HOME/.local/share/DiscordPTB" "$HOME/.local/share/DiscordCanary"
    do
        [ -d "$raiz" ] || continue
        for sub in "$raiz/resources" "$raiz"; do
            if [ -e "$sub/app.asar" ] || [ -e "$sub/_app.asar" ]; then
                printf '%s\n' "$sub"
                break
            fi
        done
    done
    return 0
}

# O instalador do Equicord e o do Vencord trocam o app.asar por um stub cujo index.js so faz
# require da pasta de build. Numa instalacao a partir do fonte esse require aponta direto para
# <checkout>/dist/desktop, que e a forma mais confiavel de achar o checkout.
injected_path() {
    local resources="$1" file text
    for file in "$resources/app/index.js" "$resources/app.asar"; do
        [ -f "$file" ] || continue
        [ "$(stat -c%s "$file" 2>/dev/null || echo 0)" -lt 65536 ] || continue
        text="$(tr -d '\0' < "$file" 2>/dev/null || true)"
        if [[ "$text" =~ require\(\"([^\"]+)\"\) ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
            return 0
        fi
    done
    return 1
}

installed_mod() {
    local resources path
    while IFS= read -r resources; do
        path="$(injected_path "$resources" || true)"
        [ -n "$path" ] || continue
        case "${path,,}" in
            *equibop*) echo "Equibop"; return 0 ;;
            *equicord*) echo "Equicord"; return 0 ;;
            *vesktop*) echo "Vesktop"; return 0 ;;
            *vencord*) echo "Vencord"; return 0 ;;
        esac
    done < <(discord_resources)
    return 1
}

checkout_from_injection() {
    local resources path root
    while IFS= read -r resources; do
        path="$(injected_path "$resources" || true)"
        [ -n "$path" ] || continue
        root="$(dirname "$(dirname "$path")")"   # <checkout>/dist/desktop -> <checkout>
        if is_checkout "$root"; then printf '%s\n' "$root"; return 0; fi
    done < <(discord_resources)
    return 1
}

checkout_on_disk() {
    local root name candidate
    for root in "$HOME" "$HOME/Documents" "$HOME/Desktop" "$HOME/Downloads" \
                "$HOME/dev" "$HOME/git" "$HOME/repos" "$HOME/projects" "$HOME/src" \
                "$HOME/.local/share"
    do
        [ -d "$root" ] || continue
        for name in Equicord equicord Vencord vencord; do
            candidate="$root/$name"
            if is_checkout "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
        done
    done

    step "Procurando um pouco mais fundo em $HOME"
    while IFS= read -r candidate; do
        if is_checkout "$candidate"; then printf '%s\n' "$candidate"; return 0; fi
    done < <(find "$HOME" -maxdepth 4 -type d \( -iname Equicord -o -iname Vencord \) 2>/dev/null | head -n 20)

    return 1
}

find_checkout() {
    local root
    if [ -n "$SOURCE" ]; then
        is_checkout "$SOURCE" || fail "Nao encontrei um checkout do Equicord ou Vencord em $SOURCE"
        printf '%s\n' "$SOURCE"; return 0
    fi

    if root="$(checkout_from_injection)"; then
        ok "Achei pelo Discord: $root"
        printf '%s\n' "$root"; return 0
    fi

    if root="$(checkout_on_disk)"; then
        ok "Achei no disco: $root"
        printf '%s\n' "$root"; return 0
    fi

    return 1
}

injected_from_checkout() {
    local root="$1" resources path
    while IFS= read -r resources; do
        path="$(injected_path "$resources" || true)"
        [ -n "$path" ] || continue
        case "$path" in "$root"/*) return 0 ;; esac
    done < <(discord_resources)
    return 1
}

# ----------------------------------------------------------------------------- instalacao

os_field() {
    [ -r /etc/os-release ] || return 0
    sed -n "s/^$1=//p" /etc/os-release | tr -d '"' | head -1
    return 0
}

# Detectado pelo binario, e nao pelo ID da distro: derivada de Arch e de Ubuntu aparece toda
# semana, e o pacman nao muda de nome por causa disso.
package_manager() {
    have pacman  && { printf 'pacman\n';  return 0; }
    have apt-get && { printf 'apt\n';     return 0; }
    have dnf     && { printf 'dnf\n';     return 0; }
    have zypper  && { printf 'zypper\n';  return 0; }
    have apk     && { printf 'apk\n';     return 0; }
    printf 'desconhecido\n'
    return 0
}

install_cmd() {
    case "$(package_manager)" in
        pacman) printf 'sudo pacman -S --needed %s\n' "$*" ;;
        apt)    printf 'sudo apt-get install -y %s\n' "$*" ;;
        dnf)    printf 'sudo dnf install -y %s\n' "$*" ;;
        zypper) printf 'sudo zypper install -y %s\n' "$*" ;;
        apk)    printf 'sudo apk add %s\n' "$*" ;;
        *)      printf '' ;;
    esac
    return 0
}

node_major() {
    local v=""
    have node && v="$(node -v 2>/dev/null | sed -n 's/^v\([0-9][0-9]*\).*/\1/p' | head -1)"
    printf '%s\n' "${v:-0}"
    return 0
}

# O Node do Debian estavel e do Ubuntu LTS costuma ser mais antigo que 22, e o build so quebra
# la na frente, com um erro que nao diz "seu Node e velho". Melhor barrar aqui e explicar.
node_velho_ajuda() {
    printf '\n  %sO Equicord precisa do Node 22 ou mais novo, e o seu e o %s.%s\n' "$C_YELLOW" "$(node_major)" "$C_OFF" >&2
    case "$(package_manager)" in
        pacman)
            printf '  %sNo Arch o pacote nodejs ja e atual. Rode: sudo pacman -Syu nodejs npm%s\n' "$C_DIM" "$C_OFF" >&2 ;;
        apt)
            printf '  %sO pacote do Debian/Ubuntu e antigo demais. Duas saidas:%s\n' "$C_DIM" "$C_OFF" >&2
            printf '  %s  1) nvm:  curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash%s\n' "$C_DIM" "$C_OFF" >&2
            printf '  %s           depois: nvm install 22%s\n' "$C_DIM" "$C_OFF" >&2
            printf '  %s  2) NodeSource: https://github.com/nodesource/distributions%s\n' "$C_DIM" "$C_OFF" >&2 ;;
        dnf)
            printf '  %sNo Fedora: sudo dnf module reset nodejs && sudo dnf module enable nodejs:22%s\n' "$C_DIM" "$C_OFF" >&2 ;;
        *)
            printf '  %sInstale o Node 22 pelo nvm ou pelo fnm.%s\n' "$C_DIM" "$C_OFF" >&2 ;;
    esac
    return 0
}

ensure_toolchain() {
    local need_git="$1" faltando=()

    [ "$need_git" -eq 1 ] && ! have git && faltando+=("git")
    have node || faltando+=("nodejs")
    have npm  || faltando+=("npm")

    if [ ${#faltando[@]} -gt 0 ]; then
        warn "Faltando: ${faltando[*]}"

        local cmd
        cmd="$(install_cmd "${faltando[@]}")"
        if [ -z "$cmd" ]; then
            printf '  %sNao reconheci o gerenciador de pacotes. Instale na mao: %s%s\n' "$C_DIM" "${faltando[*]}" "$C_OFF" >&2
            fail "Instale o que falta e rode de novo."
        fi

        printf '  %sSua distro: %s%s\n' "$C_DIM" "$(os_field PRETTY_NAME)" "$C_OFF" >&2
        printf '  %sComando: %s%s\n' "$C_DIM" "$cmd" "$C_OFF" >&2

        # Rodar por conta propria um comando com sudo seria abuso de confianca; perguntar antes
        # e o minimo, e quem preferir faz na mao com o comando ali em cima.
        if confirm "Posso rodar isso agora?"; then
            eval "$cmd" || fail "A instalacao das dependencias falhou. Rode na mao: $cmd"
            hash -r 2>/dev/null || true
        else
            fail "Instale o que falta e rode de novo."
        fi
    fi

    if [ "$(node_major)" -lt 22 ]; then
        node_velho_ajuda
        fail "Atualize o Node e rode de novo."
    fi

    # Sem corepack de proposito. Ele so serviria para fixar a versao do campo packageManager,
    # que o proprio pnpm ja respeita, e em troca traz dois modos de falha: as chaves de
    # assinatura vencidas que vem no Node 22, e uma pergunta interativa antes de baixar que
    # deixa o instalador parado esperando uma resposta que ninguem sabe que precisa dar.

    # No Arch o pnpm e um pacote como qualquer outro, e sai mais limpo que um -g do npm em
    # /usr/lib, que fica fora do controle do pacman.
    if ! have_pnpm && [ "$(package_manager)" = "pacman" ]; then
        step "Instalando o pnpm pelo pacman"
        sudo pacman -S --needed --noconfirm pnpm >/dev/null 2>&1 || true
        hash -r 2>/dev/null || true
    fi

    if ! have_pnpm; then
        step "Instalando o pnpm pelo npm"
        npm install -g pnpm >/dev/null 2>&1 || sudo npm install -g pnpm >/dev/null 2>&1 || true
        hash -r 2>/dev/null || true
    fi

    have_pnpm || fail 'Nao consegui deixar o pnpm funcionando. Rode: sudo npm install -g pnpm'
    ok "pnpm $(pnpm --version 2>/dev/null)"
}

install_equicord() {
    local target="$HOME/Equicord"

    printf '\n' >&2
    warn "Nao encontrei Equicord nem Vencord no seu computador." >&2
    printf '  %sVou fazer:%s\n' "$C_BOLD" "$C_OFF" >&2
    printf '  %s  1. Baixar o Equicord em %s%s\n' "$C_DIM" "$target" "$C_OFF" >&2
    printf '  %s  2. Instalar as dependencias%s\n' "$C_DIM" "$C_OFF" >&2
    printf '  %s  3. Compilar junto com o GoLiveBypass%s\n' "$C_DIM" "$C_OFF" >&2
    printf '  %s  4. Injetar no Discord (o Discord vai fechar)%s\n\n' "$C_DIM" "$C_OFF" >&2
    confirm "Pode seguir?" || fail "Cancelado."

    ensure_toolchain 1

    if [ -d "$target" ]; then
        is_checkout "$target" || fail "$target ja existe e nao parece um checkout. Apague a pasta ou use --source."
        step "Ja existe um checkout em $target, reaproveitando" >&2
    else
        step "git clone $EQUICORD_GIT" >&2
        git clone --depth 1 "$EQUICORD_GIT" "$target" >&2 || fail "git clone falhou"
    fi

    printf '%s\n' "$target"
}

repo_file() {
    local relative="$1"
    local local_path="$SCRIPT_DIR/../$relative"
    if [ -f "$local_path" ]; then
        cat "$local_path"
        return 0
    fi

    if have curl; then
        curl -fsSL "$REPO_RAW/$relative" || fail "Nao consegui baixar $relative. Verifique sua conexao."
    elif have wget; then
        wget -qO- "$REPO_RAW/$relative" || fail "Nao consegui baixar $relative. Verifique sua conexao."
    else
        fail "Preciso do curl ou do wget para baixar o plugin."
    fi
}

stop_discord() {
    pgrep -x -i 'Discord|DiscordCanary|DiscordPTB' >/dev/null 2>&1 || return 0

    step "Fechando o Discord"
    pkill -x -i 'Discord|DiscordCanary|DiscordPTB' >/dev/null 2>&1 || true

    local i
    for i in $(seq 1 30); do
        sleep 0.3
        pgrep -x -i 'Discord|DiscordCanary|DiscordPTB' >/dev/null 2>&1 || return 0
    done

    fail "O Discord nao fechou. Feche na mao e rode de novo."
}

copy_plugin() {
    local root="$1" target="$1/src/userplugins/$PLUGIN_DIR_NAME" file
    step "Instalando o plugin em $target"
    mkdir -p "$target"

    # versoes antigas usavam index.ts; deixar os dois quebra o build
    rm -f "$target/index.ts"

    for file in "${PLUGIN_FILES[@]}"; do
        if [ -n "$PLUGIN_SOURCE" ]; then
            [ -f "$PLUGIN_SOURCE/$(basename "$file")" ] || fail "Nao achei $(basename "$file") em $PLUGIN_SOURCE."
            cp "$PLUGIN_SOURCE/$(basename "$file")" "$target/$(basename "$file")"
        else
            repo_file "$file" > "$target/$(basename "$file")"
        fi
    done

    # `&&` sozinho como ultima linha deixaria a funcao com o codigo de saida do teste, e sob
    # `set -e` uma pasta vazia derrubaria o instalador inteiro.
    if [ -n "$PLUGIN_SOURCE" ]; then
        warn "Plugin copiado de $PLUGIN_SOURCE, e nao do GitHub."
    fi
}

build_mod() {
    local root="$1"
    if [ ! -d "$root/node_modules" ]; then
        step "Instalando dependencias (na primeira vez demora alguns minutos)"
        (cd "$root" && pnpm install) || fail "pnpm install falhou"
    fi

    step "Compilando"
    (cd "$root" && pnpm build) || fail "pnpm build falhou"
}

inject_mod() {
    local root="$1"
    stop_discord
    step "Injetando no Discord (pode pedir sua senha do sudo)"
    (cd "$root" && pnpm inject) || true

    # O pnpm inject sai com 0 mesmo quando o instalador do mod falha, entao o codigo de saida
    # nao serve de prova. Conferir se a injecao realmente passou a apontar para este checkout.
    injected_from_checkout "$root" || fail "A injecao nao pegou. Se o Discord estiver em /usr/share ou /opt, rode: cd $root && sudo pnpm inject"
}

checkout_mod() {
    # A identidade vem do package.json, nao do nome da pasta: quem baixou o ZIP tem o repo
    # numa pasta chamada Equicord-main, e ai o nome da pasta nao diz nada.
    local root="$1"
    local manifest="$root/package.json"

    if [ -f "$manifest" ]; then
        local name
        name="$(node -e 'try{process.stdout.write(String(require(process.argv[1]).name||""))}catch(e){}' "$manifest" 2>/dev/null || true)"
        case "${name,,}" in
            *equicord*) echo "Equicord"; return 0 ;;
            *vencord*) echo "Vencord"; return 0 ;;
        esac
    fi

    case "$(basename "$root" | tr '[:upper:]' '[:lower:]')" in
        *vencord*) echo "Vencord" ;;
        *) echo "Equicord" ;;
    esac
}

mod_settings_file() {
    # Mesma regra do proprio mod (src/main/utils/constants.ts):
    #   DATA_DIR = <MOD>_USER_DATA_DIR ?? ~/.config/<Mod>
    local root="$1"
    local mod
    mod="$(checkout_mod "$root")"

    local override="${mod^^}_USER_DATA_DIR"
    if [ -n "${!override:-}" ]; then
        printf '%s\n' "${!override}/settings/settings.json"
        return 0
    fi

    printf '%s\n' "$HOME/.config/$mod/settings/settings.json"
}

set_plugin_settings() {
    local root="$1"
    local proxy="$2"
    local file
    file="$(mod_settings_file "$root")"
    mkdir -p "$(dirname "$file")"

    GLB_FILE="$file" GLB_PROXY="$proxy" node -e '
        const fs = require("fs");
        const file = process.env.GLB_FILE;

        let settings = {};
        if (fs.existsSync(file)) {
            const raw = fs.readFileSync(file, "utf8");
            if (raw.trim() !== "") {
                try {
                    settings = JSON.parse(raw);
                } catch (error) {
                    // Nunca reescrever por cima de um arquivo ilegivel: isso apagaria todos os
                    // plugins da pessoa.
                    const backup = file + ".bak-" + Date.now();
                    fs.copyFileSync(file, backup);
                    console.error("ilegivel, copia em " + backup);
                    process.exit(2);
                }
            }
        }

        const plugin = settings.plugins && settings.plugins.GoLiveBypass ? settings.plugins.GoLiveBypass : {};
        plugin.enabled = true;
        plugin.proxy = process.env.GLB_PROXY || "";
        if (plugin.excludedCountries === undefined) plugin.excludedCountries = "BR";

        settings.plugins = settings.plugins || {};
        settings.plugins.GoLiveBypass = plugin;
        fs.writeFileSync(file, JSON.stringify(settings, null, 4));
    ' && step "Plugin ativado em $file" || warn "Nao mexi no $file. Ative o GoLiveBypass na mao em Configuracoes > Plugins."
}

show_status() {
    local root="${1:-}"
    local count mod plugin
    count="$(discord_resources | wc -l)"
    mod="$(installed_mod || true)"

    printf '  %sDetectado:%s\n' "$C_BOLD" "$C_OFF"
    if [ "$count" -gt 0 ]; then
        printf '  %s  Discord   instalado (%s)%s\n' "$C_DIM" "$count" "$C_OFF"
    else
        printf '  %s  Discord   nao encontrado%s\n' "$C_YELLOW" "$C_OFF"
    fi
    printf '  %s  Mod       %s%s\n' "$C_DIM" "${mod:-nenhum}" "$C_OFF"

    if [ -n "$root" ]; then
        printf '  %s  Fonte     %s%s\n' "$C_DIM" "$root" "$C_OFF"
        plugin="$root/src/userplugins/$PLUGIN_DIR_NAME"
        if [ -d "$plugin" ]; then
            printf '  %s  Plugin    ja instalado%s\n' "$C_GREEN" "$C_OFF"
        else
            printf '  %s  Plugin    nao instalado%s\n' "$C_DIM" "$C_OFF"
        fi
    else
        printf '  %s  Fonte     nao encontrado%s\n' "$C_DIM" "$C_OFF"
    fi
    printf '\n'
}

select_target() {
    local root="${1:-}"
    if [ -z "$root" ]; then
        install_equicord
        return
    fi

    ok "Usando o checkout encontrado em $root" >&2
    printf '%s\n' "$root"
}

start_discord() {
    local exe
    for exe in discord Discord discord-canary; do
        if have "$exe"; then
            nohup "$exe" >/dev/null 2>&1 &
            return 0
        fi
    done
}

do_install() {
    local root="${1:-}"
    root="$(select_target "$root")"

    ensure_toolchain 0
    copy_plugin "$root"
    build_mod "$root"

    if injected_from_checkout "$root"; then
        step "O Discord ja carrega deste checkout, so reiniciando"
        stop_discord
    else
        inject_mod "$root"
    fi

    # Com o Discord fechado: aberto, ele regrava o settings.json a partir da memoria e
    # apaga o que escrevemos aqui.
    set_plugin_settings "$root" ""

    start_discord

    printf '\n'
    ok "Pronto. O plugin ja vem ativado, nao precisa mexer em nada."
    printf '  %sProxy: gratuita, escolhida e testada sozinha a cada abertura%s\n' "$C_DIM" "$C_OFF"
    printf '  %sEntre numa call e use Go Live ou a camera.%s\n' "$C_DIM" "$C_OFF"
}

do_uninstall() {
    local root target
    root="$(find_checkout)" || fail "Nao encontrei o checkout do Equicord/Vencord. Use --source."
    target="$root/src/userplugins/$PLUGIN_DIR_NAME"

    [ -d "$target" ] && { step "Removendo $target"; rm -rf "$target"; }

    stop_discord
    step "Desfazendo a injecao"
    (cd "$root" && pnpm uninject) || warn "O pnpm uninject falhou."
    start_discord

    printf '\n'
    ok "Tudo desinstalado. Seu Discord voltou ao normal."
}

main_menu() {
    local root
    root="$(find_checkout || true)"
    show_status "$root"

    printf '  %sO que voce quer fazer?%s\n\n' "$C_BOLD" "$C_OFF"
    printf '    %s[1] Instalar ou reinstalar o GoLiveBypass%s\n' "$C_GREEN" "$C_OFF"
    printf '    %s[2] Desinstalar%s\n' "$C_RED" "$C_OFF"
    printf '    [0] Sair\n\n'

    local choice
    read -r -p "  Escolha: " choice
    case "$choice" in
        1) do_install "$root" ;;
        2) do_uninstall ;;
        *) printf '  %sAte mais.%s\n' "$C_DIM" "$C_OFF" ;;
    esac
}

banner
case "$MODE" in
    install) do_install "$(find_checkout || true)" ;;
    uninstall) do_uninstall ;;
    *) main_menu ;;
esac
printf '\n'
