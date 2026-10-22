# Compartilhado por configurar.sh e iniciar.sh. Não executa nada ao ser carregado.
orientar_sistema() {
    if command -v apt-get >/dev/null 2>&1; then
        echo 'Ubuntu/Mint/Zorin: instale os programas pelo gerenciador de aplicativos ou peça ajuda a um administrador.' >&2
        echo 'Comandos manuais possíveis (revise antes; estes scripts NÃO os executam):' >&2
        echo '  sudo apt update' >&2
        echo '  sudo apt install python3 r-base r-base-dev coreutils ca-certificates tzdata' >&2
        echo 'Para compilar bibliotecas R: build-essential gfortran libcurl4-openssl-dev libicu-dev pkg-config.' >&2
    else
        echo 'Consulte o gerenciador da sua distribuição para instalar Python 3, R e GNU coreutils.' >&2
        echo 'Não há instalação automática de programas do sistema. Consulte DEPENDENCIAS.md.' >&2
    fi
}

verificar_base() {
    local raiz=$1 programa arquivo uuid destino
    if [[ $(uname -s) != Linux ]]; then
        echo 'ERRO: suporte inicial somente a Linux. Windows e macOS nativos não são suportados.' >&2
        return 1
    fi
    case "$raiz" in
        *:*|*$'\n'*|*$'\r'*) echo 'ERRO: o caminho do projeto não pode conter dois-pontos ou quebras de linha (limite de R_LIBS).' >&2; return 1 ;;
    esac
    echo 'Verificando programas e arquivos do Import_MDS...'
    for programa in python3 R Rscript sha256sum readlink; do
        if ! command -v "$programa" >/dev/null 2>&1; then
            echo "ERRO: $programa não encontrado no PATH." >&2
            orientar_sistema
            return 1
        fi
    done
    if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 8) else 1)'; then
        echo 'ERRO: é necessário Python 3.8 ou superior.' >&2
        return 1
    fi
    for arquivo in app.py R/coletar_dados.R R/sistemas/sim.R R/comum/cid.R R/comum/auditoria.R R/comum/exportacao.R R/configurar_ambiente.R scripts/gerar_referencia_cid10.py referencias/cid10/oms_2019_codigos.json referencias/cid10/icd102019en.xml.zip; do
        if [[ ! -f "$raiz/$arquivo" || ! -r "$raiz/$arquivo" ]]; then
            echo "ERRO: arquivo fundamental ausente/ilegível: $arquivo. Extraia o ZIP completo." >&2
            return 1
        fi
    done
    if [[ ! -r /proc/sys/kernel/random/uuid ]] || ! IFS= read -r uuid < /proc/sys/kernel/random/uuid ||
        [[ ! $uuid =~ ^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$ ]]; then
        echo 'ERRO: UUID v4 do kernel Linux indisponível em /proc/sys/kernel/random/uuid.' >&2
        return 1
    fi
    if [[ -L "$raiz/Dados" || ( -e "$raiz/Dados" && ! -d "$raiz/Dados" ) ]]; then
        echo 'ERRO: Dados/ deve ser um diretório real, sem link simbólico.' >&2
        return 1
    fi
    destino=$raiz
    [[ ! -d "$raiz/Dados" ]] || destino="$raiz/Dados"
    if [[ ! -w "$destino" || ! -x "$destino" ]]; then
        echo 'ERRO: sem permissão para criar resultados em Dados/. Use uma pasta pessoal com permissão de escrita.' >&2
        return 1
    fi
    if ! python3 -B - "$raiz" <<'PY'
import json, runpy, sys
from pathlib import Path
try:
    raiz = Path(sys.argv[1])
    indice = json.loads((raiz / 'referencias/cid10/oms_2019_codigos.json').read_text(encoding='utf-8'))
    gerador = runpy.run_path(str(raiz / 'scripts/gerar_referencia_cid10.py'))
    esperado = gerador['gerar'](raiz / 'referencias/cid10/icd102019en.xml.zip', indice['referencia']['obtido_em_utc'])
    if indice != esperado:
        raise ValueError('índice diferente do ZIP e do gerador fixados')
except Exception as erro:
    print('ERRO: referência CID-10 local inválida:', erro, file=sys.stderr)
    sys.exit(1)
print('Referência OMS local e correção de diabetes verificadas, sem acesso à internet.')
PY
    then
        return 1
    fi
    biblioteca_local=$(Rscript --vanilla "$raiz/R/configurar_ambiente.R" biblioteca "$raiz") || return 1
    export R_LIBS="$biblioteca_local${R_LIBS:+:$R_LIBS}"
    export PYTHONDONTWRITEBYTECODE=1
    if ! command -v git >/dev/null 2>&1; then
        echo 'AVISO: Git ausente; não é necessário para ZIP, instalação ou uso. Identificação Git no JSON poderá ficar indisponível.'
    fi
}

testar_saida() (
    local raiz=$1 teste
    for programa in mktemp ln rm rmdir; do
        command -v "$programa" >/dev/null 2>&1 || { echo "ERRO: falta $programa (coreutils)." >&2; return 1; }
    done
    if [[ ! -d "$raiz/Dados" ]]; then
        mkdir -- "$raiz/Dados" || { echo 'ERRO: não foi possível criar Dados/.' >&2; return 1; }
    fi
    teste=$(mktemp -d -- "$raiz/Dados/.import-mds-teste.XXXXXXXX") || return 1
    trap 'rm -f -- "$teste/origem" "$teste/ligacao"; rmdir -- "$teste"' EXIT
    printf 'teste Import_MDS\n' > "$teste/origem" || return 1
    if ! ln -- "$teste/origem" "$teste/ligacao"; then
        echo 'ERRO: o sistema de arquivos de Dados/ não permite hard links. A publicação segura não pode funcionar aqui.' >&2
        return 1
    fi
    sha256sum -- "$teste/ligacao" >/dev/null || return 1
    echo 'Escrita, hard links e sha256sum verificados; somente os temporários próprios serão removidos.'
)
