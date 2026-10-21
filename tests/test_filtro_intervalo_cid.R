# TZ=UTC Rscript --vanilla tests/test_filtro_intervalo_cid.R
# Referências locais/sintéticas. fetch_datasus só existe como função simulada.
local({
  suppressPackageStartupMessages(library(microdatasus))
  stopifnot(as.character(utils::packageVersion("microdatasus")) == "3.0.0")
  raiz <- normalizePath(".")
  m <- new.env(parent = globalenv())
  for (f in c("R/comum/cid.R", "R/sistemas/sim.R", "R/comum/exportacao.R", "R/comum/auditoria.R")) sys.source(f, m)
  erro <- function(expr, trecho = NULL) {
    mensagem <- tryCatch({force(expr); NULL}, error = function(e) conditionMessage(e))
    stopifnot(!is.null(mensagem))
    if (!is.null(trecho)) stopifnot(grepl(trecho, mensagem, fixed = TRUE))
  }
  oficial <- m$carregar_referencia_cid()
  erro(m$carregar_referencia_cid("https://exemplo.invalid/referencia.json"), "arquivo local")
  stopifnot(length(oficial$categorias) == 2090L, length(oficial$subcategorias) == 9153L,
    !"I14" %in% oficial$categorias,
    identical(m$interpretar_consulta_cid("I10-I15")$categorias, c("I10", "I11", "I12", "I13", "I15")),
    m$interpretar_consulta_cid("A00-A04")$modalidade == "intervalo",
    m$interpretar_consulta_cid("C00-C10")$modalidade == "intervalo")
  r <- oficial
  r$categorias <- c("A00", "A02", "A04", "I09", "I10", "I11", "I12", "I13", "I15", "I20", "I21")
  r$subcategorias <- c("A00.0", "A02.0", "I09.0", "I11.0", "I11.9", "I12.0", "I13.0", "I13.2", "I15.0", "I15.9", "I21.0")
  r$referencia$origem <- "Sintética"; r$referencia$versao <- "teste"; r$referencia$identificador <- "teste-com-lacunas"
  r$referencia$quantidade_categorias <- length(r$categorias)
  r$referencia$quantidade_subcategorias <- length(r$subcategorias)
  q <- m$interpretar_consulta_cid("I10-I15", r)
  stopifnot(identical(q$categorias, c("I10", "I11", "I12", "I13", "I15")),
    identical(m$interpretar_consulta_cid("A00-A04", r)$categorias, c("A00", "A02", "A04")))
  a <- m$interpretar_consulta_cid("A00-A04", r)
  stopifnot(identical(which(m$selecionar_cid(
    c("A00", "A000", "A00.0", "A01", "A010", "A02", "A020", "A02.0", "A03", "A04", "A040"), a)),
    c(1:3, 6:8, 10L)))
  for (entrada in c("I10-I15", "i10-i15", " I10 - I15 ", "I10\t-\tI15")) {
    stopifnot(identical(m$interpretar_consulta_cid(entrada, r), q))
  }
  invalidos <- c("I15-I10", "I10-J15", "I10--I15", "I 10-I15", "I1-I15", "I10-I150",
    "I10-I14", "I14-I15", "I10-I16", "I10-", "-I15", "I10-I15-I20", "I10-I15, I21", "I10-I15\n")
  for (x in invalidos) erro(m$interpretar_consulta_cid(x, r))
  stopifnot(identical(m$interpretar_consulta_cid("I10-I10", r)$categorias, "I10"))
  ruim <- r; ruim$referencia$quantidade_categorias <- 100
  erro(m$interpretar_consulta_cid("I10-I15", ruim), "incompleta")
  cat("OK: referência oficial geral, I14 ausente, limites e lacunas sintéticas, canonização e entradas inválidas\n")

  cids <- c("I09", "I10", "I11", "I12", "I13", "I14", "I15", "I16", "I110", "I11.0",
    "I119", "I11.9", "I111", "I11.1", "I150", "I15.0", "I15.9", "I11XYZ", NA, "", " I110",
    "i110", "I12..0", "I1100", "I11.", "I15", "I10.0")
  # O SIM já converte cid_valor para maiúsculas. O campo original não é reescrito.
  codigos <- toupper(cids)
  esperadas <- c(2:5, 7L, 9:12, 15:17, 22L, 26L)
  stopifnot(identical(which(m$selecionar_cid(codigos, q)), esperadas),
    identical(which(m$selecionar_cid(codigos, m$interpretar_consulta_cid("I10-I10", r))), 2L),
    identical(m$selecionar_cid(character(), q), logical()))
  for (prefixo in c("I2", "I21", "I210", "I21.0", " I11", "", "i11", "DRC")) {
    antigo <- startsWith(codigos, prefixo)
    atual <- m$selecionar_cid(codigos, m$interpretar_consulta_cid(prefixo))
    stopifnot(identical(atual, antigo))
  }
  stopifnot(all(m$selecionar_cid(codigos, m$interpretar_consulta_cid("ALL"))))
  cat("OK: categorias, subcategorias atribuídas, ponto/compacto, códigos inválidos/ausentes e prefixos literais\n")

  prefixos <- c("I2", "I21", "I210", "I21.0", "I219", "I11", NA, " I21", "", "I21XYZ", "I2100")
  esperados_prefixos <- list(I2 = c(1:5, 10:11), I21 = c(2:5, 10:11), I210 = c(3L, 11L),
    "I21.0" = 4L, ALL = 1:11)
  for (f in names(esperados_prefixos)) {
    mask <- m$selecionar_cid(prefixos, m$interpretar_consulta_cid(f))
    stopifnot(identical(which(mask), esperados_prefixos[[f]]))
  }
  stopifnot(all(m$selecionar_cid(c("I120", "I12.0", "I132", "I13.2"), q)))

  n <- length(cids)
  bruto <- data.frame(IDADE = rep("418", n), DTOBITO = rep("01012020", n), DTNASC = rep("01012002", n),
    NATURAL = rep("821", n), SEXO = rep("1", n), RACACOR = rep("1", n), CAUSABAS = cids,
    ESTCIV = rep("1", n), LOCOCOR = rep("1", n), CODESTAB = sprintf("%07d", seq_len(n)),
    CODMUNRES = rep("211130", n), CODMUNNATU = rep("211130", n), ASSISTMED = rep("1", n))
  bruto$IDADE[3L] <- "417"; bruto$SEXO[4L] <- "2"; bruto$RACACOR[5L] <- "4"
  bruto$DTOBITO[9L] <- NA_character_
  bruto <- bruto[c(seq_len(n), 9L), ]; rownames(bruto) <- NULL
  antes <- serialize(bruto, NULL)
  saida <- m$preparar_exportacao_sim(bruto, cid = q$valor, consulta_cid = q)
  todas <- c(esperadas, 28L)
  stopifnot(identical(saida$ESTABELECIMENTO, bruto$CODESTAB[todas]),
    identical(saida$DOENCA, toupper(bruto$CAUSABAS[todas])), identical(names(saida), m$colunas_principal_auditoria()),
    identical(attr(saida, "auditoria_naturalidade")$registro_id, as.character(todas)),
    identical(attr(saida, "auditoria_naturalidade")$posicao_csv, seq_along(todas)),
    identical(serialize(bruto, NULL), antes), sum(is.na(saida$DATA)) == 2L)
  s <- m$preparar_exportacao_sim(bruto, cid = q$valor, consulta_cid = q, idade_min = 18, sexo = "Masculino", raca = "Branca")
  sobreviventes <- c(2L, 7L, 9:12, 15:17, 22L, 26L, 28L)
  stopifnot(identical(s$ESTABELECIMENTO, bruto$CODESTAB[sobreviventes]),
    identical(s$DOENCA, toupper(bruto$CAUSABAS[sobreviventes])),
    attr(s, "contagens_etarias")$apos_demais_filtros == length(sobreviventes),
    attr(s, "contagens_datas")$total_final_exportavel == length(sobreviventes),
    attr(s, "contagens_naturalidade")$apos_demais_filtros$total == length(sobreviventes))
  dt <- data.table::as.data.table(bruto); antes_dt <- serialize(dt, NULL)
  stopifnot(identical(m$preparar_exportacao_sim(dt, cid = q$valor, consulta_cid = q), saida),
    identical(serialize(dt, NULL), antes_dt))
  stopifnot(identical(m$preparar_exportacao_sim(bruto, cid = "")$ESTABELECIMENTO,
                      bruto$CODESTAB[!is.na(bruto$CAUSABAS)]),
    nrow(m$preparar_exportacao_sim(bruto, cid = "ALL")) == nrow(bruto))
  bruto_prefixos <- bruto[rep(2L, length(prefixos)), ]; bruto_prefixos$CAUSABAS <- prefixos
  bruto_prefixos$CODESTAB <- sprintf("%07d", seq_along(prefixos))
  for (f in names(esperados_prefixos)) {
    p <- m$preparar_exportacao_sim(bruto_prefixos, cid = f)
    stopifnot(identical(p$ESTABELECIMENTO, bruto_prefixos$CODESTAB[esperados_prefixos[[f]]]),
      identical(p$DOENCA, prefixos[esperados_prefixos[[f]]]))
  }
  q_vazia <- m$interpretar_consulta_cid("A00-A04", r)
  vazio <- m$preparar_exportacao_sim(bruto, cid = q_vazia$valor, consulta_cid = q_vazia)
  stopifnot(nrow(vazio) == 0L, identical(names(vazio), m$colunas_principal_auditoria()))
  cat("OK: filtros epidemiológicos, 14 colunas, valores, IDs, duplicatas, ordem, contagens e entradas preservadas\n")

  nome <- m$construir_nome_csv("SIM-DO", "MA", 2014, 2014, cid = q$valor, idade_min = 18, consulta_cid = q)
  stopifnot(identical(nome, "dados_SIM-DO_MA_2014_2014_cid-intervalo-I10-I15_idade_18mais.csv"),
    identical(m$construir_nome_csv("SIM-DO", "MA", 2014, 2014, cid = "I21", idade_min = 18),
      "dados_SIM-DO_MA_2014_2014_I21_idade_18mais.csv"))
  # O orquestrador verdadeiro é avaliado com coleta estritamente simulada.
  codigo <- parse(file.path(raiz, "R/coletar_dados.R"))
  fetch <- which(vapply(codigo, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name("dados_brutos")), logical(1)))
  stopifnot(length(fetch) == 1L, identical(codigo[[fetch]][[3L]][[1L]], as.name("fetch_datasus")))
  temp <- tempfile("import-mds-intervalos-"); dir.create(temp)
  on.exit(unlink(temp, recursive = TRUE), add = TRUE)
  executar <- function(cid) {
    p <- tempfile("projeto ", tmpdir = temp)
    for (f in c("R/coletar_dados.R", "R/comum/cid.R", "R/sistemas/sim.R", "R/comum/exportacao.R", "R/comum/auditoria.R")) {
      dir.create(dirname(file.path(p, f)), recursive = TRUE, showWarnings = FALSE)
      stopifnot(file.copy(file.path(raiz, f), file.path(p, f)))
    }
    dir.create(file.path(p, "referencias/cid10"), recursive = TRUE)
    jsonlite::write_json(r, file.path(p, "referencias/cid10/oms_2019_codigos.json"), auto_unbox = TRUE)
    e <- new.env(parent = globalenv()); e$chamadas <- 0L
    args <- c("--cid", cid, "--uf", "MA", "--year_start", "2014", "--year_end", "2014", "--idade_min", "18")
    e$commandArgs <- function(trailingOnly = FALSE) if (trailingOnly) args else c("Rscript", paste0("--file=", file.path(p, "R/coletar_dados.R")), args)
    e$fetch_datasus <- function(...) {e$chamadas <- e$chamadas + 1L; bruto}
    mensagem <- NULL
    invisible(capture.output(tryCatch(eval(codigo, e), error = function(err) mensagem <<- conditionMessage(err))))
    list(e = e, erro = mensagem, projeto = p)
  }
  for (x in invalidos) {
    resultado <- executar(x)
    stopifnot(!is.null(resultado$erro), resultado$e$chamadas == 0L, !dir.exists(file.path(resultado$projeto, "Dados")))
  }
  resultado <- executar(" i10 - i15 ")
  stopifnot(is.null(resultado$erro), resultado$e$chamadas == 1L)
  j <- m$verificar_resultado_auditado(resultado$e$destinos$relatorio)
  detalhe <- j$metadados$consulta$filtros$cid_intervalo
  stopifnot(j$versao_esquema == "1.1.0", j$metadados$consulta$filtros$cid == "I10-I15",
    detalhe$modalidade == "intervalo", detalhe$referencia$versao == "teste",
    identical(unlist(detalhe$categorias_elegiveis, use.names = FALSE), q$categorias),
    j$arquivos$principal$sha256 == m$sha256_arquivo(resultado$e$destinos$principal),
    j$arquivos$principal$registros == 14L, length(j$arquivos$principal$colunas) == 14L,
    basename(resultado$e$destinos$principal) == nome)
  prefixo <- executar("I21")
  j0 <- m$verificar_resultado_auditado(prefixo$e$destinos$relatorio)
  stopifnot(is.null(j0$metadados$consulta$filtros$cid_intervalo), j0$metadados$consulta$filtros$cid == "I21")
  cat("OK: consulta inválida antes da reserva/coleta, nomes, três artefatos, JSON 1.1 opcional e checksums; sem internet\n")
  cat("PASSOU: intervalos gerais por referência atribuída e prefixos legados, sem downloads ou alteração de microdados reais.\n")
})
