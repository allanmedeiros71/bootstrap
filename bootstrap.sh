#!/usr/bin/env bash
# bootstrap.sh — primeiros passos num PC zerado, até entregar ao pos-install.sh
#
#   curl -fsSL https://boot.medeiros.cloud | bash
#   curl -fsSL https://boot.medeiros.cloud | bash -s -- --only dotfiles,apps
#   curl -fsSL https://boot.medeiros.cloud | bash -s -- --dry-run
#   curl -fsSL https://boot.medeiros.cloud | bash -s -- --bootstrap-only
#
# Etapas:
#   1. git, curl e ssh (no macOS, as Command Line Tools)
#   2. chave SSH (~/.ssh/id_ed25519), carregada no ssh-agent
#   3. cadastro da chave no GitHub com o gh — login pelo navegador ou pelo celular,
#      sem copiar e colar a chave
#   4. clone de allanmedeiros71/scripts em ~/git/scripts
#   5. exec pos-install.sh com os argumentos recebidos (ele chama o chezmoi)
#
# Opções próprias (as demais vão para o pos-install.sh):
#   --bootstrap-only   para depois do clone, sem rodar o pos-install.sh
#   -n, --dry-run      mostra o que faria; com o repo já clonado, roda o pos-install.sh --dry-run
#   -h, --help         esta ajuda
#
# Variáveis de ambiente:
#   GH_TOKEN      token do GitHub com escopo admin:public_key — pula o login (testes, automação)
#   SCRIPTS_REPO  padrão git@github.com:allanmedeiros71/scripts.git
#   SCRIPTS_DIR   padrão ~/git/scripts (o chezmoi espera o repo ali)
#
# ARQUIVO PÚBLICO: nada de segredo aqui.

set -euo pipefail

SCRIPTS_REPO="${SCRIPTS_REPO:-git@github.com:allanmedeiros71/scripts.git}"
SCRIPTS_DIR="${SCRIPTS_DIR:-$HOME/git/scripts}"
KEY="$HOME/.ssh/id_ed25519"

DRY_RUN=false
ONLY_BOOTSTRAP=false
TTY=/dev/tty    # com curl | bash o stdin é o próprio script: o que é interativo lê daqui
GH=""           # caminho do gh (do sistema ou baixado para $TMP)
TMP=""

# ---------------------------------------------------------------------------
# Utilitários
# ---------------------------------------------------------------------------
has()   { command -v "$1" >/dev/null 2>&1; }
title() { printf '\n\033[1;35m▶ %s\033[0m\n' "$*"; }
info()  { printf '  %s\n' "$*"; }
ok()    { printf '  \033[32m✔\033[0m %s\n' "$*"; }
warn()  { printf '  \033[33m⚠\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[31m✖ %s\033[0m\n' "$*" >&2; exit 1; }

run() {
    if $DRY_RUN; then printf '  \033[2m[dry-run] %s\033[0m\n' "$*"; else "$@"; fi
}

interactive() { [ "$TTY" = /dev/tty ]; }

pause() {  # pause "mensagem"
    printf '  %s ' "$1"
    read -r _ <"$TTY" || true
}

usage() {  # texto embutido: com curl | bash não há arquivo para ler o cabeçalho
    cat <<'TXT'
Uso: curl -fsSL https://boot.medeiros.cloud | bash [-s -- opções]

  --bootstrap-only   para depois do clone, sem rodar o pos-install.sh
  -n, --dry-run      mostra o que faria (repassado ao pos-install.sh)
  -h, --help         esta ajuda
  demais opções      vão para o pos-install.sh (ex.: --only dotfiles,apps)

Variáveis: GH_TOKEN (escopo admin:public_key; pula o login), SCRIPTS_REPO, SCRIPTS_DIR
TXT
}

cleanup() { [ -n "$TMP" ] && rm -rf "$TMP"; TMP=""; }

detect_os() {
    if [ "$(uname -s)" = Darwin ]; then echo macos; return; fi
    [ -r /etc/os-release ] || die "/etc/os-release não encontrado"
    local id
    for id in $(. /etc/os-release; echo "$ID ${ID_LIKE:-}"); do
        case "$id" in
            arch)          echo arch;   return ;;
            fedora)        echo fedora; return ;;
            debian|ubuntu) echo debian; return ;;
        esac
    done
    die "Distribuição não suportada"
}

sha256_check() {  # lê "hash  arquivo" do stdin
    if has sha256sum; then sha256sum --status -c -; else shasum -a 256 --status -c -; fi
}

# ---------------------------------------------------------------------------
# 1. Pré-requisitos
# ---------------------------------------------------------------------------
install_prereqs() {
    title "Pré-requisitos (git, curl, ssh)"
    if [ "$OS" = macos ]; then
        # No macOS o /usr/bin/git existe mesmo sem as Command Line Tools (só abre o instalador)
        if xcode-select -p >/dev/null 2>&1; then ok "Command Line Tools já instaladas"; return; fi
        run xcode-select --install || true
        $DRY_RUN && return
        interactive || die "Instale as Command Line Tools (xcode-select --install) e rode de novo"
        pause "Conclua a instalação na janela que abriu e tecle Enter…"
        until xcode-select -p >/dev/null 2>&1; do
            pause "Ainda não terminou — tecle Enter quando concluir…"
        done
        ok "Command Line Tools instaladas"
        return
    fi

    if has git && has curl && has ssh && has ssh-keygen; then ok "Já instalados"; return; fi
    has sudo || die "sudo não encontrado — instale-o e adicione $USER ao grupo de administradores"
    case "$OS" in
        debian)
            run sudo apt-get update -qq
            run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
                git curl openssh-client ca-certificates ;;
        fedora)
            run sudo dnf install -y -q git curl openssh-clients ;;
        arch)
            # -Syu junto: no Arch não se instala pacote com a base desatualizada
            run sudo pacman -Syu --needed --noconfirm git curl openssh ;;
    esac
    $DRY_RUN || ok "git, curl e ssh instalados"
}

# ---------------------------------------------------------------------------
# 2. Chave SSH
# ---------------------------------------------------------------------------
ensure_key() {
    title "Chave SSH"
    run mkdir -p "$HOME/.ssh"
    run chmod 700 "$HOME/.ssh"

    if [ -f "$KEY" ]; then
        ok "Usando $KEY"
    elif interactive; then
        info "Escolha uma senha para a chave (Enter deixa sem senha)"
        run ssh-keygen -q -t ed25519 -C "$USER@$(uname -n)" -f "$KEY" <"$TTY"
    else
        run ssh-keygen -q -t ed25519 -C "$USER@$(uname -n)" -f "$KEY" -N ""
    fi
    $DRY_RUN && return

    # No agente, a senha digitada uma vez vale para o clone e para o chezmoi
    # (o pos-install.sh herda o SSH_AUTH_SOCK)
    if [ -z "${SSH_AUTH_SOCK:-}" ]; then
        eval "$(ssh-agent -s)" >/dev/null
    fi
    local fp
    fp=$(ssh-keygen -lf "$KEY.pub" | awk '{print $2}')
    if ! ssh-add -l 2>/dev/null | grep -qF "$fp"; then
        ssh-add -q "$KEY" <"$TTY" || warn "Não foi possível carregar a chave no ssh-agent"
    fi
    ok "Chave no ssh-agent"
}

# ---------------------------------------------------------------------------
# 3. GitHub
# ---------------------------------------------------------------------------
github_known_hosts() {
    local kh="$HOME/.ssh/known_hosts" keys=""
    if [ -f "$kh" ] && ssh-keygen -F github.com -f "$kh" >/dev/null 2>&1; then return; fi
    # Chaves que o GitHub publica via HTTPS — melhor que confiar no primeiro contato do ssh-keyscan
    keys=$(curl -fsSL https://api.github.com/meta 2>/dev/null \
        | grep -oE '"(ssh-ed25519|ecdsa-sha2-nistp256|ssh-rsa) [A-Za-z0-9+/=]+"' \
        | tr -d '"') || keys=""
    if [ -z "$keys" ]; then
        warn "api.github.com/meta indisponível — usando ssh-keyscan"
        keys=$(ssh-keyscan -t ed25519 github.com 2>/dev/null | cut -d' ' -f2-)
    fi
    [ -n "$keys" ] || die "Não consegui obter as chaves de host do GitHub"
    printf '%s\n' "$keys" | sed 's/^/github.com /' >>"$kh"
    ok "github.com em ~/.ssh/known_hosts"
}

github_ssh_ok() {
    # ssh -T sai com 1 mesmo quando autentica: o que vale é a mensagem
    local out
    out=$(ssh -T -o BatchMode=yes -o ConnectTimeout=10 git@github.com 2>&1 || true)
    case "$out" in *"successfully authenticated"*) return 0 ;; esac
    return 1
}

# gh do sistema ou binário da release oficial (sha256 conferido), só para esta execução.
# O login fica salvo em ~/.config/gh e vale para o gh que o chezmoi instala depois.
get_gh() {
    if has gh; then GH=gh; return; fi
    local os arch ver base file ext url
    case "$(uname -s)" in
        Linux)  os=linux ;;
        Darwin) os=macOS ;;
    esac
    case "$(uname -m)" in
        x86_64|amd64)  arch=amd64 ;;
        aarch64|arm64) arch=arm64 ;;
        *) die "Sem binário do gh para $(uname -m) — instale o gh e rode de novo" ;;
    esac
    ext=tar.gz; [ "$os" = macOS ] && ext=zip

    # /releases/latest redireciona para /releases/tag/vX.Y.Z (sem a API e seu limite de requisições)
    url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)
    ver=${url##*/v}
    case "$ver" in
        [0-9]*.[0-9]*.[0-9]*) ;;
        *) die "Não consegui descobrir a versão do gh ($url)" ;;
    esac

    base="https://github.com/cli/cli/releases/download/v$ver"
    file="gh_${ver}_${os}_${arch}"
    TMP=$(mktemp -d)
    info "Baixando gh $ver"
    curl -fsSL -o "$TMP/$file.$ext" "$base/$file.$ext"
    curl -fsSL -o "$TMP/checksums.txt" "$base/gh_${ver}_checksums.txt"
    (cd "$TMP" && grep " $file.$ext\$" checksums.txt | sha256_check) \
        || die "Checksum do gh não confere — abortando"
    if [ "$ext" = zip ]; then
        unzip -q "$TMP/$file.$ext" -d "$TMP"
    else
        tar -xzf "$TMP/$file.$ext" -C "$TMP"
    fi
    GH="$TMP/$file/bin/gh"
    [ -x "$GH" ] || die "gh não encontrado no pacote baixado"
}

register_key() {
    title "GitHub"
    if $DRY_RUN; then
        info "[dry-run] cadastraria $KEY.pub no GitHub (gh auth login pelo navegador)"
        return
    fi
    github_known_hosts
    if github_ssh_ok; then ok "O GitHub já aceita esta chave"; return; fi

    get_gh
    if ! "$GH" auth status -h github.com >/dev/null 2>&1; then
        interactive || die "Sem terminal para o login: defina GH_TOKEN (escopo admin:public_key)"
        info "Login no GitHub: copie o código, abra a URL (pode ser no celular) e autorize"
        "$GH" auth login -h github.com -p ssh -w -s admin:public_key --skip-ssh-key <"$TTY"
    fi

    local key_title
    key_title="$(uname -n) ($(date +%Y-%m-%d))"
    if ! "$GH" ssh-key add "$KEY.pub" --title "$key_title"; then
        [ -n "${GH_TOKEN:-}" ] && die "O GH_TOKEN precisa do escopo admin:public_key"
        info "O login atual não pode cadastrar chaves — pedindo o escopo admin:public_key"
        "$GH" auth refresh -h github.com -s admin:public_key <"$TTY"
        "$GH" ssh-key add "$KEY.pub" --title "$key_title" || die "Falha ao cadastrar a chave no GitHub"
    fi

    local _
    for _ in 1 2 3 4 5; do
        if github_ssh_ok; then ok "Chave cadastrada e aceita pelo GitHub"; return; fi
        sleep 2
    done
    die "O GitHub ainda não aceita a chave — confira em https://github.com/settings/keys"
}

# ---------------------------------------------------------------------------
# 4. Repositório de scripts
# ---------------------------------------------------------------------------
clone_scripts() {
    title "Repositório de scripts"
    if [ -d "$SCRIPTS_DIR/.git" ]; then
        if run git -C "$SCRIPTS_DIR" pull --ff-only --quiet; then
            ok "Atualizado: $SCRIPTS_DIR"
        else
            warn "git pull falhou — seguindo com a cópia local"
        fi
    elif [ -e "$SCRIPTS_DIR" ] && [ -n "$(ls -A "$SCRIPTS_DIR" 2>/dev/null)" ]; then
        die "$SCRIPTS_DIR já existe e não é um clone git — mova-o e rode de novo"
    else
        run mkdir -p "$(dirname "$SCRIPTS_DIR")"
        run git clone --quiet "$SCRIPTS_REPO" "$SCRIPTS_DIR"
        ok "Clonado em $SCRIPTS_DIR"
    fi
}

# ---------------------------------------------------------------------------
# Principal
# ---------------------------------------------------------------------------
main() {
    local pass=() arg
    for arg in "$@"; do
        case "$arg" in
            --bootstrap-only) ONLY_BOOTSTRAP=true ;;
            -n|--dry-run)     DRY_RUN=true; pass+=("$arg") ;;
            -h|--help)        usage; exit 0 ;;
            *)                pass+=("$arg") ;;
        esac
    done

    [ "$EUID" -ne 0 ] || die "Rode como usuário normal — o script usa sudo quando precisa"
    # Sem terminal (CI, container de teste): nada de perguntas
    { : <"$TTY"; } 2>/dev/null || TTY=/dev/null
    trap cleanup EXIT

    OS="$(detect_os)"
    title "Bootstrap — $OS"
    $DRY_RUN && warn "Modo dry-run: nada será alterado"

    install_prereqs
    ensure_key
    register_key
    clone_scripts
    cleanup

    local pos="$SCRIPTS_DIR/pos-install.sh"
    if $ONLY_BOOTSTRAP; then
        title "Pronto"
        info "Próximo passo: $pos"
        exit 0
    fi
    if [ ! -x "$pos" ]; then
        $DRY_RUN && { info "[dry-run] executaria $pos ${pass[*]+${pass[*]}}"; exit 0; }
        die "$pos não encontrado"
    fi

    title "Passando para o pos-install.sh"
    # ${pass[@]+…}: bash 3.2 (macOS) reclama de array vazio com set -u
    exec "$pos" ${pass[@]+"${pass[@]}"} <"$TTY"
}

# Só aqui algo é executado: se o download parar no meio, nada roda pela metade
main "$@"
