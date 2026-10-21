# TZ=UTC Rscript --vanilla tests/test_sim_auditoria_integracao.R
# Projeto copiado para diretórios temporários, microdados inteiramente sintéticos.
# A coleta NÃO é executada: fetch_datasus é substituída no ambiente do script.
local({
  raiz <- normalizePath(".")
  modulo <- new.env(parent = globalenv())
  sys.source("R/comum/exportacao.R", modulo)
  sys.source("R/comum/auditoria.R", modulo)
  stopifnot(as.character(utils::packageVersion("microdatasus")) == "3.0.0")
  codigo <- parse("R/coletar_dados.R")
  fetch <- which(vapply(codigo, function(x) is.call(x) && identical(x[[1L]], as.name("<-")) &&
    identical(x[[2L]], as.name("dados_brutos")), logical(1)))
  # Se o contrato mudar para uma chamada qualificada que ignore a simulação,
  # interrompe ANTES de avaliar qualquer expressão do orquestrador.
  stopifnot(length(fetch) == 1L, identical(codigo[[fetch]][[3L]][[1L]], as.name("fetch_datasus")),
    sum(all.names(codigo) == "fetch_datasus") == 1L)
  temporario <- tempfile("import-mds-sim-auditoria-")
  stopifnot(dir.create(temporario))
  on.exit(unlink(temporario, recursive = TRUE), add = TRUE)
  arquivos <- c("R/coletar_dados.R", "R/sistemas/sim.R", "R/comum/exportacao.R", "R/comum/auditoria.R")
  projeto <- function() {
    d <- tempfile("projeto com espaços-", tmpdir = temporario)
    for (p in arquivos) {
      dir.create(dirname(file.path(d, p)), recursive = TRUE, showWarnings = FALSE)
      stopifnot(file.copy(file.path(raiz, p), file.path(d, p)))
    }
    # Um CSV histórico SINTÉTICO e um temporário alheio precisam sobreviver.
    utils::write.csv(data.frame(valor = "resultado anterior sintético"), file.path(d, "historico.csv"), row.names = FALSE)
    writeLines("temporário alheio", file.path(d, ".import-mds-csv-alheio.tmp"))
    d
  }
  bytes <- function(p) readBin(p, "raw", n = file.info(p)$size)
  freq <- table(microdatasus::tabNaturalidade$cod)
  ambiguo <- "44"
  stopifnot(freq[ambiguo] == 2L)
  base <- data.frame(
    NATURAL = c("821", ambiguo, NA, "0001 ", "821", ambiguo, "NA", "821", "", "   ", "821"),
    IDADE = c("418", "460", "999", "618", "417", "500", "418", "306", "400", "312", "418"),
    DTOBITO = c("01012020", NA, "", "  ", "31022020", "01012020xyz", "010120", "29022020", NA, "32132020", "01012020"),
    DTNASC = rep("01011980", 11L), DTATESTADO = rep("01032020", 11L),
    SEXO = c(rep("1", 5L), "2", rep("1", 5L)), RACACOR = c(rep("1", 5L), "4", rep("1", 5L)),
    CAUSABAS = c("I21", "I210", "I21", "I21", "I21", "I219", "C50", "I219", "I21", "I21", NA),
    CODESTAB = sprintf("%07d", 1:11), CODMUNRES = rep("211130", 11L), CODMUNNATU = rep("211130", 11L),
    ESTCIV = rep("1", 11L), LOCOCOR = rep("1", 11L), ASSISTMED = rep("1", 11L),
    OCUP = rep("000000", 11L), OCUPMAE = rep("000000", 11L), stringsAsFactors = FALSE)
  entrada <- base[c(1:11, 2L), ]
  rownames(entrada) <- NULL
  argumentos <- c("--system", "SIM-DO", "--uf", "MA", "--year_start", "2020", "--year_end", "2024",
    "--month_start", "2", "--month_end", "11", "--cid", "I21")
  executar <- function(args = argumentos, dados = entrada, falha = "", ocupar = NULL,
                       tabela_naturalidade = NULL, fora_raiz = FALSE) {
    d <- projeto()
    anterior <- getwd()
    on.exit(setwd(anterior), add = TRUE)
    setwd(d)
    nome <- modulo$construir_nome_csv("SIM-DO", "MA", 2020, 2024, cid = "I21")
    pasta <- file.path(d, "Dados", sub("[.]csv$", "", nome))
    destinos <- list(principal = file.path(pasta, nome),
      naturalidade = file.path(pasta, "logs", sub("[.]csv$", "_auditoria_naturalidade.csv", nome)),
      relatorio = file.path(pasta, "logs", sub("[.]csv$", "_relatorio.json", nome)))
    if (!is.null(ocupar)) {
      dir.create(file.path(pasta, "logs"), recursive = TRUE)
      writeLines("arquivo existente", destinos[[ocupar]])
    }
    anteriores <- c(file.path(d, "historico.csv"), file.path(d, ".import-mds-csv-alheio.tmp"))
    hashes <- vapply(anteriores, modulo$sha256_arquivo, character(1))
    hash_ocupado <- if (!is.null(ocupar)) modulo$sha256_arquivo(destinos[[ocupar]]) else NULL
    e <- new.env(parent = globalenv())
    e$commandArgs <- function(trailingOnly = FALSE) {
      if (trailingOnly) args else c("Rscript", paste0("--file=", file.path(d, "R/coletar_dados.R")), args)
    }
    e$chamadas <- 0L
    e$fetch_datasus <- function(...) {
      e$chamadas <- e$chamadas + 1L
      e$parametros_coleta <- list(...)
      if (identical(falha, "coleta")) stop("coleta simulada falhou")
      dados
    }
    e$source <- function(file, local = FALSE) {
      stopifnot(isTRUE(local), file %in% file.path(d, arquivos))
      sys.source(file, e)
      if (basename(file) == "exportacao.R" && falha %in% c("criar_dados", "criar_extracao", "criar_logs")) {
        e$dir.create <- function(path, ...) {
          bloquear <- switch(falha, criar_dados = basename(path) == "Dados",
            criar_logs = basename(path) == "logs", criar_extracao = basename(path) == sub("[.]csv$", "", nome))
          if (bloquear) FALSE else base::dir.create(path, ...)
        }
      }
      if (basename(file) == "sim.R" && !is.null(tabela_naturalidade)) {
        converter <- e$converter_naturalidade_sim
        e$converter_naturalidade_sim <- function(codigos) converter(codigos, tabela = tabela_naturalidade)
      }
      if (basename(file) == "auditoria.R") {
        if (identical(falha, "escrita")) e$.escrever_csv_padrao <- function(x, con) {
          writeLines("parcial", con); stop("escrita simulada falhou")
        }
        if (falha %in% c("apos_principal", "apos_auxiliar")) {
          publicar <- e$publicar_arquivo_seguro
          chamadas <- 0L
          e$publicar_arquivo_seguro <- function(temp, destino) {
            chamadas <<- chamadas + 1L
            if (chamadas == if (falha == "apos_principal") 2L else 3L) stop("publicação simulada interrompida")
            publicar(temp, destino)
          }
        }
        if (identical(falha, "consumidor")) e$verificar_resultado_auditado <- function(...) stop("conferência final simulada falhou")
      }
      if (basename(file) == "sim.R" && falha %in% c("atributo", "posicoes", "contagens", "descricao", "contagens_indisponiveis")) {
        preparar <- e$preparar_exportacao_sim
        e$preparar_exportacao_sim <- function(...) {
          x <- preparar(...)
          a <- attr(x, "auditoria_naturalidade")
          if (falha == "atributo") attr(x, "auditoria_naturalidade") <- NULL
          if (falha == "posicoes") { a$posicao_csv[2L] <- 1L; attr(x, "auditoria_naturalidade") <- a }
          if (falha == "descricao") { a$naturalidade_descricao[1L] <- "incorreta"; attr(x, "auditoria_naturalidade") <- a }
          if (falha == "contagens") {
            cts <- attr(x, "contagens_datas"); cts$total_final_exportavel <- 999L; attr(x, "contagens_datas") <- cts
          }
          if (falha == "contagens_indisponiveis") attr(x, "contagens_etarias") <- NULL
          x
        }
      }
    }
    pasta_trabalho <- d
    if (fora_raiz) {
      pasta_trabalho <- tempfile("outra pasta-", tmpdir = temporario)
      stopifnot(dir.create(pasta_trabalho))
      setwd(pasta_trabalho)
    }
    mensagem <- NULL
    saida <- capture.output(tryCatch(eval(codigo, e), error = function(err) mensagem <<- conditionMessage(err)))
    stopifnot(identical(vapply(anteriores, modulo$sha256_arquivo, character(1)), hashes),
      identical(list.files(d, pattern = "^\\.import-mds-csv-", all.files = TRUE), ".import-mds-csv-alheio.tmp"))
    if (!is.null(ocupar)) stopifnot(identical(hash_ocupado, modulo$sha256_arquivo(destinos[[ocupar]])))
    list(ambiente = e, erro = mensagem, saida = saida, diretorio = d,
         destinos_previstos = destinos, pasta_trabalho = pasta_trabalho)
  }
  artefatos <- function(resultado) {
    if (is.null(resultado$ambiente$destinos)) resultado$destinos_previstos else resultado$ambiente$destinos
  }
  sucesso <- function(r) {
    stopifnot(is.null(r$erro), r$ambiente$chamadas == 1L, all(file.exists(unlist(artefatos(r)))),
      any(grepl("Arquivo gerado:", r$saida, fixed = TRUE)))
    modulo$verificar_resultado_auditado(artefatos(r)$relatorio, r$ambiente$metadados$id_execucao)
  }
  antes <- serialize(entrada, NULL)
  r <- executar()
  j <- sucesso(r)
  esperado_estab <- sprintf("%07d", c(1:6, 8:10, 2L))
  stopifnot(identical(r$ambiente$dados_final$ESTABELECIMENTO, esperado_estab),
    identical(serialize(entrada, NULL), antes), ncol(r$ambiente$dados_final) == 14L,
    identical(names(r$ambiente$dados_final), modulo$colunas_principal_auditoria()),
    identical(r$ambiente$dados_final$DATA, as.Date(c("2020-01-01", NA, NA, NA, NA, NA, "2020-02-29", NA, NA, NA))),
    identical(r$ambiente$dados_final$IDADE, c("18", "60", NA, NA, "17", "100", NA, "0", NA, "60")),
    identical(r$ambiente$parametros_coleta, list(year_start = 2020, year_end = 2024, month_start = 2,
      month_end = 11, uf = "MA", information_system = "SIM-DO", stop_on_error = TRUE)),
    j$versao_esquema == "1.1.0", j$cobertura_datasus == "nao_verificada", j$publicacao$situacao == "concluida",
    j$arquivos$principal$registros == 10L, j$arquivos$naturalidade$registros == 7L,
    j$metadados$consulta$periodo$month_start == 2L, j$metadados$consulta$periodo$month_end == 11L,
    is.null(j$metadados$consulta$filtros$idade_min), is.null(j$metadados$consulta$filtros$idade_max),
    is.null(j$metadados$versoes$Python), "metadados.versoes.Python" %in% unlist(j$informacoes_indisponiveis),
    j$metadados$versoes$microdatasus == "3.0.0", j$metadados$versoes$jsonlite == as.character(utils::packageVersion("jsonlite")))
  # Expectativas explícitas anteriores aos filtros, distintas do resultado final.
  ce <- j$contagens$etarias; cd <- j$contagens$datas; cn <- j$contagens$naturalidade
  stopifnot(ce$entrada == 12L, ce$idades_validas == 9L, ce$idades_desconhecidas == 1L, ce$idades_invalidas == 2L,
    ce$apos_filtro_etario == 12L, ce$apos_demais_filtros == 10L,
    cd$datas_validas == 3L, cd$datas_ausentes == 5L, cd$datas_invalidas == 4L,
    cd$preservados_apos_validacao == 12L, cd$excluidos_por_data == 0L, cd$total_final_exportavel == 10L,
    identical(unlist(cn$antes_filtros, use.names = FALSE), c(12L, 4L, 3L, 2L, 3L)),
    identical(unlist(cn$apos_demais_filtros, use.names = FALSE), c(10L, 3L, 3L, 1L, 3L)))
  a <- modulo$ler_auditoria_naturalidade(artefatos(r)$naturalidade, 10L)
  esperado_aux <- data.frame(posicao_registro = c(2, 3, 4, 6, 8, 9, 10),
    codigo_original = c(ambiguo, NA, "0001 ", ambiguo, "", "   ", ambiguo),
    situacao = c("ambigua", "ausente", "sem_correspondencia", "ambigua", "ausente", "ausente", "ambigua"),
    motivo = c("codigo_corresponde_a_dois_paises_distintos", "codigo_ausente_na", "codigo_nao_encontrado",
               "codigo_corresponde_a_dois_paises_distintos", "codigo_ausente_vazio", "codigo_ausente_espacos",
               "codigo_corresponde_a_dois_paises_distintos"),
    descricao = c("CAMBOJA / LAOS", NA, NA, "CAMBOJA / LAOS", NA, NA, "CAMBOJA / LAOS"))
  stopifnot(identical(a, esperado_aux), !"registro_id" %in% names(a),
    r$ambiente$dados_final$ESTADO_NATURALIDADE[1L] == "MARANHAO",
    identical(r$ambiente$dados_final$ESTABELECIMENTO[a$posicao_registro], sprintf("%07d", c(2, 3, 4, 6, 9, 10, 2))))
  legado <- file.path(r$diretorio, "serializacao_anterior.csv")
  utils::write.csv(r$ambiente$dados_final, legado, row.names = FALSE)
  stopifnot(identical(bytes(artefatos(r)$principal), bytes(legado)),
    identical(j$arquivos$principal$sha256, modulo$sha256_arquivo(artefatos(r)$principal)))
  cat("OK: coleta única simulada, três artefatos, bytes legados, 14 campos, datas/idades, duplicatas, contagens e posições explícitas\n")

  fora <- executar(fora_raiz = TRUE)
  sucesso(fora)
  stopifnot(!dir.exists(file.path(fora$pasta_trabalho, "Dados")),
    identical(fora$ambiente$raiz_projeto, fora$diretorio),
    identical(bytes(artefatos(fora)$principal), bytes(artefatos(r)$principal)))
  cat("OK: fluxo completo simulado iniciado em outra pasta preserva saída na raiz do projeto\n")

  # Três regras no fluxo completo, após exclusões por idade/CID/sexo/raça.
  padronizada <- base[rep(1L, 9L), ]; rownames(padronizada) <- NULL
  padronizada$NATURAL <- c("44", "821", "73", "81", "44", "81", "44", "73", "81")
  padronizada$IDADE <- c("418", "418", "460", "500", "417", rep("418", 4L))
  padronizada$CAUSABAS <- c(rep("I21", 5L), "C50", rep("I21", 3L))
  padronizada$SEXO[7L] <- "2"; padronizada$RACACOR[8L] <- "4"
  padronizada[9L, ] <- padronizada[4L, ] # Duplicata legítima de código 81.
  r <- executar(c(argumentos, "--idade_min", "18", "--sexo", "Masculino", "--raca", "Branca"), dados = padronizada)
  j <- sucesso(r)
  a <- modulo$ler_auditoria_naturalidade(artefatos(r)$naturalidade, 5L)
  stopifnot(identical(r$ambiente$dados_final$ESTADO_NATURALIDADE,
      c("CAMBOJA / LAOS", "MARANHAO", "IRLANDA", rep("ILHAS FALKLAND (MALVINAS)", 2L))),
    identical(a, data.frame(posicao_registro = c(1, 3, 4, 5), codigo_original = c("44", "73", "81", "81"),
      situacao = c("ambigua", rep("inequivoca", 3L)),
      motivo = c("codigo_corresponde_a_dois_paises_distintos", rep("equivalencia_nomenclatura_geografica", 3L)),
      descricao = c("CAMBOJA / LAOS", "IRLANDA", rep("ILHAS FALKLAND (MALVINAS)", 2L)))),
    identical(unlist(j$contagens$naturalidade$antes_filtros, use.names = FALSE), c(9L, 6L, 3L, 0L, 0L)),
    identical(unlist(j$contagens$naturalidade$apos_demais_filtros, use.names = FALSE), c(5L, 4L, 1L, 0L, 0L)),
    j$contagens$etarias$apos_filtro_etario == 8L, j$contagens$etarias$apos_demais_filtros == 5L,
    ncol(r$ambiente$dados_final) == 14L, j$versao_esquema == "1.1.0")
  cat("OK: 44 permanece ambíguo no auxiliar; 73/81 rastreáveis sem ambiguidade, posições e contagens após filtros\n")

  r <- executar(c(argumentos, "--idade_min", "18"))
  j <- sucesso(r)
  stopifnot(identical(r$ambiente$dados_final$ESTABELECIMENTO, sprintf("%07d", c(1, 2, 6, 2))),
    j$contagens$etarias$apos_filtro_etario == 6L, j$contagens$etarias$apos_demais_filtros == 4L,
    j$contagens$etarias$excluidos_desconhecidos == 1L, j$contagens$etarias$excluidos_invalidos == 2L,
    j$contagens$etarias$excluidos_fora_limites == 3L,
    identical(modulo$ler_auditoria_naturalidade(artefatos(r)$naturalidade, 4L)$posicao_registro, c(2, 3, 4)))
  r <- executar(c(argumentos, "--idade_min", "18", "--sexo", "Masculino", "--raca", "Branca"))
  sucesso(r)
  stopifnot(identical(r$ambiente$dados_final$ESTABELECIMENTO, sprintf("%07d", c(1, 2, 2))),
    identical(modulo$ler_auditoria_naturalidade(artefatos(r)$naturalidade, 3L)$posicao_registro, c(2, 3)))
  r <- executar(c(argumentos, "--idade_min", "18", "--idade_max", "59"))
  j <- sucesso(r)
  stopifnot(identical(r$ambiente$dados_final$ESTABELECIMENTO, "0000001"),
    j$metadados$consulta$filtros$idade_min == 18, j$metadados$consulta$filtros$idade_max == 59,
    endsWith(artefatos(r)$principal, "_idade_18-59.csv"))
  r <- executar(c(argumentos, "--faixa", "60+"))
  j <- sucesso(r)
  stopifnot(j$metadados$consulta$filtros$idade_min == 60, is.null(j$metadados$consulta$filtros$idade_max),
    endsWith(artefatos(r)$principal, "_60+.csv"))
  r <- executar(dados = entrada[c(1, 5, 8, 11), ])
  j <- sucesso(r); stopifnot(j$arquivos$naturalidade$registros == 0L)
  args_vazio <- argumentos; args_vazio[length(args_vazio)] <- "Z99"
  r <- executar(args_vazio)
  j <- sucesso(r)
  stopifnot(j$arquivos$principal$registros == 0L, j$arquivos$naturalidade$registros == 0L,
    ncol(r$ambiente$dados_final) == 14L)
  # O texto literal NA só vira ausência quando o processador assim o classifica.
  args_c50 <- argumentos; args_c50[length(args_c50)] <- "C50"
  r <- executar(args_c50); sucesso(r)
  stopifnot(identical(modulo$ler_auditoria_naturalidade(artefatos(r)$naturalidade, 1L)$codigo_original, "NA"),
    is.na(r$ambiente$dados_final$DATA[1L]))
  # Ressalva inequívoca também deve ser persistida; a referência sintética só
  # substitui o argumento tabela da função do projeto, nunca a tabela do pacote.
  dados_repetidos <- entrada[1L, ]; dados_repetidos$NATURAL <- "001"
  r <- executar(dados = dados_repetidos,
    tabela_naturalidade = data.frame(cod = c("001", "001"), nome = c("Repetida", "Repetida")))
  sucesso(r)
  stopifnot(identical(modulo$ler_auditoria_naturalidade(artefatos(r)$naturalidade, 1L),
    data.frame(posicao_registro = 1, codigo_original = "001", situacao = "inequivoca",
               motivo = "descricoes_identicas_repetidas", descricao = "Repetida")))
  r <- executar(falha = "contagens_indisponiveis"); j <- sucesso(r)
  stopifnot(is.null(j$contagens$etarias), "contagens.etarias" %in% unlist(j$informacoes_indisponiveis),
    j$contagens$datas$entrada == 12L, j$arquivos$principal$registros == 10L)
  args_nacional <- argumentos; args_nacional[match("--uf", args_nacional) + 1L] <- "ALL"
  r <- executar(args_nacional); j <- sucesso(r)
  stopifnot(j$metadados$consulta$uf == "ALL", j$metadados$consulta$parametros$uf == "all",
    r$ambiente$parametros_coleta$uf == "all", endsWith(artefatos(r)$principal, "dados_SIM-DO_BR_2020_2024_I21.csv"))
  r <- executar(c(argumentos, "--idade_min", "-1"))
  stopifnot(!is.null(r$erro), r$ambiente$chamadas == 0L,
    !any(grepl("Arquivo gerado:", r$saida, fixed = TRUE)))
  cat("OK: filtros atuais e legado, posições após seleção, auditoria vazia, resultado vazio e código literal NA\n")

  for (ocupado in c("principal", "naturalidade", "relatorio")) {
    r <- executar(ocupar = ocupado)
    stopifnot(grepl("já existe", r$erro, fixed = TRUE), r$ambiente$chamadas == 0L,
      !any(grepl("Arquivo gerado:", r$saida, fixed = TRUE)))
  }
  for (f in c("criar_dados", "criar_extracao", "criar_logs")) {
    r <- executar(falha = f)
    stopifnot(!is.null(r$erro), r$ambiente$chamadas == 0L,
      !any(file.exists(unlist(artefatos(r)))), !any(grepl("Arquivo gerado:", r$saida, fixed = TRUE)))
  }
  for (f in c("coleta", "escrita", "apos_principal", "apos_auxiliar", "atributo", "posicoes", "contagens", "descricao")) {
    r <- executar(falha = f)
    stopifnot(!is.null(r$erro), r$ambiente$chamadas == 1L,
      !file.exists(artefatos(r)$relatorio), !any(grepl("Arquivo gerado:", r$saida, fixed = TRUE)),
      file.exists(artefatos(r)$principal) == (f %in% c("apos_principal", "apos_auxiliar")),
      file.exists(artefatos(r)$naturalidade) == (f == "apos_auxiliar"))
  }
  r <- executar(falha = "consumidor")
  stopifnot(!is.null(r$erro), all(file.exists(unlist(artefatos(r)))),
    !any(grepl("Arquivo gerado:", r$saida, fixed = TRUE)))
  # Os arquivos não são apagados se a conferência final falhar. Um consumidor
  # independente consegue verificá-los; a falha acima é exclusivamente simulada.
  modulo$verificar_resultado_auditado(artefatos(r)$relatorio)
  cat("OK: três conflitos impedem coleta; falhas de escrita/publicação/vínculo propagadas, sem sucesso ou remoção de definitivos\n")

  # Processo R real, mas com a chamada de coleta substituída no seu ambiente.
  for (f in c("sucesso", "conflito", "escrita", "apos_principal")) {
    d <- projeto(); saveRDS(entrada, file.path(d, "entrada.rds"))
    pasta <- file.path(d, "Dados", "dados_SIM-DO_MA_2020_2024_I21")
    principal <- file.path(pasta, "dados_SIM-DO_MA_2020_2024_I21.csv")
    destino_json <- file.path(pasta, "logs", "dados_SIM-DO_MA_2020_2024_I21_relatorio.json")
    if (f == "conflito") {
      dir.create(dirname(destino_json), recursive = TRUE)
      writeLines("resultado anterior", destino_json)
    }
    runner <- c(paste0("setwd(", encodeString(d, quote = '"'), ")"),
      "e <- new.env(parent=globalenv())",
      "e$fetch_datasus <- function(...) {writeLines('simulada', 'coleta_chamada'); readRDS('entrada.rds')}")
    if (f %in% c("escrita", "apos_principal")) runner <- c(runner,
      "e$source <- function(file, local=FALSE) {sys.source(file, e); if (basename(file)=='auditoria.R') {",
      if (f == "escrita") "e$.escrever_csv_padrao <- function(x,con) stop('escrita simulada falhou')" else
        "original <- e$publicar_arquivo_seguro; n <- 0L; e$publicar_arquivo_seguro <- function(t,d) {n <<- n+1L; if(n==2L) stop('publicação simulada interrompida'); original(t,d)}",
      "}}")
    runner <- c(runner, "sys.source('R/coletar_dados.R', envir=e)")
    script <- file.path(d, "runner.R"); writeLines(runner, script)
    output <- suppressWarnings(system2(file.path(R.home("bin"), "Rscript"),
      c("--vanilla", shQuote(script), argumentos), stdout = TRUE, stderr = TRUE))
    status <- attr(output, "status"); if (is.null(status)) status <- 0L
    stopifnot((status == 0L) == (f == "sucesso"), file.exists(file.path(d, "coleta_chamada")) == (f != "conflito"),
      any(grepl("Arquivo gerado:", output, fixed = TRUE)) == (f == "sucesso"))
    if (f == "sucesso") modulo$verificar_resultado_auditado(destino_json)
    else if (f == "conflito") stopifnot(identical(readLines(destino_json), "resultado anterior"))
    else stopifnot(!file.exists(destino_json))
    stopifnot(file.exists(principal) == (f %in% c("sucesso", "apos_principal")))
  }
  cat("OK: Rscript propaga erro com saída não zero; conclusão somente após verificação; nenhum download\n")
  cat("PASSOU: integração SIM e auditoria, conflitos antecipados, falhas controladas, CSVs históricos sintéticos preservados.\n")
})
