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

# Limites aceitam escalares numéricos inteiros ou texto contendo apenas dígitos.
# NULL significa ausência; vazio, NA, frações e coerções permissivas são rejeitados.
resolver_limites_idade_sim <- function(idade_min = NULL, idade_max = NULL,
                                      faixa = "ALL") {
  validar <- function(valor, nome) {
    if (is.null(valor)) return(NULL)
    erro <- function() stop(nome, " deve ser um inteiro não negativo ou NULL.")
    if (length(valor) != 1L || is.object(valor) || !is.null(dim(valor)) || is.na(valor)) erro()
    if (is.character(valor)) {
      if (!grepl("\\A[0-9]+\\z", valor, perl = TRUE)) erro()
      valor <- suppressWarnings(as.numeric(valor))
    } else if (!is.numeric(valor)) {
      erro()
    }
    # Limite técnico de representação exata, não limite epidemiológico de idade.
    if (!is.finite(valor) || valor < 0 || valor != floor(valor) || valor > 2^53 - 1) erro()
    valor
  }
  idade_min <- validar(idade_min, "idade_min")
  idade_max <- validar(idade_max, "idade_max")
  faixas <- list("18-39" = c(18, 39), "40-59" = c(40, 59), "60+" = c(60, Inf))
  # Faixas não reconhecidas continuam sem efeito, como no contrato legado.
  if (faixa %in% names(faixas)) {
    if (!is.null(idade_min) || !is.null(idade_max)) {
      stop("Não combine --faixa específica com --idade_min ou --idade_max.")
    }
    idade_min <- faixas[[faixa]][1L]
    idade_max <- if (is.finite(faixas[[faixa]][2L])) faixas[[faixa]][2L] else NULL
  }
  if (!is.null(idade_min) && !is.null(idade_max) && idade_min > idade_max) {
    stop("idade_min não pode ser maior que idade_max.")
  }
  list(idade_min = idade_min, idade_max = idade_max)
}

# Não faz junções: exige uma correspondência bijetiva pelos identificadores
# temporários e restaura a ordem original antes de anexar as idades preservadas.
associar_idades_sim <- function(dados, ids_originais, idades) {
  ids_processados <- dados[[".import_mds_registro_id"]]
  if (nrow(dados) != length(ids_originais) || nrow(idades) != length(ids_originais) ||
      anyNA(ids_originais) || anyDuplicated(ids_originais) ||
      !is.character(ids_processados) || anyNA(ids_processados) ||
      anyDuplicated(ids_processados) || !setequal(ids_processados, ids_originais)) {
    stop("Não foi possível garantir a correspondência entre registros brutos e processados do SIM.")
  }
  dados <- dados[match(ids_originais, ids_processados), , drop = FALSE]
  for (nome in names(idades)) dados[[nome]] <- idades[[nome]]
  dados
}

processar_dados_sim <- function(dados_brutos) {
  if (!is.data.frame(dados_brutos) || !"IDADE" %in% names(dados_brutos)) {
    stop("Dados brutos do SIM devem conter a coluna IDADE original.")
  }
  idades <- normalizar_idade_sim(dados_brutos$IDADE)
  reservadas <- c(".import_mds_registro_id", names(idades))
  if (any(reservadas %in% names(dados_brutos))) {
    stop("Dados brutos do SIM contêm colunas reservadas para associação etária.")
  }
  ids <- as.character(seq_len(nrow(dados_brutos)))
  dados_trabalho <- as.data.frame(dados_brutos)
  dados_trabalho$.import_mds_registro_id <- ids
  dados <- microdatasus::process_sim(dados_trabalho)
  associar_idades_sim(dados, ids, idades) |>
    dplyr::mutate(
      data_evento = as.Date(DTOBITO),
      cid_valor = toupper(CAUSABAS),
      IDADE_NUM = as.numeric(IDADEanos)
    )
}

filtrar_dados_sim <- function(dados, sexo = "ALL", raca = "ALL",
                              faixa = "ALL", cid = "ALL",
                              idade_min = NULL, idade_max = NULL) {
  limites <- resolver_limites_idade_sim(idade_min, idade_max, faixa)
  entrada <- nrow(dados)
  # A exclusão de datas ausentes permanece anterior aos filtros epidemiológicos.
  dados <- dplyr::filter(dados, !is.na(data_evento))
  ativo <- !is.null(limites$idade_min) || !is.null(limites$idade_max)
  valida <- dados$idade_situacao == "valida" & !is.na(dados$idade_anos_completos)
  manter <- rep(TRUE, nrow(dados))
  if (ativo) {
    manter <- valida
    if (!is.null(limites$idade_min)) {
      manter <- manter & !is.na(dados$idade_anos_completos) &
        dados$idade_anos_completos >= limites$idade_min
    }
    if (!is.null(limites$idade_max)) {
      manter <- manter & !is.na(dados$idade_anos_completos) &
        dados$idade_anos_completos <= limites$idade_max
    }
  }
  # Contagens referentes à etapa etária, após a exclusão de datas ausentes.
  contagens <- list(
    filtro_ativo = ativo, idade_min = limites$idade_min, idade_max = limites$idade_max,
    entrada = entrada, excluidos_sem_data = entrada - nrow(dados),
    antes_filtro_etario = nrow(dados),
    idades_validas = sum(valida),
    idades_desconhecidas = sum(dados$idade_situacao == "desconhecida"),
    idades_invalidas = sum(dados$idade_situacao == "invalida"),
    excluidos_desconhecidos = if (ativo) sum(dados$idade_situacao == "desconhecida") else 0L,
    excluidos_invalidos = if (ativo) sum(dados$idade_situacao == "invalida") else 0L,
    excluidos_fora_limites = sum(valida & !manter),
    apos_filtro_etario = sum(manter)
  )
  dados <- dados[manter, , drop = FALSE]

  if (sexo != "ALL") {
    dados <- dplyr::filter(dados, SEXO == sexo)
  }

  if (raca != "ALL") {
    dados <- dplyr::filter(dados, RACACOR == raca)
  }

  if (cid != "ALL") {
    dados <- dplyr::filter(dados, startsWith(cid_valor, cid))
  }

  contagens$apos_demais_filtros <- nrow(dados)
  attr(dados, "contagens_etarias") <- contagens
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
                                   faixa = "ALL", cid = "ALL",
                                   idade_min = NULL, idade_max = NULL) {
  limites <- resolver_limites_idade_sim(idade_min, idade_max, faixa)
  dados <- processar_dados_sim(dados_brutos) |>
    filtrar_dados_sim(
      sexo = sexo, raca = raca, cid = cid,
      idade_min = limites$idade_min, idade_max = limites$idade_max
    )
  resultado <- selecionar_colunas_sim(dados)
  attr(resultado, "contagens_etarias") <- attr(dados, "contagens_etarias")
  resultado
}
