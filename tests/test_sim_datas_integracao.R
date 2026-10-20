# Executar da raiz: TZ=UTC Rscript --vanilla tests/test_sim_datas_integracao.R
# Somente dados sintéticos; CSVs de teste em diretório temporário próprio.
local({
  suppressPackageStartupMessages({ library(microdatasus); library(dplyr) })
  stopifnot(as.character(packageVersion("microdatasus")) == "3.0.0")
  modulo <- new.env(parent = globalenv())
  sys.source("R/sistemas/sim.R", envir = modulo)
  preparar <- modulo$preparar_exportacao_sim
  sem_contagens <- function(x) {
    attr(x, "contagens_etarias") <- NULL
    attr(x, "contagens_datas") <- NULL
    attr(x, "contagens_naturalidade") <- NULL
    attr(x, "auditoria_naturalidade") <- NULL
    x
  }
  erro <- function(expr) tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))

  codigos <- c("29022020", NA_character_, "", "   ", "31022020", "01012020xyz",
               "1012020", "010120", "2020-02-29", "29/02/2020", "28022021",
               "31122020", "01012021", "32132020", NA_character_, "01012020")
  entrada <- data.frame(
    DTOBITO = codigos, DTNASC = rep("01012002", 16L), DTATESTADO = rep("02032020", 16L),
    IDADE = c("418", "420", "306", "999", "460", "417", "500", "501",
              "418", "999", "417", "400", "460", "600", "420", "418"),
    ESTCIV = rep("1", 16L),
    SEXO = c("1", "1", "2", "1", "1", "1", "2", "1", "1", "1", "2", "2", "2", "1", "1", "0"),
    RACACOR = c("1", "1", "4", "1", "1", "1", "4", "1", "1", "1", "4", "4", "4", "1", "1", NA),
    CAUSABAS = c("I21", "i210", "I21", "I21", "I219", "I21", "I21", "C50",
                 "I21", NA, "I21", "C50", "I210", "I21", "i210", NA),
    LOCOCOR = rep("1", 16L), CODESTAB = sprintf("%07d", c(1:14, 2L, 16L)),
    CODMUNRES = rep("211130", 16L), NATURAL = rep("821", 16L),
    CODMUNNATU = rep("211130", 16L), ASSISTMED = rep("1", 16L),
    stringsAsFactors = FALSE
  )
  stopifnot(identical(as.list(entrada[2L, ]), as.list(entrada[15L, ])))
  colunas <- c("IDADE", "DATA_DE_NASCIMENTO", "ESTADO_CIVIL", "SEXO", "RACA_COR",
               "LOCAL_OBITO", "ESTABELECIMENTO", "DATA", "ESTADO_RESIDENCIA",
               "MUNICIPIO_RESIDENCIA", "ESTADO_NATURALIDADE", "MUNICIPIO_NATURALIDADE",
               "ASSISTENCIA_MEDICA", "DOENCA")
  datas_esperadas <- as.Date(c("2020-02-29", rep(NA_character_, 9L),
                              "2021-02-28", "2020-12-31", "2021-01-01", NA, NA, "2020-01-01"))
  situacoes <- c("valida", "ausente", "ausente", "ausente", rep("invalida", 6L),
                 "valida", "valida", "valida", "invalida", "ausente", "valida")
  motivos <- c("codigo_valido", "ausente_na", "ausente_vazio", "ausente_espacos",
               "data_calendario_invalida", rep("formato_invalido", 5L),
               "codigo_valido", "codigo_valido", "codigo_valido", "data_calendario_invalida",
               "ausente_na", "codigo_valido")
  anos <- c(18L, 20L, 0L, NA_integer_, 60L, 17L, 100L, 101L,
            18L, NA_integer_, 17L, 0L, 60L, NA_integer_, 20L, 18L)
  antes <- serialize(entrada, NULL)
  processados <- modulo$processar_dados_sim(entrada)
  ids <- as.character(1:16)
  stopifnot(
    identical(serialize(entrada, NULL), antes), nrow(processados) == 16L,
    identical(processados$.import_mds_registro_id, ids),
    identical(processados$CODESTAB, entrada$CODESTAB),
    identical(processados$data_obito_original, codigos),
    identical(processados$data_obito_validada, datas_esperadas),
    identical(processados$data_evento, datas_esperadas),
    identical(processados$data_obito_situacao, situacoes),
    identical(processados$data_obito_motivo, motivos),
    identical(processados$idade_codigo_original, entrada$IDADE),
    identical(processados$idade_anos_completos, anos),
    identical(processados$DTOBITO[c(6L, 7L, 8L)], c("2020-01-01", "20-12-10", "20-01-01")),
    all(is.na(processados$data_evento[c(6L, 7L, 8L)]))
  )
  cat("OK: datas e idades brutas associadas antes da perda de informação; data final independente da conversão permissiva\n")

  # Cada caso declara a seleção inteira e as exclusões etárias esperadas:
  # após idade, desconhecidas, inválidas, fora dos limites.
  casos <- list(
    sem_limites = list(list(), 1:16, c(16L, 0L, 0L, 0L)),
    minimo = list(list(idade_min = 18), c(1L, 2L, 5L, 7L, 8L, 9L, 13L, 15L, 16L), c(9L, 2L, 1L, 4L)),
    maximo = list(list(idade_max = 17), c(3L, 6L, 11L, 12L), c(4L, 2L, 1L, 9L)),
    intervalo = list(list(idade_min = 18, idade_max = 60), c(1L, 2L, 5L, 9L, 13L, 15L, 16L), c(7L, 2L, 1L, 6L)),
    iguais = list(list(idade_min = 18, idade_max = 18), c(1L, 9L, 16L), c(3L, 2L, 1L, 10L)),
    cid = list(list(cid = "I21"), c(1:7, 9L, 11L, 13L, 14L, 15L), c(16L, 0L, 0L, 0L)),
    outro_cid = list(list(cid = "C50"), c(8L, 12L), c(16L, 0L, 0L, 0L)),
    combinados = list(list(sexo = "Masculino", raca = "Branca", cid = "I21"), c(1L, 2L, 4L, 5L, 6L, 9L, 14L, 15L), c(16L, 0L, 0L, 0L)),
    combinados_minimo = list(list(sexo = "Masculino", raca = "Branca", cid = "I21", idade_min = 18), c(1L, 2L, 5L, 9L, 15L), c(9L, 2L, 1L, 4L)),
    vazio = list(list(cid = "Z999"), integer(), c(16L, 0L, 0L, 0L))
  )
  saidas <- list()
  for (nome in names(casos)) {
    caso <- casos[[nome]]
    saida <- do.call(preparar, c(list(dados_brutos = entrada), caso[[1L]]))
    linhas <- caso[[2L]]
    etapa <- caso[[3L]]
    esperado_datas <- list(
      entrada = 16L, datas_validas = 5L, datas_ausentes = 4L, datas_invalidas = 7L,
      preservados_apos_validacao = 16L, excluidos_por_data = 0L,
      apos_filtro_etario = etapa[1L], apos_demais_filtros = length(linhas),
      total_final_exportavel = length(linhas)
    )
    esperado_idades <- list(
      filtro_ativo = !is.null(caso[[1L]]$idade_min) || !is.null(caso[[1L]]$idade_max),
      idade_min = caso[[1L]]$idade_min, idade_max = caso[[1L]]$idade_max,
      entrada = 16L, excluidos_sem_data = 0L, antes_filtro_etario = 16L,
      idades_validas = 13L, idades_desconhecidas = 2L, idades_invalidas = 1L,
      excluidos_desconhecidos = etapa[2L], excluidos_invalidos = etapa[3L],
      excluidos_fora_limites = etapa[4L], apos_filtro_etario = etapa[1L],
      apos_demais_filtros = length(linhas)
    )
    cd <- attr(saida, "contagens_datas")
    ce <- attr(saida, "contagens_etarias")
    stopifnot(
      identical(names(saida), colunas), nrow(saida) == length(linhas),
      identical(saida$ESTABELECIMENTO, entrada$CODESTAB[linhas]),
      identical(saida$DATA, datas_esperadas[linhas]),
      identical(saida$DOENCA, toupper(entrada$CAUSABAS[linhas])),
      identical(cd, esperado_datas), identical(ce, esperado_idades),
      cd$entrada == cd$datas_validas + cd$datas_ausentes + cd$datas_invalidas,
      cd$preservados_apos_validacao == cd$entrada - cd$excluidos_por_data,
      ce$antes_filtro_etario == cd$preservados_apos_validacao,
      ce$antes_filtro_etario == ce$apos_filtro_etario + ce$excluidos_desconhecidos +
        ce$excluidos_invalidos + ce$excluidos_fora_limites,
      ce$apos_filtro_etario == cd$apos_filtro_etario,
      ce$apos_demais_filtros == cd$apos_demais_filtros,
      cd$total_final_exportavel == nrow(saida),
      identical(serialize(entrada, NULL), antes)
    )
    saidas[[nome]] <- saida
    cat("OK:", nome, "- seleção, DATA, 14 colunas e contagens explícitas reconciliadas\n")
  }
  stopifnot(identical(saidas$sem_limites$IDADE,
                     c("18", "20", NA, NA, "60", "17", "100", "101", "18", NA, "17", "0", "60", NA, "20", "18")))

  # Compara todos os 14 valores, tipos e bytes CSV de datas válidas com o commit
  # anterior. As novas contagens são avaliadas separadamente, acima.
  anterior <- new.env(parent = globalenv())
  texto <- system2("git", c("show", "0f414367880648b4c6858e3da217e43e54d2e20e:R/sistemas/sim.R"), stdout = TRUE)
  stopifnot(is.null(attr(texto, "status")))
  eval(parse(text = texto), envir = anterior)
  for (nome in names(casos)) {
    config <- casos[[nome]][[1L]]
    legado <- do.call(anterior$preparar_exportacao_sim,
                      c(list(dados_brutos = entrada[c(1L, 11L, 12L, 13L, 16L), ]), config))
    legado <- sem_contagens(legado)
    novo <- sem_contagens(saidas[[nome]][!is.na(saidas[[nome]]$DATA), ])
    stopifnot(identical(legado, novo), identical(
      capture.output(utils::write.csv(legado, file = "", row.names = FALSE)),
      capture.output(utils::write.csv(novo, file = "", row.names = FALSE))
    ))
  }
  legado_completo <- anterior$preparar_exportacao_sim(entrada)
  stopifnot(nrow(legado_completo) == 8L, nrow(saidas$sem_limites) == 16L,
            identical(legado_completo$ESTABELECIMENTO, entrada$CODESTAB[c(1L, 6L, 7L, 8L, 11L, 12L, 13L, 16L)]))
  cat("OK: valores e bytes legados das datas válidas preservados; aumento de 8 para 16 linhas e três datas permissivas anuladas\n")

  # Reordenação controlada no limite entre processador e associação; não altera
  # o pacote instalado. Os cenários corrompidos devem interromper o fluxo real.
  validacoes <- cbind(modulo$normalizar_idade_sim(entrada$IDADE), modulo$validar_data_obito_sim(codigos))
  stopifnot(identical(modulo$associar_validacoes_sim(processados[16:1, ], ids, validacoes), processados))
  alteracoes <- list(
    perda = function(d) d[-1L, ],
    duplicacao = function(d) d[c(1:16, 1L), ],
    id_ausente = function(d) {d$.import_mds_registro_id[1L] <- NA_character_; d},
    id_inesperado = function(d) {d$.import_mds_registro_id[1L] <- "inesperado"; d},
    id_duplicado = function(d) {d$.import_mds_registro_id[2L] <- "1"; d},
    sem_id = function(d) d[, names(d) != ".import_mds_registro_id"]
  )
  for (alterar in alteracoes) {
    isolado <- new.env(parent = globalenv())
    sys.source("R/sistemas/sim.R", envir = isolado)
    isolado$associar_validacoes_sim <- function(dados, ids_originais, validacoes) {
      modulo$associar_validacoes_sim(alterar(dados), ids_originais, validacoes)
    }
    stopifnot(identical(erro(isolado$processar_dados_sim(entrada)),
                        "Não foi possível garantir a correspondência entre registros brutos e processados do SIM."))
  }
  stopifnot(!is.null(erro(modulo$associar_validacoes_sim(processados, ids, validacoes[-1L, ]))))
  cat("OK: restauração por ID e interrupção do processamento em perdas, duplicações e IDs inesperados\n")

  estrutural <- new.env(parent = globalenv())
  sys.source("R/sistemas/sim.R", envir = estrutural)
  estrutural$validar_data_obito_sim <- function(...) stop("Validação não deveria iniciar.")
  stopifnot(identical(erro(estrutural$processar_dados_sim(entrada[, names(entrada) != "DTOBITO"])),
                      "Dados brutos do SIM devem conter a coluna DTOBITO original."))
  for (nome in c(".import_mds_registro_id", names(validacoes))) {
    colisao <- entrada
    colisao[[nome]] <- "reservado"
    stopifnot(identical(erro(modulo$processar_dados_sim(colisao)),
                        "Dados brutos do SIM contêm colunas reservadas para associação de registros."))
  }
  cat("OK: ausência estrutural de DTOBITO e colisões de colunas rejeitadas\n")

  invertida <- preparar(entrada[16:1, ])
  stopifnot(identical(sem_contagens(invertida), sem_contagens(saidas$sem_limites[16:1, ])))
  tabela <- data.table::as.data.table(entrada)
  antes_tabela <- serialize(tabela, NULL)
  stopifnot(identical(preparar(tabela), saidas$sem_limites),
            identical(serialize(tabela, NULL), antes_tabela), identical(serialize(entrada, NULL), antes))
  cat("OK: ordem inversa, duplicatas legítimas e ausência de mutação em data.frame/data.table\n")

  # Exercita o exportador existente apenas em um diretório temporário próprio.
  exportador <- new.env(parent = baseenv())
  sys.source("R/comum/exportacao.R", envir = exportador)
  diretorio <- tempfile("import-mds-datas-integracao-")
  stopifnot(dir.create(diretorio))
  on.exit(unlink(diretorio, recursive = TRUE), add = TRUE)
  arquivo <- file.path(diretorio, "sintetico.csv")
  exportador$exportar_csv_seguro(saidas$sem_limites, arquivo)
  csv <- utils::read.csv(arquivo, colClasses = "character", check.names = FALSE)
  stopifnot(nrow(csv) == 16L, identical(names(csv), colunas),
            identical(csv$DATA, as.character(datas_esperadas)),
            identical(csv$ESTABELECIMENTO, entrada$CODESTAB),
            identical(readLines(arquivo), capture.output(utils::write.csv(saidas$sem_limites, file = "", row.names = FALSE))))
  cat("OK: CSV seguro com DATA=NA, duplicatas, 14 colunas e serialização existente preservada\n")
  cat("PASSOU: 10 cenários de seleção e contagens; associação, regressão, esquema, duplicatas, entrada e CSV; sem downloads.\n")
})
