# TZ=UTC Rscript --vanilla tests/test_auditoria.R
# Somente dados sintéticos; nenhuma coleta e nenhum CSV histórico é acessado.
local({
  carregar <- function() {
    e <- new.env(parent = baseenv())
    sys.source("R/comum/exportacao.R", e)
    sys.source("R/comum/auditoria.R", e)
    e
  }
  modulo <- carregar()
  raiz <- tempfile("import-mds-teste-auditoria-")
  stopifnot(dir.create(raiz))
  on.exit(unlink(raiz, recursive = TRUE), add = TRUE)
  caso <- function() {
    d <- tempfile("caso-", tmpdir = raiz)
    stopifnot(dir.create(d))
    d
  }
  bytes <- function(p) readBin(p, "raw", n = file.info(p)$size)
  erro <- function(expr, trecho = NULL) {
    mensagem <- tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
    stopifnot(!is.null(mensagem))
    if (!is.null(trecho)) stopifnot(grepl(trecho, mensagem, fixed = TRUE))
    invisible(mensagem)
  }
  caminhos <- function(d) c(principal = file.path(d, "saida.csv"),
    auxiliar = file.path(d, "saida_auditoria_naturalidade.csv"),
    json = file.path(d, "saida_relatorio.json"))
  sem_temporarios <- function(d) {
    stopifnot(length(list.files(d, pattern = "^\\.import-mds-csv-", all.files = TRUE)) == 0L)
  }
  dados <- as.data.frame(setNames(rep(list(rep("texto", 6L)), 14L), modulo$colunas_principal_auditoria()),
                         stringsAsFactors = FALSE)
  dados$IDADE <- c("18", "18", "0", NA, "100", "17")
  dados$DATA <- as.Date(c("2020-01-01", "2020-01-01", NA, "2020-02-29", NA, NA))
  dados$ESTABELECIMENTO <- rep("000001", 6L)
  dados$LOCAL_OBITO <- c("duplicata", "duplicata", "vírgula,aspas\"e\nquebra", "NA", NA, "  ")
  auditoria <- data.frame(posicao_registro = c(1L, 3L, 4L, 5L, 6L),
    codigo_original = c("001", NA, "NA", "  ", "00,\"\n1"),
    situacao = c("ambigua", "ausente", "sem_correspondencia", "ausente", "sem_correspondencia"),
    motivo = c("descricoes_conflitantes", "codigo_ausente_na", "codigo_nao_encontrado",
               "codigo_ausente_espacos", "codigo_nao_encontrado"),
    descricao = rep(NA_character_, 5L), stringsAsFactors = FALSE)
  contagens <- list(
    etarias = list(filtro_ativo = TRUE, idade_min = 0, idade_max = NULL, entrada = 10L,
      excluidos_sem_data = 0L, antes_filtro_etario = 10L, idades_validas = 8L,
      idades_desconhecidas = 1L, idades_invalidas = 1L, excluidos_desconhecidos = 1L,
      excluidos_invalidos = 1L, excluidos_fora_limites = 1L, apos_filtro_etario = 7L, apos_demais_filtros = 6L),
    datas = list(entrada = 10L, datas_validas = 6L, datas_ausentes = 2L, datas_invalidas = 2L,
      preservados_apos_validacao = 10L, excluidos_por_data = 0L, apos_filtro_etario = 7L,
      apos_demais_filtros = 6L, total_final_exportavel = 6L),
    naturalidade = list(antes_filtros = list(total = 10L, inequivocas = 3L, ambiguas = 2L,
      sem_correspondencia = 2L, ausentes = 3L), apos_filtro_etario = 7L,
      apos_demais_filtros = list(total = 6L, inequivocas = 1L, ambiguas = 1L, sem_correspondencia = 2L, ausentes = 2L)))
  meta <- modulo$preparar_metadados_auditoria("SIM-DO", "MA", list(ano_inicio = 2020L, ano_fim = 2024L),
    parametros = list(stop_on_error = TRUE), filtros = list(cid = "I21", idade_min = 0, idade_max = NULL),
    inicio = as.POSIXct("2020-02-29 10:00:00", tz = "America/Belem"),
    import_mds = list(commit = "versao-sintetica", alteracoes_locais = FALSE))
  publicar <- function(d, e = modulo, principal = dados, auxiliar = auditoria, cts = contagens, m = meta) {
    e$publicar_resultado_auditado(principal, auxiliar, caminhos(d)[["principal"]], m, cts)
  }
  antes <- serialize(dados, NULL)
  antes_aux <- serialize(auditoria, NULL)
  d <- caso(); p <- caminhos(d)
  r <- publicar(d)
  stopifnot(all(file.exists(p)), r$versao_esquema == "1.0.0", r$id_execucao == meta$id_execucao,
    r$arquivos$principal$registros == 6L, r$arquivos$naturalidade$registros == 5L,
    r$cobertura_datasus == "nao_verificada", r$publicacao$situacao == "concluida",
    meta$inicio_execucao_utc == "2020-02-29T13:00:00Z", is.null(r$metadados$versoes$Python),
    "metadados.versoes.Python" %in% unlist(r$informacoes_indisponiveis),
    identical(serialize(dados, NULL), antes), identical(serialize(auditoria, NULL), antes_aux))
  lido <- modulo$verificar_resultado_auditado(p[["json"]], meta$id_execucao)
  stopifnot(lido$arquivos$principal$registros == 6L, is.null(lido$metadados$versoes$Python),
    identical(modulo$ler_auditoria_naturalidade(p[["auxiliar"]], 6L), transform(auditoria, posicao_registro = as.numeric(posicao_registro))))
  esperado <- file.path(d, "legado.csv")
  utils::write.csv(dados, esperado, row.names = FALSE)
  stopifnot(identical(bytes(p[["principal"]]), bytes(esperado)),
    identical(names(modulo$.ler_csv_auditoria(p[["principal"]])), modulo$colunas_principal_auditoria()),
    nrow(modulo$.ler_csv_auditoria(p[["principal"]])) == 6L,
    identical(unlist(modulo$.ler_csv_auditoria(p[["principal"]])[1, ], use.names = FALSE),
              unlist(modulo$.ler_csv_auditoria(p[["principal"]])[2, ], use.names = FALSE)))
  sem_temporarios(d)
  cat("OK: três artefatos, JSON versionado, UTC, contagens, SHA-256, 14 colunas e bytes legados; duplicatas e campos multilinha\n")

  # Cabeçalhos sem registros e metadados indisponíveis explicitamente nulos.
  d <- caso(); vazio <- dados[FALSE, ]; aux_vazio <- auditoria[FALSE, ]
  r <- publicar(d, principal = vazio, auxiliar = aux_vazio, cts = list())
  p <- caminhos(d)
  modulo$verificar_resultado_auditado(p[["json"]])
  utils::write.csv(vazio, file.path(d, "legado.csv"), row.names = FALSE)
  stopifnot(identical(bytes(p[["principal"]]), bytes(file.path(d, "legado.csv"))),
    r$arquivos$principal$registros == 0L, r$arquivos$naturalidade$registros == 0L,
    all(c("contagens.etarias", "contagens.datas", "contagens.naturalidade") %in% unlist(r$informacoes_indisponiveis)),
    identical(names(modulo$.ler_csv_auditoria(p[["auxiliar"]])), modulo$colunas_naturalidade_auditoria()))
  d <- caso(); publicar(d, auxiliar = aux_vazio)
  stopifnot(nrow(modulo$ler_auditoria_naturalidade(caminhos(d)[["auxiliar"]], 6L)) == 0L)
  # Exceção inequívoca indicada pelo chamador: descrição literal NA é texto.
  a <- data.frame(posicao_registro = 2L, codigo_original = "0001 ", situacao = "inequivoca",
    motivo = "descricoes_identicas_repetidas", descricao = "NA")
  d <- caso(); publicar(d, auxiliar = a)
  stopifnot(identical(modulo$ler_auditoria_naturalidade(caminhos(d)[["auxiliar"]], 6L)$descricao, "NA"))
  cat("OK: principal vazio, auxiliar vazio, códigos com zeros/espaços, ausência diferenciada do texto NA\n")

  # Todos os destinos: arquivo, diretório e link simbólico quebrado.
  for (alvo in seq_len(3L)) for (tipo in c("arquivo", "diretorio", "link")) {
    d <- caso(); p <- caminhos(d); destino <- unname(p[alvo])
    if (tipo == "arquivo") writeLines("conteúdo anterior", destino)
    if (tipo == "diretorio") stopifnot(dir.create(destino))
    if (tipo == "link") stopifnot(file.symlink(file.path(d, "inexistente"), destino))
    hash <- if (tipo == "arquivo") modulo$sha256_arquivo(destino) else NULL
    erro(publicar(d), "já existe")
    if (tipo == "arquivo") stopifnot(identical(hash, modulo$sha256_arquivo(destino)))
    if (tipo == "link") stopifnot(nzchar(Sys.readlink(destino)))
    stopifnot(!any(file.exists(p[-alvo])))
    sem_temporarios(d)
  }
  cat("OK: conflitos antecipados em todos os destinos, inclusive diretórios e links quebrados; conteúdo existente preservado\n")

  # Falhas de preparação não publicam nada. Um temporário alheio nunca é limpo.
  for (falha in c("principal", "auxiliar", "json")) {
    d <- caso(); p <- caminhos(d); e <- carregar()
    alheio <- file.path(d, ".import-mds-csv-alheio.tmp"); writeLines("alheio", alheio)
    hash <- modulo$sha256_arquivo(alheio)
    original <- e$.escrever_csv_padrao
    if (falha == "json") {
      e$.escrever_relatorio_auditoria <- function(r, con) stop("falha sintética JSON")
    } else {
      e$.escrever_csv_padrao <- function(x, con) {
        if ((falha == "principal" && ncol(x) == 14L) || (falha == "auxiliar" && ncol(x) == 5L)) {
          writeLines("parcial", con); stop("falha sintética CSV")
        }
        original(x, con)
      }
    }
    erro(publicar(d, e), "falha sintética")
    stopifnot(!any(file.exists(p)), identical(hash, modulo$sha256_arquivo(alheio)),
      identical(list.files(d, pattern = "^\\.import-mds-csv-", all.files = TRUE), basename(alheio)))
  }

  # Interrupções CONTROLADAS (erros R), entre publicações e antes do JSON.
  # Não simulam SIGKILL, perda de energia nem a durabilidade do filesystem.
  for (etapa in 1:3) {
    d <- caso(); p <- caminhos(d); e <- carregar(); quantidade <- 0L
    original <- e$publicar_arquivo_seguro
    e$publicar_arquivo_seguro <- function(temp, dest) {
      quantidade <<- quantidade + 1L
      if (quantidade == etapa) stop("interrupção simulada")
      original(temp, dest)
    }
    erro(publicar(d, e), "interrupção simulada")
    stopifnot(identical(unname(file.exists(p)), c(etapa > 1L, etapa > 2L, FALSE)))
    if (etapa > 1L) {
      utils::write.csv(dados, file.path(d, "esperado.csv"), row.names = FALSE)
      stopifnot(identical(bytes(p[["principal"]]), bytes(file.path(d, "esperado.csv"))))
    }
    sem_temporarios(d)
  }
  # Conflito depois do preflight, imediatamente antes de cada hard link.
  for (etapa in 1:3) {
    d <- caso(); p <- caminhos(d); e <- carregar(); quantidade <- 0L
    original <- e$publicar_arquivo_seguro
    e$publicar_arquivo_seguro <- function(temp, dest) {
      quantidade <<- quantidade + 1L
      if (quantidade == etapa) writeLines("outra execução", dest)
      original(temp, dest)
    }
    erro(publicar(d, e), "já existe")
    stopifnot(identical(readLines(p[[etapa]]), "outra execução"))
    if (etapa < 3L) stopifnot(!file.exists(p[["json"]]))
    else erro(modulo$verificar_resultado_auditado(p[["json"]]))
    sem_temporarios(d)
  }
  cat("OK: falhas de preparação, interrupções entre publicações, conflitos tardios e limpeza exclusiva; nenhum marcador próprio após falha\n")

  # Falha na geração final do JSON deixa os CSVs completos sem marcador.
  d <- caso(); e <- carregar(); chamadas <- 0L; original <- e$.escrever_relatorio_auditoria
  e$.escrever_relatorio_auditoria <- function(r, con) {
    chamadas <<- chamadas + 1L
    if (chamadas == 2L) stop("falha JSON final")
    original(r, con)
  }
  erro(publicar(d, e), "falha JSON final")
  stopifnot(identical(unname(file.exists(caminhos(d))), c(TRUE, TRUE, FALSE)))
  sem_temporarios(d)
  # Alteração dos bytes publicados detectada antes do marcador.
  d <- caso(); e <- carregar(); original <- e$publicar_arquivo_seguro
  e$publicar_arquivo_seguro <- function(temp, dest) {
    original(temp, dest)
    if (endsWith(dest, "_auditoria_naturalidade.csv")) cat("alterado", file = caminhos(d)[["principal"]], append = TRUE)
  }
  erro(publicar(d, e), "Checksum")
  stopifnot(!file.exists(caminhos(d)[["json"]])); sem_temporarios(d)

  # Consumidor recusa hash/tamanho, contagem, ID e estrutura adulterados.
  d <- caso(); publicar(d); p <- caminhos(d)
  original_csv <- bytes(p[["principal"]]); original_json <- bytes(p[["json"]])
  cat("alteração", file = p[["principal"]], append = TRUE)
  erro(modulo$verificar_resultado_auditado(p[["json"]]), "Checksum")
  writeBin(original_csv, p[["principal"]])
  for (alteracao in c("quantidade", "quantidade_sem_contagens", "quantidade_auxiliar", "sha256", "id", "cobertura",
                     "caminho", "esquema", "sem_metadados", "sem_conferencia")) {
    r <- jsonlite::fromJSON(p[["json"]], simplifyVector = FALSE)
    if (alteracao == "quantidade") r$arquivos$principal$registros <- 8L
    if (alteracao == "quantidade_sem_contagens") {
      r$arquivos$principal$registros <- 8L
      r$contagens <- list(etarias = NULL, datas = NULL, naturalidade = NULL)
    }
    if (alteracao == "quantidade_auxiliar") r$arquivos$naturalidade$registros <- 8L
    if (alteracao == "sha256") r$arquivos$principal$sha256 <- strrep("0", 64L)
    if (alteracao == "id") r$id_execucao <- modulo$novo_id_execucao()
    if (alteracao == "cobertura") r$cobertura_datasus <- "completa"
    if (alteracao == "caminho") r$arquivos$principal$nome <- "../saida.csv"
    if (alteracao == "esquema") r$arquivos$principal$colunas <- list("APENAS_UMA")
    if (alteracao == "sem_metadados") r$metadados$versoes <- NULL
    if (alteracao == "sem_conferencia") r$horarios$conferencia_utc <- NULL
    con <- file(p[["json"]], "w"); modulo$.escrever_relatorio_auditoria(r, con); close(con)
    erro(modulo$verificar_resultado_auditado(p[["json"]]))
    writeBin(original_json, p[["json"]])
  }
  erro(modulo$verificar_resultado_auditado(p[["json"]], modulo$novo_id_execucao()), "Identificador")
  modulo$verificar_resultado_auditado(p[["json"]])
  cat("OK: checksums e metadados efetivos, estrutura, ID, cobertura e caminhos verificados pelo consumidor\n")

  # Validação de contagens recebidas por etapa; não reconstrói campos perdidos.
  for (tipo in c("final", "soma_datas", "fracionario", "ausente", "entre_etapas", "soma_naturalidade", "aumento_categoria")) {
    cts <- contagens
    if (tipo == "final") cts$datas$total_final_exportavel <- 5L
    if (tipo == "soma_datas") cts$datas$datas_validas <- 7L
    if (tipo == "fracionario") cts$etarias$excluidos_invalidos <- 0.5
    if (tipo == "ausente") cts$etarias$entrada <- NULL
    if (tipo == "entre_etapas") cts$naturalidade$apos_filtro_etario <- 8L
    if (tipo == "soma_naturalidade") cts$naturalidade$antes_filtros$ambiguas <- 3L
    if (tipo == "aumento_categoria") {
      cts$naturalidade$apos_demais_filtros$ambiguas <- 3L
      cts$naturalidade$apos_demais_filtros$ausentes <- 0L
    }
    d <- caso(); erro(publicar(d, cts = cts)); stopifnot(!any(file.exists(caminhos(d))))
  }
  for (posicoes in list(c(1, 1, 4, 5, 6), c(0, 3, 4, 5, 6), c(1, 3, 4, 5, 7),
                       c(1.5, 3, 4, 5, 6), c(NA, 3, 4, 5, 6), as.character(1:5))) {
    a <- auditoria; a$posicao_registro <- posicoes; d <- caso()
    erro(publicar(d, auxiliar = a), "Posições"); stopifnot(!any(file.exists(caminhos(d))))
  }
  d <- caso(); a <- auditoria; a$motivo[2L] <- "codigo_nao_encontrado"
  erro(publicar(d, auxiliar = a), "Ausência NA")
  d <- caso(); erro(publicar(d, principal = dados[-1L]), "Esquema principal")
  # Escritor que perde registro: validação lê CSV e rejeita antes de publicar.
  d <- caso(); e <- carregar(); original <- e$.escrever_csv_padrao
  e$.escrever_csv_padrao <- function(x, con) original(x[-1L, , drop = FALSE], con)
  erro(publicar(d, e), "quantidade"); stopifnot(!any(file.exists(caminhos(d)))); sem_temporarios(d)
  cat("OK: contagens incompatíveis, posições duplicadas/fracionárias/fora dos limites e perda na serialização são rejeitadas\n")

  # Dependência/sha256sum indisponível ou utilitário falhando: erro explícito.
  e <- carregar(); e$Sys.which <- function(...) ""
  erro(e$sha256_arquivo(p[["principal"]]), "indisponível")
  e <- carregar(); e$system2 <- function(...) structure("falha", status = 1L)
  erro(e$sha256_arquivo(p[["principal"]]), "sha256sum")
  e <- carregar(); e$requireNamespace <- function(...) FALSE
  d <- caso(); erro(publicar(d, e), "jsonlite"); stopifnot(!any(file.exists(caminhos(d))))
  stopifnot(length(unique(replicate(20L, modulo$novo_id_execucao()))) == 20L)
  erro(modulo$preparar_metadados_auditoria("SIM-DO", id_execucao = "id-invalido"), "UUID")
  stopifnot(!is.null(modulo$identificar_import_mds(".")), is.null(modulo$identificar_import_mds(raiz)))
  if (requireNamespace("data.table", quietly = TRUE)) {
    dt <- data.table::as.data.table(dados); at <- data.table::as.data.table(auditoria)
    bdt <- serialize(dt, NULL); bat <- serialize(at, NULL)
    d <- caso(); publicar(d, principal = dt, auxiliar = at)
    stopifnot(identical(serialize(dt, NULL), bdt), identical(serialize(at, NULL), bat))
  }
  cat("OK: falhas explícitas de dependências, UUIDs, identificação Git e entradas data.table preservadas\n")
  cat("Todos os testes de auditoria persistente passaram.\n")
})
