# Regras legadas do SIM, preservadas durante a separação do orquestrador.
# Cada função recebe dados em memória; este módulo não realiza coleta ou exportação.

processar_dados_sim <- function(dados_brutos) {
  microdatasus::process_sim(dados_brutos) |>
    dplyr::mutate(
      data_evento = as.Date(DTOBITO),
      cid_valor = toupper(CAUSABAS),
      IDADE_NUM = as.numeric(IDADEanos)
    )
}

filtrar_dados_sim <- function(dados, sexo = "ALL", raca = "ALL",
                              faixa = "ALL", cid = "ALL") {
  # Exclusões obrigatórias da pesquisa original, mantidas nesta etapa.
  dados <- dados |>
    dplyr::filter(!is.na(data_evento)) |>
    dplyr::filter(!is.na(IDADE_NUM) & IDADE_NUM >= 18)

  if (sexo != "ALL") {
    dados <- dplyr::filter(dados, SEXO == sexo)
  }

  if (raca != "ALL") {
    dados <- dplyr::filter(dados, RACACOR == raca)
  }

  if (faixa != "ALL") {
    if (faixa == "18-39") {
      dados <- dplyr::filter(dados, IDADE_NUM >= 18 & IDADE_NUM <= 39)
    } else if (faixa == "40-59") {
      dados <- dplyr::filter(dados, IDADE_NUM >= 40 & IDADE_NUM <= 59)
    } else if (faixa == "60+") {
      dados <- dplyr::filter(dados, IDADE_NUM >= 60)
    }
  }

  if (cid != "ALL") {
    dados <- dplyr::filter(dados, startsWith(cid_valor, cid))
  }

  dados
}

selecionar_colunas_sim <- function(dados) {
  dplyr::select(dados, dplyr::any_of(c(
    "IDADEanos",
    "DTNASC",
    "ESTCIV",
    "SEXO",
    "RACACOR",
    "LOCOCOR",
    "CODESTAB",
    "data_evento",
    "munResUf",
    "munResNome",
    "NATURAL",
    "CODMUNNATU",
    "ASSISTMED",
    "cid_valor"
  ))) |>
    dplyr::rename(
      IDADE = IDADEanos,
      DATA_DE_NASCIMENTO = DTNASC,
      ESTADO_CIVIL = ESTCIV,
      RACA_COR = RACACOR,
      LOCAL_OBITO = LOCOCOR,
      ESTABELECIMENTO = CODESTAB,
      DATA = data_evento,
      ESTADO_RESIDENCIA = munResUf,
      MUNICIPIO_RESIDENCIA = munResNome,
      ESTADO_NATURALIDADE = NATURAL,
      MUNICIPIO_NATURALIDADE = CODMUNNATU,
      ASSISTENCIA_MEDICA = ASSISTMED,
      DOENCA = cid_valor
    )
}

preparar_exportacao_sim <- function(dados_brutos, sexo = "ALL", raca = "ALL",
                                   faixa = "ALL", cid = "ALL") {
  processar_dados_sim(dados_brutos) |>
    filtrar_dados_sim(sexo = sexo, raca = raca, faixa = faixa, cid = cid) |>
    selecionar_colunas_sim()
}
