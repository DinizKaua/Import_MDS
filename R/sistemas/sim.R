# Regras legadas do SIM, preservadas durante a separação do orquestrador.
# Cada função recebe dados em memória; este módulo não realiza coleta ou exportação.

# Validação da DTOBITO bruta, executada antes de process_sim().
# Referência do formato: microdatasus 3.0.0, bloco DTOBITO de R/process_sim.R:
# https://github.com/rfsaldanha/microdatasus/blob/7109ec2c42cf674ba453e0d7a20d2f464890b543/R/process_sim.R
# Exige oito dígitos ASCII DDMMAAAA, calendário e conversão reversível.
# Retorna uma linha por entrada: original (character), validada (Date), situação
# e motivo (character). Entradas ausentes/inválidas têm data validada NA.
# Apenas NA, vazio e espaços ASCII isolados são ausentes; tabs e sentinelas
# não documentadas não recebem interpretação especial. O original é preservado.
# Usa o calendário gregoriano proléptico de Date, inclusive sua convenção de ano
# 0000, sem impor plausibilidade epidemiológica. %Y pode omitir zeros em anos
# anteriores a 1000; a ida e volta recompõe explicitamente os quatro dígitos.
validar_data_obito_sim <- function(codigos) {
  if (!is.character(codigos) || is.object(codigos) || !is.null(dim(codigos))) {
    stop("codigos deve ser um vetor de caracteres, com NA_character_ para ausentes.")
  }

  quantidade <- length(codigos)
  resultado <- data.frame(
    data_obito_original = unname(codigos),
    data_obito_validada = as.Date(rep(NA_character_, quantidade)),
    data_obito_situacao = rep("invalida", quantidade),
    data_obito_motivo = rep("formato_invalido", quantidade),
    stringsAsFactors = FALSE
  )
  na <- is.na(codigos)
  vazio <- !na & codigos == ""
  espacos <- !na & grepl("\\A +\\z", codigos, perl = TRUE)
  resultado$data_obito_situacao[na | vazio | espacos] <- "ausente"
  resultado$data_obito_motivo[na] <- "ausente_na"
  resultado$data_obito_motivo[vazio] <- "ausente_vazio"
  resultado$data_obito_motivo[espacos] <- "ausente_espacos"

  indices <- which(!na & grepl("\\A[0-9]{8}\\z", codigos, perl = TRUE))
  datas <- as.Date(codigos[indices], format = "%d%m%Y")
  resultado$data_obito_motivo[indices] <- "data_calendario_invalida"
  interpretaveis <- which(!is.na(datas))
  if (length(interpretaveis)) {
    datas_interpretadas <- datas[interpretaveis]
    retorno <- sprintf(
      "%02d%02d%04d",
      as.integer(format(datas_interpretadas, "%d")),
      as.integer(format(datas_interpretadas, "%m")),
      as.integer(format(datas_interpretadas, "%Y"))
    )
    resultado$data_obito_motivo[indices[interpretaveis]] <- "conversao_nao_reversivel"
    correspondem <- retorno == codigos[indices[interpretaveis]]
    validos <- indices[interpretaveis[correspondem]]
    resultado$data_obito_validada[validos] <- datas_interpretadas[correspondem]
    resultado$data_obito_situacao[validos] <- "valida"
    resultado$data_obito_motivo[validos] <- "codigo_valido"
  }
  resultado
}

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

# Converte somente a naturalidade, sem junções com os microdados. A tabela
# oficial é lida sem modificações. Repetições idênticas na referência produzem
# uma tradução; descrições distintas produzem NA, sem escolher a primeira.
# NA/vazio/espaços são ausências; códigos são comparados sem limpeza ou coerção.
converter_naturalidade_sim <- function(codigos, tabela = microdatasus::tabNaturalidade) {
  if (!is.character(codigos) || is.object(codigos) || !is.null(dim(codigos))) {
    stop("NATURAL deve ser um vetor de caracteres, preservando os códigos originais.")
  }
  if (!is.data.frame(tabela) || anyDuplicated(names(tabela)) ||
      !all(c("cod", "nome") %in% names(tabela)) ||
      !is.character(tabela$cod) || is.object(tabela$cod) || !is.null(dim(tabela$cod)) ||
      !is.character(tabela$nome) || is.object(tabela$nome) || !is.null(dim(tabela$nome))) {
    stop("Tabela de naturalidade deve conter cod e nome como colunas de caracteres.")
  }
  ausente <- function(x) is.na(x) | x == "" | grepl("\\A +\\z", x, perl = TRUE)
  chave_ausente <- ausente(tabela$cod)
  descricao_ausente <- ausente(tabela$nome)
  chaves <- tabela$cod[!chave_ausente]
  chaves <- chaves[!duplicated(chaves)] # Apenas a referência, nunca os microdados.
  mapa <- data.frame(codigo = chaves, descricao = rep(NA_character_, length(chaves)),
                     situacao = rep("sem_correspondencia", length(chaves)),
                     motivo = rep("descricao_ausente_na_tabela", length(chaves)),
                     stringsAsFactors = FALSE)
  repetidas <- identicas <- conflitantes <- 0L
  for (i in seq_along(chaves)) {
    linhas <- which(!chave_ausente & tabela$cod == chaves[i])
    descricoes <- tabela$nome[linhas[!descricao_ausente[linhas]]]
    descricoes <- descricoes[!duplicated(descricoes)]
    repetidas <- repetidas + as.integer(length(linhas) > 1L)
    if (length(descricoes) > 1L) {
      mapa$situacao[i] <- "ambigua"
      mapa$motivo[i] <- "descricoes_conflitantes"
      conflitantes <- conflitantes + 1L
    } else if (length(descricoes) == 1L) {
      # Mesma normalização Unicode aplicada ao texto pelo processador oficial.
      mapa$descricao[i] <- stringi::stri_unescape_unicode(descricoes)
      mapa$situacao[i] <- "inequivoca"
      mapa$motivo[i] <- if (any(descricao_ausente[linhas])) {
        "descricao_unica_com_ausencias_na_tabela"
      } else if (length(linhas) > 1L) {
        identicas <- identicas + 1L
        "descricoes_identicas_repetidas"
      } else "correspondencia_unica"
    }
  }
  if (anyNA(mapa$descricao[mapa$situacao == "inequivoca"])) {
    stop("Não foi possível normalizar uma descrição inequívoca de naturalidade.")
  }
  resultado <- data.frame(
    naturalidade_codigo_original = unname(codigos),
    naturalidade_descricao = rep(NA_character_, length(codigos)),
    naturalidade_situacao = rep("sem_correspondencia", length(codigos)),
    naturalidade_motivo = rep("codigo_nao_encontrado", length(codigos)),
    stringsAsFactors = FALSE
  )
  falta <- ausente(codigos)
  posicoes <- match(codigos, mapa$codigo)
  encontrados <- which(!falta & !is.na(posicoes))
  resultado$naturalidade_descricao[encontrados] <- mapa$descricao[posicoes[encontrados]]
  resultado$naturalidade_situacao[encontrados] <- mapa$situacao[posicoes[encontrados]]
  resultado$naturalidade_motivo[encontrados] <- mapa$motivo[posicoes[encontrados]]
  resultado$naturalidade_situacao[falta] <- "ausente"
  resultado$naturalidade_motivo[is.na(codigos)] <- "codigo_ausente_na"
  resultado$naturalidade_motivo[!is.na(codigos) & codigos == ""] <- "codigo_ausente_vazio"
  resultado$naturalidade_motivo[!is.na(codigos) & grepl("\\A +\\z", codigos, perl = TRUE)] <- "codigo_ausente_espacos"
  attr(resultado, "diagnostico_tabela") <- list(
    linhas = nrow(tabela), chaves_ausentes = sum(chave_ausente),
    descricoes_ausentes = sum(descricao_ausente), codigos = nrow(mapa),
    chaves_repetidas = repetidas, chaves_conflitantes = conflitantes,
    chaves_com_repeticoes_identicas = identicas
  )
  resultado
}

contar_naturalidade_sim <- function(dados) {
  list(total = nrow(dados),
       inequivocas = sum(dados$naturalidade_situacao == "inequivoca"),
       ambiguas = sum(dados$naturalidade_situacao == "ambigua"),
       sem_correspondencia = sum(dados$naturalidade_situacao == "sem_correspondencia"),
       ausentes = sum(dados$naturalidade_situacao == "ausente"))
}

# Não faz junções: exige uma correspondência bijetiva pelos identificadores
# temporários e restaura a ordem original antes de anexar idades e datas brutas
# validadas. As duas funções de validação preservam a ordem e a cardinalidade.
associar_validacoes_sim <- function(dados, ids_originais, validacoes) {
  ids_processados <- dados[[".import_mds_registro_id"]]
  if (nrow(dados) != length(ids_originais) || nrow(validacoes) != length(ids_originais) ||
      anyNA(ids_originais) || anyDuplicated(ids_originais) ||
      !is.character(ids_processados) || anyNA(ids_processados) ||
      anyDuplicated(ids_processados) || !setequal(ids_processados, ids_originais)) {
    stop("Não foi possível garantir a correspondência entre registros brutos e processados do SIM.")
  }
  dados <- dados[match(ids_originais, ids_processados), , drop = FALSE]
  for (nome in names(validacoes)) dados[[nome]] <- validacoes[[nome]]
  dados
}

processar_dados_sim <- function(dados_brutos) {
  if (!is.data.frame(dados_brutos) || !"IDADE" %in% names(dados_brutos)) {
    stop("Dados brutos do SIM devem conter a coluna IDADE original.")
  }
  if (!"DTOBITO" %in% names(dados_brutos)) {
    stop("Dados brutos do SIM devem conter a coluna DTOBITO original.")
  }
  if (!"NATURAL" %in% names(dados_brutos)) {
    stop("Dados brutos do SIM devem conter a coluna NATURAL original.")
  }
  idades <- normalizar_idade_sim(dados_brutos$IDADE)
  datas <- validar_data_obito_sim(dados_brutos$DTOBITO)
  naturalidades <- converter_naturalidade_sim(dados_brutos$NATURAL)
  validacoes <- cbind(idades, datas, naturalidades)
  reservadas <- c(".import_mds_registro_id", names(validacoes))
  if (any(reservadas %in% names(dados_brutos))) {
    stop("Dados brutos do SIM contêm colunas reservadas para associação de registros.")
  }
  ids <- as.character(seq_len(nrow(dados_brutos)))
  dados_trabalho <- as.data.frame(dados_brutos)
  dados_trabalho$.import_mds_registro_id <- ids
  # NATURAL só é referenciada pelo pacote em sua junção de naturalidade.
  # Retirá-la desta cópia impede a expansão sem mudar o restante do processador.
  dados_trabalho$NATURAL <- NULL
  dados <- microdatasus::process_sim(dados_trabalho)
  associar_validacoes_sim(dados, ids, validacoes) |>
    dplyr::mutate(
      NATURAL = naturalidade_descricao,
      data_evento = data_obito_validada,
      cid_valor = toupper(CAUSABAS),
      IDADE_NUM = as.numeric(IDADEanos)
    )
}

filtrar_dados_sim <- function(dados, sexo = "ALL", raca = "ALL",
                              faixa = "ALL", cid = "ALL",
                              idade_min = NULL, idade_max = NULL) {
  limites <- resolver_limites_idade_sim(idade_min, idade_max, faixa)
  entrada <- nrow(dados)
  contagens_naturalidade <- list(antes_filtros = contar_naturalidade_sim(dados))
  # Categorias de data anteriores a qualquer filtro. A validação não exclui
  # registros; datas ausentes/inválidas seguem para todos os filtros existentes.
  contagens_datas <- list(
    entrada = entrada,
    datas_validas = sum(dados$data_obito_situacao == "valida"),
    datas_ausentes = sum(dados$data_obito_situacao == "ausente"),
    datas_invalidas = sum(dados$data_obito_situacao == "invalida"),
    preservados_apos_validacao = entrada,
    excluidos_por_data = 0L
  )
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
  # Etapa etária sobre todos os registros validados. O campo legado
  # excluidos_sem_data continua contando exclusões por data: agora sempre zero.
  contagens <- list(
    filtro_ativo = ativo, idade_min = limites$idade_min, idade_max = limites$idade_max,
    entrada = entrada, excluidos_sem_data = 0L,
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
  contagens_datas$apos_filtro_etario <- nrow(dados)
  contagens_naturalidade$apos_filtro_etario <- nrow(dados)

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
  contagens_datas$apos_demais_filtros <- nrow(dados)
  contagens_naturalidade$apos_demais_filtros <- contar_naturalidade_sim(dados)
  attr(dados, "contagens_etarias") <- contagens
  attr(dados, "contagens_datas") <- contagens_datas
  attr(dados, "contagens_naturalidade") <- contagens_naturalidade
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
  contagens_datas <- attr(dados, "contagens_datas")
  contagens_datas$total_final_exportavel <- nrow(resultado)
  attr(resultado, "contagens_datas") <- contagens_datas
  attr(resultado, "contagens_naturalidade") <- attr(dados, "contagens_naturalidade")
  # A posição é calculada APÓS os filtros, inclusive para duplicatas legítimas.
  # Estes atributos não são persistidos no CSV legado. A publicação consistente
  # de principal + auxiliar ainda precisa ser resolvida antes de uso em produção.
  attr(resultado, "auditoria_naturalidade") <- data.frame(
    posicao_csv = seq_len(nrow(dados)), registro_id = dados$.import_mds_registro_id,
    naturalidade_codigo_original = dados$naturalidade_codigo_original,
    naturalidade_descricao = dados$naturalidade_descricao,
    naturalidade_situacao = dados$naturalidade_situacao,
    naturalidade_motivo = dados$naturalidade_motivo,
    stringsAsFactors = FALSE
  )
  resultado
}
