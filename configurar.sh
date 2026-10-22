#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Linux ]]; then
    echo 'ERRO: suporte inicial somente a Linux. Windows e macOS nativos não são suportados.' >&2
    exit 1
fi
if ! command -v readlink >/dev/null 2>&1; then
    echo 'ERRO: falta readlink (pacote coreutils no Ubuntu/Mint/Zorin).' >&2
    exit 1
fi
script=$(readlink -f -- "${BASH_SOURCE[0]}")
raiz=$(cd -- "$(dirname -- "$script")" && pwd -P)
if [[ ! -r "$raiz/scripts/ambiente.sh" ]]; then
    echo 'ERRO: projeto incompleto. Extraia novamente o ZIP completo.' >&2
    exit 1
fi
source "$raiz/scripts/ambiente.sh"

modo=configurar
if [[ $# -eq 1 && $1 == --check ]]; then
    modo=check
elif [[ $# -ne 0 ]]; then
    echo 'Uso: bash configurar.sh [--check]' >&2
    exit 2
fi

verificar_base "$raiz" || exit 1
if [[ $modo == configurar ]]; then
    testar_saida "$raiz" || exit 1
else
    echo 'AVISO: --check não cria arquivos; escrita e hard links não são ensaiados neste modo.'
fi

if Rscript --vanilla "$raiz/R/configurar_ambiente.R" verificar "$raiz"; then
    :
else
    codigo=$?
    if [[ $codigo -ne 10 || $modo == check ]]; then
        echo 'ERRO: ambiente não está pronto. Execute bash configurar.sh e consulte DEPENDENCIAS.md.' >&2
        exit 1
    fi
    echo "Os pacotes listados acima serão instalados somente em: $biblioteca_local"
    echo 'Dependências transitivas ausentes/incompatíveis também podem ser instaladas nessa biblioteca.'
    echo 'Haverá acesso ao CRAN e/ou GitHub, compilação local e uso de espaço em disco.'
    echo 'Pacotes globais e pacotes já compatíveis não serão substituídos.'
    resposta=''
    read -r -p 'Autoriza essa instalação? [s/N] ' resposta || true
    case "$resposta" in
        s|S|sim|SIM) ;;
        *) echo 'Instalação não autorizada. Nenhum pacote foi instalado.' >&2; exit 1 ;;
    esac
    Rscript --vanilla "$raiz/R/configurar_ambiente.R" instalar "$raiz" --confirmado || exit 1
    Rscript --vanilla "$raiz/R/configurar_ambiente.R" verificar "$raiz" || exit 1
fi
echo 'Configuração verificada com sucesso. Próximo comando: bash iniciar.sh'
