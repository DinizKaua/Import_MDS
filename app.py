import subprocess
import sys
from pathlib import Path
import json
import re

# -------------------------------
#   Tipo de sistema
# -------------------------------
def escolher_sistema():
    print("Tipo de dado:")
    print("1 - Óbitos (SIM-DO)")
    print("2 - Internações (SIH-RD)")

    opcao = input("Escolha: ")

    if opcao == "1":
        return "SIM-DO"
    elif opcao == "2":
        return "SIH-RD"
    else:
        print("Opção inválida\n")
        return escolher_sistema()


# -------------------------------
#   Período
# -------------------------------
def escolher_periodo():
    print("\nPeríodo dos dados:")

    print("1 - Anual")
    print("2 - Mensal")

    tipo = input("Escolha: ")

    ano_inicio = input("Ano início: ")
    ano_fim = input("Ano fim: ")

    mes_inicio = "1"
    mes_fim = "12"

    if tipo == "2":
        mes_inicio = input("Mês início (1-12): ")
        mes_fim = input("Mês fim (1-12): ")

    return ano_inicio, ano_fim, mes_inicio, mes_fim


# -------------------------------
#   Estado
# -------------------------------
def escolher_estado():
    print("\nEstado (UF)")
    print("Ex: MA, SP, RJ ou ALL (todos)")

    return input("Digite: ").upper()


# -------------------------------
#   Filtro sexo
# -------------------------------
def escolher_sexo():
    print("\nFiltrar por sexo?")
    print("1 - Masculino")
    print("2 - Feminino")
    print("3 - Não filtrar")

    opcao = input("Escolha: ")

    if opcao == "1":
        return "Masculino"
    elif opcao == "2":
        return "Feminino"
    else:
        return "ALL"


# -------------------------------
#   Doença (CID)
# -------------------------------
def interpretar_intervalo_cid(valor, referencia=None):
    # Sem hífen, preservar o prefixo literal, inclusive espaços/ponto/vazio.
    if "-" not in valor:
        return valor
    partes = re.fullmatch(r"[ \t]*([A-Z][0-9]{2})[ \t]*-[ \t]*([A-Z][0-9]{2})[ \t]*", valor.upper())
    if partes is None:
        raise ValueError("Intervalo inválido: use categorias completas, como I10-I15, com um único hífen.")
    inicio, fim = partes.groups()
    if inicio[0] != fim[0]:
        raise ValueError("Os limites CID devem ter a mesma letra.")
    if int(inicio[1:]) > int(fim[1:]):
        raise ValueError("Intervalo CID com limites invertidos.")
    if referencia is None:
        caminho = Path(__file__).resolve().parent / "referencias" / "cid10" / "oms_2019_codigos.json"
        try:
            with caminho.open(encoding="utf-8") as arquivo:
                referencia = json.load(arquivo)
        except (OSError, ValueError) as erro:
            raise RuntimeError("Referência local CID-10 indisponível ou ilegível.") from erro
    try:
        categorias = referencia["categorias"]
        if (referencia["versao_indice"] != "1.0.0" or not isinstance(categorias, list)
                or not categorias or not all(isinstance(c, str) and re.fullmatch(r"[A-Z][0-9]{2}", c) for c in categorias)
                or len(set(categorias)) != len(categorias)
                or referencia["referencia"]["quantidade_categorias"] != len(categorias)):
            raise ValueError("Contrato inválido")
    except (KeyError, TypeError, ValueError) as erro:
        raise RuntimeError("Referência local CID-10 inválida ou incompleta.") from erro
    if inicio not in categorias or fim not in categorias:
        raise ValueError("Limite CID inexistente na referência local utilizada.")
    return f"{inicio}-{fim}"


def escolher_doenca():
    print("\nCódigo da doença (CID-10)")
    print("Digite um prefixo, como I21, ou um intervalo de categorias, como I10-I15.")
    print("Digite ALL para não filtrar")

    while True:
        valor = input("Digite: ").upper()
        if valor == "":
            return "ALL"
        try:
            return interpretar_intervalo_cid(valor)
        except ValueError as erro:
            print(erro)

# -------------------------------
#   Raça/Cor
# -------------------------------
def escolher_raca():
    print("\nFiltrar por raça/cor?")
    print("1 - Branca")
    print("2 - Preta")
    print("3 - Parda")
    print("4 - Amarela")
    print("5 - Indígena")
    print("6 - Não filtrar")

    opcao = input("Escolha: ")

    mapa = {
        "1": "Branca",
        "2": "Preta",
        "3": "Parda",
        "4": "Amarela",
        "5": "Indigena"
    }

    return mapa.get(opcao, "ALL")

# -------------------------------
#   Limites etários opcionais (anos completos)
# -------------------------------
def ler_limite_idade(pergunta):
    while True:
        valor = input(pergunta)
        if valor == "":
            return None
        if not valor.isascii() or not valor.isdigit():
            print("Informe um inteiro não negativo, sem espaços, ou Enter para não limitar.")
            continue
        try:
            idade = int(valor)
        except ValueError:
            print("Valor excede o limite técnico de representação aceito pelo R.")
            continue
        # Mesmo limite técnico de representação exata de resolver_limites_idade_sim().
        if idade > 2**53 - 1:
            print("Valor excede o limite técnico de representação aceito pelo R (9007199254740991).")
            continue
        return idade


def escolher_limites_idade():
    print("\nLimites etários em anos completos:")
    idade_min = ler_limite_idade("Idade mínima (Enter para não limitar): ")
    while True:
        idade_max = ler_limite_idade("Idade máxima (Enter para não limitar): ")
        if idade_min is not None and idade_max is not None and idade_min > idade_max:
            print("A idade máxima não pode ser menor que a idade mínima. Informe novamente a máxima.")
            continue
        return idade_min, idade_max

# -------------------------------
#   Execução principal
# -------------------------------
def main():
    print("\n===== IMPORTADOR DATASUS =====\n")

    sistema = escolher_sistema()
    ano_inicio, ano_fim, mes_inicio, mes_fim = escolher_periodo()
    uf = escolher_estado()
    sexo = escolher_sexo()
    raca = escolher_raca()
    idade_min, idade_max = escolher_limites_idade()
    try:
        doenca = escolher_doenca()
    except RuntimeError as erro:
        print("\nNão foi possível validar o intervalo CID:", erro)
        return 1


    print("\nExecutando coleta...\n")

    argumentos = [
        "Rscript", str(Path(__file__).resolve().parent / "R" / "coletar_dados.R"),
        "--system", sistema,
        "--year_start", ano_inicio,
        "--year_end", ano_fim,
        "--month_start", mes_inicio,
        "--month_end", mes_fim,
        "--uf", uf,
        "--sexo", sexo,
        "--cid", doenca,
        "--raca", raca
    ]
    if idade_min is not None:
        argumentos.extend(["--idade_min", str(idade_min)])
    if idade_max is not None:
        argumentos.extend(["--idade_max", str(idade_max)])

    try:
        subprocess.run(argumentos, check=True)

        print("\nDados coletados com sucesso!")
        return 0

    except subprocess.CalledProcessError as e:
        print("\nErro ao executar o script R")
        print("Detalhes:", e)
        return e.returncode if e.returncode > 0 else 1
    except FileNotFoundError:
        print("\nExecutável Rscript não encontrado. Verifique se o R está disponível no PATH.")
        return 127
    except OSError as e:
        print("\nNão foi possível iniciar o Rscript:", e)
        return 1


# -------------------------------
#   Start
# -------------------------------
if __name__ == "__main__":
    sys.exit(main())
