# TZ=UTC Rscript --vanilla tests/test_sim_naturalidade.R
# Referências do pacote e microdados sintéticos em memória; nenhum download.
local({
  suppressPackageStartupMessages({ library(microdatasus); library(dplyr) })
  stopifnot(as.character(packageVersion("microdatasus")) == "3.0.0")
  modulo <- new.env(parent = globalenv())
  sys.source("R/comum/cid.R", envir = modulo)
  sys.source("R/sistemas/sim.R", envir = modulo)
  converter <- modulo$converter_naturalidade_sim
  erro <- function(expr) tryCatch({force(expr); NULL}, error = function(e) conditionMessage(e))
  sem_atributos <- function(x) {
    for (nome in c("contagens_etarias", "contagens_datas", "contagens_naturalidade", "auditoria_naturalidade")) attr(x, nome) <- NULL
    x
  }

  tabela <- data.frame(
    cod = c("001", "002", "002", "003", "003", "004", NA, "005", "006", "006", "", "  "),
    nome = c("Descrição única", "Conflito A", "Conflito B", "Repetida", "Repetida",
             NA, "Chave ausente", "", "Disponível", NA, "Chave vazia", "Chave em espaços"),
    stringsAsFactors = FALSE
  )
  codigos <- c("001", "002", "003", "404", NA, "", "   ", "004", "005", "006", "001", "1", "001 ")
  esperado <- data.frame(
    naturalidade_codigo_original = codigos,
    naturalidade_descricao = c("Descrição única", NA, "Repetida", NA, NA, NA, NA, NA, NA, "Disponível", "Descrição única", NA, NA),
    naturalidade_situacao = c("inequivoca", "ambigua", "inequivoca", "sem_correspondencia", rep("ausente", 3L),
                             "sem_correspondencia", "sem_correspondencia", "inequivoca", "inequivoca", "sem_correspondencia", "sem_correspondencia"),
    naturalidade_motivo = c("correspondencia_unica", "descricoes_conflitantes", "descricoes_identicas_repetidas", "codigo_nao_encontrado",
                           "codigo_ausente_na", "codigo_ausente_vazio", "codigo_ausente_espacos", "descricao_ausente_na_tabela",
                           "descricao_ausente_na_tabela", "descricao_unica_com_ausencias_na_tabela", "correspondencia_unica",
                           "codigo_nao_encontrado", "codigo_nao_encontrado"), stringsAsFactors = FALSE
  )
  diagnostico <- list(linhas = 12L, chaves_ausentes = 3L, descricoes_ausentes = 3L,
                     codigos = 6L, chaves_repetidas = 3L, chaves_conflitantes = 1L,
                     chaves_com_repeticoes_identicas = 1L)
  attr(esperado, "diagnostico_tabela") <- diagnostico
  antes <- serialize(codigos, NULL)
  antes_tabela <- serialize(tabela, NULL)
  stopifnot(identical(converter(codigos, tabela), esperado),
            identical(serialize(codigos, NULL), antes), identical(serialize(tabela, NULL), antes_tabela))
  # Nem a ordem da referência nem a entrada alteram a classificação.
  stopifnot(identical(converter(codigos, tabela[12:1, ]), esperado))
  invertido <- esperado[13:1, ]; rownames(invertido) <- NULL
  attr(invertido, "diagnostico_tabela") <- diagnostico
  stopifnot(identical(converter(rev(codigos), tabela), invertido))
  vazio <- esperado[FALSE, ]; rownames(vazio) <- NULL
  attr(vazio, "diagnostico_tabela") <- diagnostico
  stopifnot(identical(converter(character(), tabela), vazio))
  stopifnot(identical(converter("001", data.frame(cod = "001", nome = "Maranh\\u00e3o"))$naturalidade_descricao, "Maranhão"))
  cat("OK: códigos, zeros, ausências, conflitos, repetições idênticas, tabela incompleta e Unicode; ordem e cardinalidade\n")

  for (entrada in list(1, NA, factor("001"), list("001"), matrix("001"), NULL)) {
    stopifnot(!is.null(erro(converter(entrada, tabela))))
  }
  for (ref in list(data.frame(codigo = "001", nome = "X"), data.frame(cod = 1, nome = "X"),
                   data.frame(cod = "001", nome = factor("X")), data.frame(cod = "001", nome = 1), NULL)) {
    stopifnot(identical(erro(converter("001", ref)),
                        "Tabela de naturalidade deve conter cod e nome como colunas de caracteres."))
  }
  referencia_dt <- data.table::as.data.table(tabela)
  antes_dt <- serialize(referencia_dt, NULL)
  stopifnot(identical(converter(codigos, referencia_dt), esperado), identical(serialize(referencia_dt, NULL), antes_dt))
  cat("OK: esquema/tipos da referência verificados e data.table auxiliar preservada\n")

  oficial <- microdatasus::tabNaturalidade
  oficial_antes <- unserialize(serialize(oficial, NULL))
  freq <- table(oficial$cod)
  ambiguos <- names(freq)[freq > 1L]
  stopifnot(identical(ambiguos, c("44", "73", "81")), all(freq[ambiguos] == 2L))
  padronizados <- converter(c("44", "73", "81", "44", "044", "44 ", " 73", "081", "81 "))
  stopifnot(identical(padronizados$naturalidade_codigo_original,
                     c("44", "73", "81", "44", "044", "44 ", " 73", "081", "81 ")),
    identical(padronizados$naturalidade_descricao,
      c("CAMBOJA / LAOS", "IRLANDA", "ILHAS FALKLAND (MALVINAS)", "CAMBOJA / LAOS", rep(NA_character_, 5L))),
    identical(padronizados$naturalidade_situacao,
      c("ambigua", "inequivoca", "inequivoca", "ambigua", rep("sem_correspondencia", 5L))),
    identical(padronizados$naturalidade_motivo,
      c("codigo_corresponde_a_dois_paises_distintos", rep("equivalencia_nomenclatura_geografica", 2L),
        "codigo_corresponde_a_dois_paises_distintos", rep("codigo_nao_encontrado", 5L))))
  # A regra exata não deve atingir nem mesmo códigos semelhantes presentes na referência.
  similares <- data.frame(cod = c("044", "73 ", "081"), nome = c("Texto A", "Texto B", "Texto C"))
  stopifnot(identical(converter(similares$cod, similares)$naturalidade_descricao, similares$nome))
  cat("OK: três padronizações explícitas, 44 ambíguo, 73/81 inequívocos, zeros e espaços sem coerção\n")
  chaves_inequivocas <- names(freq)[freq == 1L]
  convertido <- converter(chaves_inequivocas)
  antigo <- microdatasus::process_sim(data.frame(NATURAL = chaves_inequivocas))
  stopifnot(identical(convertido$naturalidade_descricao, antigo$NATURAL),
            all(convertido$naturalidade_situacao == "inequivoca"))
  cat("OK: todas as chaves únicas instaladas mantêm exatamente as descrições oficiais\n")

  entrada <- data.frame(
    NATURAL = c(ambiguos, "821"), IDADE = c("418", "500", "417", "460"),
    DTOBITO = c("01012000", NA, "01012000xyz", "29022000"),
    DTNASC = rep("01011980", 4L), DTATESTADO = rep("01032000", 4L),
    SEXO = c("1", "1", "1", "2"), RACACOR = c("1", "1", "1", "4"),
    CAUSABAS = c("I21", "I210", "C50", "I219"), CODESTAB = sprintf("%07d", 1:4),
    CODMUNRES = rep("211130", 4L), CODMUNNATU = rep("211130", 4L),
    ESTCIV = rep("1", 4L), LOCOCOR = rep("1", 4L), ASSISTMED = rep("1", 4L),
    OCUP = rep("000000", 4L), OCUPMAE = rep("000000", 4L), stringsAsFactors = FALSE
  )
  antes <- serialize(entrada, NULL)
  legado <- microdatasus::process_sim(entrada)
  novo <- modulo$processar_dados_sim(entrada)
  stopifnot(nrow(legado) == 7L, nrow(novo) == 4L,
            identical(novo$.import_mds_registro_id, as.character(1:4)),
            identical(novo$naturalidade_codigo_original, entrada$NATURAL),
            identical(novo$naturalidade_situacao, c("ambigua", rep("inequivoca", 3L))),
            identical(novo$naturalidade_motivo, c("codigo_corresponde_a_dois_paises_distintos",
              rep("equivalencia_nomenclatura_geografica", 2L), "correspondencia_unica")),
            identical(novo$NATURAL[1:3], c("CAMBOJA / LAOS", "IRLANDA", "ILHAS FALKLAND (MALVINAS)")),
            identical(novo$NATURAL[4L], converter("821")$naturalidade_descricao),
            identical(novo$idade_codigo_original, entrada$IDADE),
            identical(novo$idade_anos_completos, c(18L, 100L, 17L, 60L)),
            identical(novo$data_obito_original, entrada$DTOBITO),
            identical(novo$data_evento, as.Date(c("2000-01-01", NA, NA, "2000-02-29"))),
            identical(serialize(entrada, NULL), antes))
  cat("OK: reprodução da auditoria: processador oficial 4→7; processamento corrigido 4→4 com idades/datas vinculadas\n")

  # Verifica a entrada/saída oficial sem NATURAL, incluindo ocupações e município.
  sem_natural <- microdatasus::process_sim(entrada[, names(entrada) != "NATURAL"])
  stopifnot(identical(novo[, names(sem_natural)], sem_natural))
  isolado <- new.env(parent = globalenv())
  sys.source("R/comum/cid.R", envir = isolado)
  sys.source("R/sistemas/sim.R", envir = isolado)
  isolado$associar_validacoes_sim <- function(dados, ids_originais, validacoes) {
    stopifnot(!"NATURAL" %in% names(dados))
    modulo$associar_validacoes_sim(dados, ids_originais, validacoes)
  }
  stopifnot(identical(isolado$processar_dados_sim(entrada), novo))
  cat("OK: junção de NATURAL não executada; demais transformações oficiais equivalentes\n")

  duplicadas <- entrada[c(1L, 2L, 1L, 4L, 3L, 2L), ]
  antes_duplicadas <- serialize(duplicadas, NULL)
  saida <- modulo$preparar_exportacao_sim(duplicadas, idade_min = 18, cid = "I21")
  colunas <- c("IDADE", "DATA_DE_NASCIMENTO", "ESTADO_CIVIL", "SEXO", "RACA_COR",
               "LOCAL_OBITO", "ESTABELECIMENTO", "DATA", "ESTADO_RESIDENCIA",
               "MUNICIPIO_RESIDENCIA", "ESTADO_NATURALIDADE", "MUNICIPIO_NATURALIDADE",
               "ASSISTENCIA_MEDICA", "DOENCA")
  stopifnot(nrow(saida) == 5L, identical(names(saida), colunas),
            identical(saida$ESTABELECIMENTO, c("0000001", "0000002", "0000001", "0000004", "0000002")),
            identical(saida$IDADE, c("18", "100", "18", "60", "100")),
            identical(saida$DOENCA, c("I21", "I210", "I21", "I219", "I210")),
            identical(saida$DATA, as.Date(c("2000-01-01", NA, "2000-01-01", "2000-02-29", NA))),
            identical(serialize(duplicadas, NULL), antes_duplicadas))
  auditoria <- attr(saida, "auditoria_naturalidade")
  esperado_auditoria <- data.frame(
    posicao_csv = 1:5, registro_id = c("1", "2", "3", "4", "6"),
    naturalidade_codigo_original = entrada$NATURAL[c(1L, 2L, 1L, 4L, 2L)],
    naturalidade_descricao = c("CAMBOJA / LAOS", "IRLANDA", "CAMBOJA / LAOS", converter("821")$naturalidade_descricao, "IRLANDA"),
    naturalidade_situacao = c("ambigua", "inequivoca", "ambigua", "inequivoca", "inequivoca"),
    naturalidade_motivo = c("codigo_corresponde_a_dois_paises_distintos", "equivalencia_nomenclatura_geografica",
      "codigo_corresponde_a_dois_paises_distintos", "correspondencia_unica", "equivalencia_nomenclatura_geografica"),
    stringsAsFactors = FALSE
  )
  stopifnot(identical(auditoria, esperado_auditoria),
            identical(saida$ESTADO_NATURALIDADE, auditoria$naturalidade_descricao),
            identical(attr(saida, "contagens_naturalidade"), list(
              antes_filtros = list(total = 6L, inequivocas = 4L, ambiguas = 2L, sem_correspondencia = 0L, ausentes = 0L),
              apos_filtro_etario = 5L,
              apos_demais_filtros = list(total = 5L, inequivocas = 3L, ambiguas = 2L, sem_correspondencia = 0L, ausentes = 0L))))
  feminina <- modulo$preparar_exportacao_sim(duplicadas, sexo = "Feminino", raca = "Parda", cid = "I21")
  stopifnot(nrow(feminina) == 1L, identical(feminina$ESTABELECIMENTO, "0000004"),
            identical(attr(feminina, "auditoria_naturalidade")$posicao_csv, 1L),
            identical(attr(feminina, "auditoria_naturalidade")$registro_id, "4"))
  vazio <- modulo$preparar_exportacao_sim(duplicadas, cid = "Z999")
  stopifnot(nrow(vazio) == 0L, identical(names(vazio), colunas), nrow(attr(vazio, "auditoria_naturalidade")) == 0L)
  cat("OK: filtros, duplicatas legítimas, 14 colunas, motivos e posições ordinais recalculadas após seleção\n")

  distintas <- entrada[rep(4L, 5L), ]
  distintas$NATURAL <- c("821", ambiguos[1L], "__sem_mapa__", NA, "")
  saida_distintas <- modulo$preparar_exportacao_sim(distintas)
  esperado_contagens <- list(total = 5L, inequivocas = 1L, ambiguas = 1L, sem_correspondencia = 1L, ausentes = 2L)
  contagens <- attr(saida_distintas, "contagens_naturalidade")
  stopifnot(identical(contagens$antes_filtros, esperado_contagens),
            identical(contagens$apos_demais_filtros, esperado_contagens))
  for (c in list(contagens$antes_filtros, contagens$apos_demais_filtros)) {
    stopifnot(c$total == c$inequivocas + c$ambiguas + c$sem_correspondencia + c$ausentes)
  }
  cat("OK: contagens das quatro situações reconciliadas antes e após os filtros\n")

  tab <- data.table::as.data.table(duplicadas)
  antes_tab <- serialize(tab, NULL)
  stopifnot(identical(modulo$preparar_exportacao_sim(tab, idade_min = 18, cid = "I21"), saida),
            identical(serialize(tab, NULL), antes_tab))
  invertida <- modulo$preparar_exportacao_sim(duplicadas[6:1, ], idade_min = 18, cid = "I21")
  stopifnot(identical(sem_atributos(invertida), sem_atributos(saida[5:1, ])),
            identical(attr(invertida, "auditoria_naturalidade")$posicao_csv, 1:5))
  cat("OK: data.table de entrada e ordem original preservados\n")

  validacoes <- cbind(modulo$normalizar_idade_sim(entrada$IDADE), modulo$validar_data_obito_sim(entrada$DTOBITO), converter(entrada$NATURAL))
  stopifnot(identical(modulo$associar_validacoes_sim(novo[4:1, ], as.character(1:4), validacoes), novo))
  for (tipo in c("perda", "duplicacao", "id_duplicado", "id_inesperado", "id_ausente", "sem_id")) {
    corrompido <- novo
    if (tipo == "perda") corrompido <- corrompido[-1L, ]
    if (tipo == "duplicacao") corrompido <- corrompido[c(1:4, 1L), ]
    if (tipo == "id_duplicado") corrompido$.import_mds_registro_id[2L] <- "1"
    if (tipo == "id_inesperado") corrompido$.import_mds_registro_id[1L] <- "outro"
    if (tipo == "id_ausente") corrompido$.import_mds_registro_id[1L] <- NA_character_
    if (tipo == "sem_id") corrompido$.import_mds_registro_id <- NULL
    stopifnot(identical(erro(modulo$associar_validacoes_sim(corrompido, as.character(1:4), validacoes)),
                        "Não foi possível garantir a correspondência entre registros brutos e processados do SIM."))
  }
  stopifnot(identical(erro(modulo$processar_dados_sim(entrada[, names(entrada) != "NATURAL"])),
                      "Dados brutos do SIM devem conter a coluna NATURAL original."),
            identical(microdatasus::tabNaturalidade, oficial_antes))
  cat("OK: integridade continua rejeitando corrupção real; referência oficial não foi modificada\n")
  cat("PASSOU: conversão controlada, cenário 4→7 corrigido para 4→4, rastreabilidade interna, regressões e integridade; sem persistência auxiliar ou downloads.\n")
})
