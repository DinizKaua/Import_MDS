# TZ=UTC Rscript --vanilla tests/test_organizacao_saida.R
# Somente temporários e dados sintéticos. Nenhuma coleta real é executada.
local({
  raiz <- normalizePath(".")
  carregar <- function() {
    e <- new.env(parent = baseenv())
    sys.source(file.path(raiz, "R/comum/exportacao.R"), e)
    sys.source(file.path(raiz, "R/comum/auditoria.R"), e)
    e
  }
  m <- carregar()
  temp <- tempfile("import-mds-organizacao-")
  stopifnot(dir.create(temp), file.exists(file.path(raiz, "Dados/.gitkeep")))
  on.exit(unlink(temp, recursive = TRUE), add = TRUE)
  caso <- function() {
    p <- tempfile("projeto com espaços-", tmpdir = temp)
    stopifnot(dir.create(p))
    p
  }
  erro <- function(expr, trecho = NULL) {
    mensagem <- tryCatch({force(expr); NULL}, error = function(e) conditionMessage(e))
    stopifnot(!is.null(mensagem))
    if (!is.null(trecho)) stopifnot(grepl(trecho, mensagem, fixed = TRUE))
    invisible(mensagem)
  }
  bytes <- function(p) readBin(p, "raw", n = file.info(p)$size)
  dados <- as.data.frame(setNames(rep(list(rep("texto", 3L)), 14L), m$colunas_principal_auditoria()))
  dados$DATA <- as.Date(c("2020-01-01", NA, "2020-01-01"))
  dados$LOCAL_OBITO <- c("vírgula, aspas\" e\nlinha", "NA", "vírgula, aspas\" e\nlinha")
  dados$ESTADO_NATURALIDADE <- c("CAMBOJA / LAOS", "MARANHAO", "CAMBOJA / LAOS")
  aux <- data.frame(posicao_registro = c(1L, 3L), codigo_original = c("44", "44"),
    situacao = rep("ambigua", 2L), motivo = rep("codigo_corresponde_a_dois_paises_distintos", 2L),
    descricao = rep("CAMBOJA / LAOS", 2L))
  meta <- m$preparar_metadados_auditoria("SIM-DO", "MA")
  nome <- m$construir_nome_csv("SIM-DO", "MA", 2020, 2020, cid = "I21", idade_min = 18)
  publicar <- function(s, e = m, d = dados, a = aux) {
    e$publicar_resultado_auditado(d, a, s$principal, meta, diretorio_logs = s$logs)
  }
  destinos <- function(s) m$destinos_resultado_auditado(s$principal, s$logs)
  # Não usar destinos() depois da publicação, pois ela recusa arquivos existentes.
  caminhos <- function(s) list(principal = s$principal,
    naturalidade = file.path(s$logs, sub("[.]csv$", "_auditoria_naturalidade.csv", basename(s$principal))),
    relatorio = file.path(s$logs, sub("[.]csv$", "_relatorio.json", basename(s$principal))))
  p <- caso(); s <- m$preparar_diretorio_extracao(p, nome); c <- destinos(s)
  stopifnot(dir.exists(file.path(p, "Dados")), dir.exists(s$logs),
    identical(s$diretorio, file.path(p, "Dados", sub("[.]csv$", "", nome))),
    identical(dirname(c$principal), s$diretorio), identical(dirname(c$naturalidade), s$logs),
    identical(dirname(c$relatorio), s$logs), identical(basename(c$principal), nome))
  publicar(s)
  r <- m$verificar_resultado_auditado(c$relatorio, meta$id_execucao)
  stopifnot(r$versao_esquema == "1.1.0", r$publicacao$base_caminhos == "diretorio_relatorio",
    r$arquivos$principal$nome == paste0("../", nome),
    r$arquivos$naturalidade$nome == sub("[.]csv$", "_auditoria_naturalidade.csv", nome),
    r$arquivos$principal$registros == 3L, r$arquivos$naturalidade$registros == 2L,
    r$arquivos$principal$sha256 == m$sha256_arquivo(c$principal),
    r$arquivos$naturalidade$sha256 == m$sha256_arquivo(c$naturalidade),
    length(r$arquivos$principal$colunas) == 14L,
    identical(m$ler_auditoria_naturalidade(c$naturalidade, 3L)$posicao_registro, c(1, 3)),
    identical(sort(list.files(s$diretorio)), sort(c(nome, "logs"))),
    identical(sort(list.files(s$logs)), sort(basename(unlist(c[-1L])))))
  legado <- file.path(p, "serializacao anterior.csv")
  utils::write.csv(dados, legado, row.names = FALSE)
  stopifnot(identical(bytes(c$principal), bytes(legado)))
  transportado <- caso()
  stopifnot(file.copy(s$diretorio, transportado, recursive = TRUE))
  m$verificar_resultado_auditado(file.path(transportado, basename(s$diretorio), "logs", basename(c$relatorio)))
  cat("OK: três artefatos organizados, nomes, JSON 1.1, SHA-256, posições, duplicatas, 14 colunas e bytes equivalentes\n")

  # Relatórios antigos no mesmo diretório continuam válidos, sem migração.
  antigo <- caso(); caminho_antigo <- file.path(antigo, "saida.csv")
  m$publicar_resultado_auditado(dados, aux, caminho_antigo, meta)
  r0 <- m$verificar_resultado_auditado(file.path(antigo, "saida_relatorio.json"))
  stopifnot(r0$versao_esquema == "1.0.0", r0$arquivos$principal$nome == "saida.csv")
  h0 <- m$sha256_arquivo(caminho_antigo)
  for (vazio in c(FALSE, TRUE)) {
    s0 <- m$preparar_diretorio_extracao(caso(), "dados com espaços.csv")
    publicar(s0, d = if (vazio) dados[FALSE, ] else dados, a = aux[FALSE, ])
    j <- m$verificar_resultado_auditado(caminhos(s0)$relatorio)
    stopifnot(j$arquivos$naturalidade$registros == 0L,
      j$arquivos$principal$registros == if (vazio) 0L else 3L)
  }
  stopifnot(m$sha256_arquivo(caminho_antigo) == h0)
  cat("OK: esquema 1.0 histórico, nomes com espaços, principal vazio e auxiliar sem exceções\n")

  # Nada previamente ocupado é reutilizado, inclusive diretórios vazios e links.
  for (tipo in c("vazio", "arquivo", "link")) {
    p0 <- caso(); pasta <- file.path(p0, "Dados", sub("[.]csv$", "", nome))
    dir.create(dirname(pasta))
    if (tipo == "vazio") dir.create(pasta)
    if (tipo == "arquivo") writeLines("preexistente", pasta)
    if (tipo == "link") stopifnot(file.symlink(file.path(p0, "inexistente"), pasta))
    erro(m$preparar_diretorio_extracao(p0, nome), "já existe")
    stopifnot(if (tipo == "vazio") dir.exists(pasta) else if (tipo == "arquivo")
      identical(readLines(pasta), "preexistente") else nzchar(Sys.readlink(pasta)))
  }
  hash_publicado <- m$sha256_arquivo(c$principal)
  erro(m$preparar_diretorio_extracao(p, nome), "já existe")
  erro(publicar(s), "já existe")
  stopifnot(m$sha256_arquivo(c$principal) == hash_publicado)
  for (etapa in c("Dados", "extracao", "logs")) {
    e <- carregar(); p0 <- caso(); criar <- base::dir.create
    e$dir.create <- function(path, ...) {
      falhar <- switch(etapa, Dados = basename(path) == "Dados", logs = basename(path) == "logs",
                       extracao = basename(path) == sub("[.]csv$", "", nome))
      if (falhar) FALSE else criar(path, ...)
    }
    erro(e$preparar_diretorio_extracao(p0, nome), "Não foi possível")
    stopifnot(!any(grepl("relatorio.json$", list.files(p0, recursive = TRUE))))
  }
  p0 <- caso(); writeLines("pai ocupado", file.path(p0, "Dados"))
  erro(m$preparar_diretorio_extracao(p0, nome), "Diretório")
  stopifnot(identical(readLines(file.path(p0, "Dados")), "pai ocupado"))
  for (n in c("../fora.csv", "sub/fora.csv", "sub\\fora.csv", "..csv", "...csv", ".csv")) {
    erro(m$preparar_diretorio_extracao(caso(), n), "Nome CSV inválido")
  }
  cat("OK: recusa de diretórios ocupados, links e falhas de mkdir, sem remover conteúdo preexistente\n")

  # Duas execuções Linux em processos separados disputam a mesma reserva mkdir.
  corrida <- caso()
  disputa <- parallel::mclapply(1:2, function(i) {
    tryCatch({m$preparar_diretorio_extracao(corrida, nome); TRUE}, error = function(e) FALSE)
  }, mc.cores = 2L)
  stopifnot(sum(unlist(disputa)) == 1L)
  cat("OK: dois processos disputam o mesmo nome; somente uma reserva é bem-sucedida\n")

  for (falha in c("escrita", "apos_principal", "conflito_auxiliar")) {
    e <- carregar(); s0 <- e$preparar_diretorio_extracao(caso(), nome); c0 <- caminhos(s0)
    if (falha == "escrita") e$.escrever_csv_padrao <- function(d, con) {
      writeLines("parcial", con); stop("falha controlada de escrita")
    } else {
      publicar_arquivo <- e$publicar_arquivo_seguro; n <- 0L
      e$publicar_arquivo_seguro <- function(t, d) {
        n <<- n + 1L
        if (n == 2L) {
          if (falha == "apos_principal") stop("interrupção controlada")
          writeLines("artefato da outra execução", d)
        }
        publicar_arquivo(t, d)
      }
    }
    alheio <- file.path(s0$logs, ".import-mds-csv-alheio.tmp"); writeLines("alheio", alheio)
    erro(publicar(s0, e))
    stopifnot(!file.exists(c0$relatorio), file.exists(c0$principal) == (falha != "escrita"),
      identical(readLines(alheio), "alheio"), dir.exists(s0$diretorio), dir.exists(s0$logs),
      identical(list.files(s0$diretorio, recursive = TRUE, all.files = TRUE, pattern = "^\\.import-mds-csv-"),
                "logs/.import-mds-csv-alheio.tmp"))
    if (falha == "conflito_auxiliar") stopifnot(identical(readLines(c0$naturalidade), "artefato da outra execução"))
  }
  cat("OK: falhas e conflitos entre publicações mantêm definitivos, sem JSON e com limpeza somente de temporários próprios\n")

  # Caminhos arbitrários, subpastas e links não podem escapar do conjunto.
  original_json <- bytes(c$relatorio)
  for (tipo in c("subida", "subpasta", "absoluto", "barra_invertida", "sem_subida", "auxiliar", "base")) {
    j <- jsonlite::fromJSON(c$relatorio, simplifyVector = FALSE)
    if (tipo == "auxiliar") j$arquivos$naturalidade$nome <- "../fora.csv"
    else if (tipo == "base") j$publicacao$base_caminhos <- "/tmp"
    else j$arquivos$principal$nome <- switch(tipo, subida = "../../fora.csv", subpasta = "../sub/fora.csv",
      absoluto = "/tmp/fora.csv", barra_invertida = "..\\fora.csv", sem_subida = nome)
    con <- file(c$relatorio, "w"); m$.escrever_relatorio_auditoria(j, con); close(con)
    erro(m$verificar_resultado_auditado(c$relatorio))
    writeBin(original_json, c$relatorio)
  }
  copia <- file.path(caso(), basename(c$relatorio)); file.copy(c$relatorio, copia)
  erro(m$verificar_resultado_auditado(copia), "fora da estrutura")
  # Apenas arquivos sintéticos são removidos/substituídos neste teste de link.
  conteudo <- bytes(c$principal); alvo <- file.path(caso(), "fora.csv"); writeBin(conteudo, alvo)
  unlink(c$principal); stopifnot(file.symlink(alvo, c$principal))
  erro(m$verificar_resultado_auditado(c$relatorio), "fora do diretório")
  unlink(c$principal); writeBin(conteudo, c$principal)
  m$verificar_resultado_auditado(c$relatorio)
  # Alias da pasta da extração ou de logs também não contorna os limites.
  alias <- file.path(caso(), basename(s$diretorio))
  stopifnot(file.symlink(s$diretorio, alias))
  erro(m$verificar_resultado_auditado(file.path(alias, "logs", basename(c$relatorio))), "link simbólico")
  logs_alias <- file.path(caso(), "logs")
  stopifnot(file.symlink(s$logs, logs_alias))
  erro(m$verificar_resultado_auditado(file.path(logs_alias, basename(c$relatorio))), "link simbólico")
  cat("OK: referências limitadas, JSON fora de logs e links para fora do conjunto rejeitados\n")

  # Rscript direto: o prefixo físico não contém chamada de coleta.
  codigo <- parse(file.path(raiz, "R/coletar_dados.R"))
  fetch <- which(vapply(codigo, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name("dados_brutos")), logical(1)))
  stopifnot(length(fetch) == 1L, identical(codigo[[fetch]][[3L]][[1L]], as.name("fetch_datasus")))
  prefixo <- codigo[seq_len(fetch - 1L)]
  stopifnot(!"fetch_datasus" %in% all.names(prefixo))
  projeto <- caso()
  for (f in c("R/comum/cid.R", "R/sistemas/sim.R", "R/comum/exportacao.R", "R/comum/auditoria.R")) {
    dir.create(dirname(file.path(projeto, f)), recursive = TRUE, showWarnings = FALSE)
    stopifnot(file.copy(file.path(raiz, f), file.path(projeto, f)))
  }
  script <- file.path(projeto, "R/coletar_dados.R")
  writeLines(vapply(prefixo, function(x) paste(deparse(x, width.cutoff = 500L), collapse = "\n"), character(1)), script)
  fora <- caso(); anterior <- getwd(); on.exit(setwd(anterior), add = TRUE)
  setwd(fora)
  executar <- function() {
    saida <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
      c("--vanilla", shQuote(script), "--system", "SIM-DO", "--uf", "MA", "--cid", "I21"),
      stdout = TRUE, stderr = TRUE))
    status <- attr(saida, "status"); if (is.null(status)) status <- 0L
    list(status = status, saida = saida)
  }
  primeira <- executar()
  if (primeira$status != 0L) stop("Prefixo Rscript falhou: ", paste(primeira$saida, collapse = "\n"))
  stopifnot(dir.exists(file.path(projeto, "Dados/dados_SIM-DO_MA_2020_2020_I21/logs")),
    !dir.exists(file.path(fora, "Dados")), executar()$status != 0L)
  setwd(anterior)
  cat("OK: Rscript absoluto com espaços, outra pasta de trabalho e conflito propagado com saída não zero\n")

  ignorado <- function(caminho) {
    status <- suppressWarnings(system2(Sys.which("git"), c("-C", shQuote(raiz), "check-ignore", "--no-index", "-q", "--", shQuote(caminho))))
    stopifnot(status %in% c(0L, 1L)); status == 0L
  }
  stopifnot(ignorado("Dados/extracao/resultado.csv"), ignorado("Dados/extracao/logs/relatorio.json"),
    !ignorado("Dados/.gitkeep"), !ignorado("configuracao.json"), ignorado("dados_teste_relatorio.json"))
  cat("OK: Dados/.gitkeep disponível e versionável, saídas ignoradas e outros JSONs versionáveis\n")
  cat("PASSOU: organização física, segurança de caminhos, compatibilidade, concorrência, falhas e execução fora da raiz; sem downloads.\n")
})
