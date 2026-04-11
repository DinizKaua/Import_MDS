import subprocess

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
def escolher_doenca():
    print("\nCódigo da doença (CID-10)")
    print("Ex: I21 (Infarto), C50 (Câncer)")
    print("Digite ALL para não filtrar")

    valor = input("Digite: ").upper()

    if valor == "":
        return "ALL"

    return valor


# -------------------------------
#   Execução principal
# -------------------------------
def main():
    print("\n===== IMPORTADOR DATASUS =====\n")

    sistema = escolher_sistema()
    ano_inicio, ano_fim, mes_inicio, mes_fim = escolher_periodo()
    uf = escolher_estado()
    sexo = escolher_sexo()
    doenca = escolher_doenca()

    print("\nExecutando coleta...\n")

    try:
        subprocess.run([
            "Rscript", "R/coletar_dados.R",
            "--system", sistema,
            "--year_start", ano_inicio,
            "--year_end", ano_fim,
            "--month_start", mes_inicio,
            "--month_end", mes_fim,
            "--uf", uf,
            "--sexo", sexo,
            "--cid", doenca
        ], check=True)

        print("\nDados coletados com sucesso!")

    except subprocess.CalledProcessError as e:
        print("\nErro ao executar o script R")
        print("Detalhes:", e)


# -------------------------------
#   Start
# -------------------------------
if __name__ == "__main__":
    main()