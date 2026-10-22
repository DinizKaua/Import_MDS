#!/usr/bin/env bash
set -euo pipefail

if [[ $(uname -s) != Linux ]]; then
    echo 'ERRO: suporte inicial somente a Linux. Windows e macOS nativos não são suportados.' >&2
    exit 1
fi
if ! command -v readlink >/dev/null 2>&1; then
    echo 'ERRO: falta readlink (coreutils). Consulte README.md.' >&2
    exit 1
fi
script=$(readlink -f -- "${BASH_SOURCE[0]}")
raiz=$(cd -- "$(dirname -- "$script")" && pwd -P)
if [[ $# -ne 0 ]]; then
    echo 'Uso: bash iniciar.sh' >&2
    exit 2
fi
if [[ ! -r "$raiz/scripts/ambiente.sh" || ! -r "$raiz/configurar.sh" ]]; then
    echo 'ERRO: projeto incompleto. Extraia novamente o ZIP completo.' >&2
    exit 1
fi
source "$raiz/scripts/ambiente.sh"
verificar_base "$raiz" || exit 1
if ! Rscript --vanilla "$raiz/R/configurar_ambiente.R" verificar "$raiz"; then
    echo 'ERRO: execute bash configurar.sh antes de iniciar. Nenhuma instalação foi realizada.' >&2
    exit 1
fi
echo 'Abrindo o menu. Somente suas escolhas no menu iniciam uma consulta.'
exec python3 "$raiz/app.py"
