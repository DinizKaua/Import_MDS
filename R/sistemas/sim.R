# Regras legadas do SIM, preservadas durante a separação do orquestrador.
# Cada função recebe dados em memória; este módulo não realiza coleta ou exportação.

# Recebe um vetor de caracteres da IDADE bruta, antes de process_sim().
# Retorna um data.frame com uma linha por código, na mesma ordem, sem filtragem.
# Contrato de unidades e sentinelas: microdatasus 3.0.0, R/process_sim.R,
# commit 7109ec2c42cf674ba453e0d7a20d2f464890b543, linhas 91–143:
# https://github.com/rfsaldanha/microdatasus/blob/7109ec2c42cf674ba453e0d7a20d2f464890b543/R/process_sim.R#L91
# "valida" exige três dígitos ASCII, unidade reconhecida e, para meses, 00–11.
# Meses 12–99 são inválidos por regra conservadora desta normalização em anos
# completos; esse limite não é uma validação de domínio do pacote oficial.
# Não foram confirmados limites específicos das demais unidades nessa fonte;
# permanecem sem novos limites. Zero anos nas unidades subanuais aceitas é uma
# convenção desta normalização, sem divisões.
# NA, "000" e "999" são desconhecidos; vazio e demais formatos são inválidos.
# A unidade de "000" continua identificável como minutos, mas a idade é NA.
# Não interpreta TIPOBITO nem infere idade fetal ou idade a partir de datas.
normalizar_idade_sim <- function(codigos) {
  if (!is.character(codigos) || !is.null(dim(codigos))) {
    stop("codigos deve ser um vetor de caracteres, com NA_character_ para ausentes.")
  }

  quantidade <- length(codigos)
  resultado <- data.frame(
    idade_codigo_original = unname(codigos),
    idade_unidade_original = rep(NA_character_, quantidade),
    idade_anos_completos = rep(NA_integer_, quantidade),
    idade_situacao = rep("invalida", quantidade),
    stringsAsFactors = FALSE
  )

  desconhecida <- is.na(codigos) | codigos %in% c("000", "999")
  formato_valido <- !is.na(codigos) &
    grepl("\\A[0-9]{3}\\z", codigos, perl = TRUE)
  codigo_unidade <- substr(codigos, 1L, 1L)
  unidades <- c(
    "0" = "minutos", "1" = "horas", "2" = "dias", "3" = "meses",
    "4" = "anos", "5" = "anos_mais_100"
  )
  reconhecida <- formato_valido & codigo_unidade %in% names(unidades)
  resultado$idade_unidade_original[reconhecida] <-
    unname(unidades[codigo_unidade[reconhecida]])

  valida <- reconhecida & !desconhecida
  meses <- which(valida & codigo_unidade == "3")
  meses_fora_contrato <- meses[as.integer(substr(codigos[meses], 2L, 3L)) >= 12L]
  valida[meses_fora_contrato] <- FALSE
  resultado$idade_situacao[desconhecida] <- "desconhecida"
  resultado$idade_situacao[valida] <- "valida"

  subanual <- valida & codigo_unidade %in% c("0", "1", "2", "3")
  resultado$idade_anos_completos[subanual] <- 0L
  anos <- valida & codigo_unidade == "4"
  resultado$idade_anos_completos[anos] <-
    as.integer(substr(codigos[anos], 2L, 3L))
  centena <- valida & codigo_unidade == "5"
  resultado$idade_anos_completos[centena] <-
    as.integer(substr(codigos[centena], 2L, 3L)) + 100L

  resultado
}

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
