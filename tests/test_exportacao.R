# Executar da raiz: TZ=UTC Rscript --vanilla tests/test_exportacao.R
# Somente dados sintéticos e diretórios temporários; nenhuma coleta é executada.
local({
  raiz <- normalizePath(".")
  modulo_arquivo <- file.path(raiz, "R", "comum", "exportacao.R")
  carregar <- function() {
    ambiente <- new.env(parent = baseenv())
    sys.source(modulo_arquivo, envir = ambiente)
    ambiente
  }
  modulo <- carregar()
  diretorio <- tempfile("import-mds-teste-exportacao-")
  stopifnot(dir.create(diretorio))
  on.exit(unlink(diretorio, recursive = TRUE), add = TRUE)
  erro <- function(expr) tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
  bytes <- function(caminho) readBin(caminho, "raw", n = file.info(caminho)$size)
  hash <- function(caminho) unname(tools::md5sum(caminho))
  nome <- function(...) modulo$construir_nome_csv("SIM-DO", "MA", 2020, 2024, ...)

  stopifnot(
    identical(nome(), "dados_SIM-DO_MA_2020_2024.csv"),
    identical(nome(cid = "I21"), "dados_SIM-DO_MA_2020_2024_I21.csv"),
    identical(nome(cid = "DRC"), "dados_SIM-DO_MA_2020_2024_DRC.csv"),
    identical(nome(cid = "I21", idade_min = 60), "dados_SIM-DO_MA_2020_2024_I21_idade_60mais.csv"),
    identical(nome(cid = "I21", idade_max = 17), "dados_SIM-DO_MA_2020_2024_I21_idade_ate17.csv"),
    identical(nome(cid = "I21", idade_min = 18, idade_max = 59), "dados_SIM-DO_MA_2020_2024_I21_idade_18-59.csv"),
    identical(nome(idade_min = 0), "dados_SIM-DO_MA_2020_2024_idade_0mais.csv"),
    identical(nome(cid = "I21", sexo = "Feminino", raca = "Preta", faixa = "18-39"),
              "dados_SIM-DO_MA_2020_2024_I21_Feminino_Preta_18-39.csv"),
    identical(nome(faixa = "60+"), "dados_SIM-DO_MA_2020_2024_60+.csv"),
    identical(nome(raca = "Indígena"), "dados_SIM-DO_MA_2020_2024_Indígena.csv"),
    identical(modulo$construir_nome_csv("SIM-DO", "all", 2020, 2024), "dados_SIM-DO_BR_2020_2024.csv"),
    identical(nome(mes_inicio = 1, mes_fim = 2), nome(mes_inicio = 3, mes_fim = 4))
  )
  consultas <- list(
    list(), list(idade_min = 0), list(idade_min = 18), list(idade_max = 18),
    list(idade_min = 18, idade_max = 18), list(idade_min = 18, idade_max = 59),
    list(cid = "I21_idade_18-59"), list(cid = "I21", idade_min = 18, idade_max = 59),
    list(cid = "Masculino"), list(sexo = "Masculino"),
    list(sexo = "Branca"), list(raca = "Branca"),
    list(cid = "I21_outro", sexo = "Masculino"), list(cid = "I21_outro", sexo = "masculino"),
    list(cid = ""), list(sexo = ""), list(raca = ""), list(faixa = "")
  )
  nomes <- vapply(consultas, function(config) do.call(nome, config), character(1))
  stopifnot(!anyDuplicated(tolower(nomes)))
  perigoso <- nome(cid = "../I21_foo%")
  stopifnot(!grepl("[/\\\\]", perigoso), !grepl("..", perigoso, fixed = TRUE))
  stopifnot(!identical(
    modulo$construir_nome_csv("SIH-RD", "MA", 2020, 2024, mes_inicio = 1, mes_fim = 2),
    modulo$construir_nome_csv("SIH-RD", "MA", 2020, 2024, mes_inicio = 3, mes_fim = 4)
  ))
  cat("OK: nomes etários, legados, meses efetivos e configurações sem aliases\n")

  dados <- data.frame(
    IDADE = c("18", NA_character_, "101"),
    DATA_DE_NASCIMENTO = c("2002-01-01", NA_character_, "1919-01-01"),
    ESTADO_CIVIL = c("Solteiro", "Casado", NA_character_),
    SEXO = c("Masculino", "Feminino", NA_character_),
    RACA_COR = c("Parda", "Indígena", "Branca"),
    LOCAL_OBITO = c("Hospital", "Domicílio", "texto,\"aspas\"\nlinha"),
    ESTABELECIMENTO = c("0000001", "0000002", "0000003"),
    DATA = as.Date(c("2020-01-01", NA, "2020-02-29")),
    ESTADO_RESIDENCIA = c("MA", "MA", "MA"),
    MUNICIPIO_RESIDENCIA = c("São Luís", "Exemplo", NA_character_),
    ESTADO_NATURALIDADE = c("Maranhão", NA_character_, "NA"),
    MUNICIPIO_NATURALIDADE = c("211130", "000000", NA_character_),
    ASSISTENCIA_MEDICA = c("Sim", "Não", NA_character_),
    DOENCA = c("I21", "I210", NA_character_), stringsAsFactors = FALSE
  )
  colunas <- c("IDADE", "DATA_DE_NASCIMENTO", "ESTADO_CIVIL", "SEXO", "RACA_COR",
               "LOCAL_OBITO", "ESTABELECIMENTO", "DATA", "ESTADO_RESIDENCIA",
               "MUNICIPIO_RESIDENCIA", "ESTADO_NATURALIDADE", "MUNICIPIO_NATURALIDADE",
               "ASSISTENCIA_MEDICA", "DOENCA")
  antes <- serialize(dados, NULL)
  alheio <- file.path(diretorio, ".import-mds-csv-outra-execucao.tmp")
  writeLines("temporário alheio", alheio)
  hash_alheio <- hash(alheio)
  destino <- file.path(diretorio, "saida.csv")
  esperado <- file.path(diretorio, "legado.csv")
  utils::write.csv(dados, esperado, row.names = FALSE)
  stopifnot(identical(modulo$verificar_destino_csv(destino), destino))
  modulo$exportar_csv_seguro(dados, destino)
  stopifnot(
    identical(bytes(destino), bytes(esperado)), identical(hash(destino), hash(esperado)),
    identical(names(read.csv(destino, colClasses = "character", check.names = FALSE)), colunas),
    identical(serialize(dados, NULL), antes), identical(hash(alheio), hash_alheio),
    identical(list.files(diretorio, all.files = TRUE, pattern = "^\\.import-mds-csv-"), basename(alheio))
  )
  vazio <- file.path(diretorio, "vazio.csv")
  esperado_vazio <- file.path(diretorio, "legado-vazio.csv")
  utils::write.csv(dados[FALSE, ], esperado_vazio, row.names = FALSE)
  modulo$exportar_csv_seguro(dados[FALSE, ], vazio)
  stopifnot(identical(bytes(vazio), bytes(esperado_vazio)))
  cat("OK: escrita completa, 14 colunas, tipos da entrada e bytes CSV idênticos ao legado\n")

  conteudo <- bytes(destino)
  digest <- hash(destino)
  existente <- carregar()
  existente$.escrever_csv_padrao <- function(...) stop("Escrita não deveria começar.")
  mensagem <- erro(existente$exportar_csv_seguro(dados, destino))
  stopifnot(grepl("Destino CSV já existe", mensagem, fixed = TRUE),
            identical(bytes(destino), conteudo), identical(hash(destino), digest))
  stopifnot(!is.null(erro(modulo$verificar_destino_csv(diretorio))))
  cat("OK: conflito inicial interrompe sem escrever ou alterar conteúdo/hash existentes\n")

  falha <- carregar()
  estado <- new.env(parent = emptyenv())
  falha$.escrever_csv_padrao <- function(dados, conexao) {
    estado$temporario <- summary(conexao)$description
    writeLines("CSV parcial", conexao)
    stop("falha de escrita simulada")
  }
  falho <- file.path(diretorio, "falho.csv")
  mensagem <- erro(falha$exportar_csv_seguro(dados, falho))
  stopifnot(
    identical(mensagem, "falha de escrita simulada"), !file.exists(falho),
    !file.exists(estado$temporario), identical(dirname(estado$temporario), diretorio),
    identical(hash(alheio), hash_alheio)
  )
  aviso <- carregar()
  aviso$.escrever_csv_padrao <- function(dados, conexao) {
    writeLines("parcial", conexao)
    warning("escrita incompleta simulada")
  }
  stopifnot(grepl("Falha na escrita do CSV", erro(aviso$exportar_csv_seguro(dados, falho)), fixed = TRUE),
            !file.exists(falho))
  cat("OK: erros/avisos de escrita impedem publicação e limpam somente o temporário próprio\n")

  # Simulação controlada: outra execução cria o destino depois da última
  # verificação e da escrita, imediatamente antes do file.link REAL.
  corrida <- carregar()
  escrever <- corrida$.escrever_csv_padrao
  destino_corrida <- file.path(diretorio, "corrida.csv")
  corrida$.escrever_csv_padrao <- function(dados, conexao) {
    escrever(dados, conexao)
    writeLines("resultado da outra execução", destino_corrida)
    estado$hash_corrida <- hash(destino_corrida)
    estado$bytes_corrida <- bytes(destino_corrida)
  }
  corrida$verificar_destino_csv(destino_corrida)
  mensagem <- erro(corrida$exportar_csv_seguro(dados, destino_corrida))
  stopifnot(
    grepl("Destino CSV já existe", mensagem, fixed = TRUE),
    identical(hash(destino_corrida), estado$hash_corrida),
    identical(bytes(destino_corrida), estado$bytes_corrida),
    identical(hash(alheio), hash_alheio)
  )
  cat("OK: conflito após verificação preservado pela publicação real sem sobrescrita\n")

  sem_suporte <- carregar()
  sem_suporte$file.link <- function(from, to) FALSE
  indisponivel <- file.path(diretorio, "indisponivel.csv")
  stopifnot(grepl("deve suportar hard links", erro(sem_suporte$exportar_csv_seguro(dados, indisponivel)), fixed = TRUE),
            !file.exists(indisponivel))
  stopifnot(identical(list.files(diretorio, all.files = TRUE, pattern = "^\\.import-mds-csv-"), basename(alheio)))
  cat("OK: plataforma sem publicação segura falha explicitamente, sem fallback destrutivo\n")

  # Exercita o prefixo verdadeiro do orquestrador em uma raiz TEMPORÁRIA.
  dir_cli <- file.path(diretorio, "projeto")
  dir.create(file.path(dir_cli, "R", "comum"), recursive = TRUE)
  dir.create(file.path(dir_cli, "R", "sistemas"), recursive = TRUE)
  stopifnot(file.copy(file.path(raiz, "R", "comum", "cid.R"), file.path(dir_cli, "R", "comum", "cid.R")),
            file.copy(file.path(raiz, "R", "coletar_dados.R"), file.path(dir_cli, "R", "coletar_dados.R")),
            file.copy(modulo_arquivo, file.path(dir_cli, "R", "comum", "exportacao.R")),
            file.copy(file.path(raiz, "R", "comum", "auditoria.R"), file.path(dir_cli, "R", "comum", "auditoria.R")),
            file.copy(file.path(raiz, "R", "sistemas", "sim.R"), file.path(dir_cli, "R", "sistemas", "sim.R")))
  codigo <- parse(file = file.path(raiz, "R", "coletar_dados.R"))
  indice_fetch <- which(vapply(codigo, function(expr) {
    is.call(expr) && identical(expr[[1L]], as.name("<-")) && identical(expr[[2L]], as.name("dados_brutos"))
  }, logical(1)))
  stopifnot(length(indice_fetch) == 1L)
  prefixo <- codigo[2L:(indice_fetch - 1L)]
  stopifnot(!"fetch_datasus" %in% all.names(prefixo))
  executar_prefixo <- function() {
    anterior <- getwd()
    on.exit(setwd(anterior), add = TRUE)
    setwd(dir_cli)
    ambiente <- new.env(parent = globalenv())
    ambiente$commandArgs <- function(trailingOnly = FALSE) {
      args <- c("--system", "SIM-DO", "--uf", "MA", "--year_start", "2020", "--year_end", "2024",
        "--cid", "I21", "--idade_min", "18", "--idade_max", "59")
      if (trailingOnly) args else c("Rscript", paste0("--file=", file.path(dir_cli, "R/coletar_dados.R")), args)
    }
    ambiente$fetch_datasus <- function(...) stop("Coleta proibida nos testes.")
    invisible(capture.output(eval(prefixo, envir = ambiente)))
    ambiente
  }
  ambiente <- executar_prefixo()
  stopifnot(identical(ambiente$nome_arquivo, "dados_SIM-DO_MA_2020_2024_I21_idade_18-59.csv"),
            identical(ambiente$caminho_arquivo, file.path(dir_cli, "Dados", sub("[.]csv$", "", ambiente$nome_arquivo), ambiente$nome_arquivo)),
            !file.exists(ambiente$caminho_arquivo))
  writeLines("resultado anterior", ambiente$caminho_arquivo)
  digest <- hash(ambiente$caminho_arquivo)
  stopifnot(grepl("Diretório da extração já existe", erro(executar_prefixo()), fixed = TRUE),
            identical(hash(ambiente$caminho_arquivo), digest))
  cat("OK: caminho final e conflito inicial determinados antes do nó de fetch\n")

  # Um erro real de exportação deve encerrar Rscript com status não zero.
  filho <- file.path(diretorio, "processo-falho.csv")
  expressao <- paste0(
    "m <- new.env(parent=baseenv()); sys.source(", encodeString(modulo_arquivo, quote = '"'), ", envir=m); ",
    "m$.escrever_csv_padrao <- function(d,c) {writeLines('parcial',c); stop('falha simulada no processo')}; ",
    "m$exportar_csv_seguro(data.frame(x=1), ", encodeString(filho, quote = '"'), ")"
  )
  saida <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
                                   c("--vanilla", "-e", shQuote(expressao)), stdout = TRUE, stderr = TRUE))
  stopifnot(!is.null(attr(saida, "status")), attr(saida, "status") != 0L,
            any(grepl("falha simulada no processo", saida, fixed = TRUE)), !file.exists(filho),
            identical(list.files(diretorio, all.files = TRUE, pattern = "^\\.import-mds-csv-"), basename(alheio)))
  cat("OK: falha de exportação propagada por Rscript com saída não zero\n")
  cat("PASSOU: nomes, compatibilidade CSV, conflitos, limpeza, publicação e falhas; sem downloads.\n")
})
