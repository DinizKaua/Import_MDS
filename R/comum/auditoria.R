# Infraestrutura isolada: carregar exportacao.R no mesmo ambiente antes do uso.
# Não coleta, não filtra registros e não deduz qualidade epidemiológica do CSV.
colunas_principal_auditoria <- function() {
  c("IDADE", "DATA_DE_NASCIMENTO", "ESTADO_CIVIL", "SEXO", "RACA_COR", "LOCAL_OBITO",
    "ESTABELECIMENTO", "DATA", "ESTADO_RESIDENCIA", "MUNICIPIO_RESIDENCIA",
    "ESTADO_NATURALIDADE", "MUNICIPIO_NATURALIDADE", "ASSISTENCIA_MEDICA", "DOENCA")
}

colunas_naturalidade_auditoria <- function() {
  c("posicao_registro", "codigo_original", "situacao", "motivo", "descricao")
}

.texto_auditoria <- function(x) {
  is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
}

.inteiro_auditoria <- function(x) {
  is.numeric(x) && length(x) == 1L && !is.na(x) && is.finite(x) &&
    x >= 0 && x == floor(x) && x <= 2^53 - 1
}

.exigir_auditoria <- function(condicao, mensagem) {
  if (!isTRUE(condicao)) stop(mensagem, call. = FALSE)
}

novo_id_execucao <- function() {
  # UUID do kernel Linux: não depende do estado pseudoaleatório da sessão R.
  id <- readLines("/proc/sys/kernel/random/uuid", n = 1L, warn = FALSE)
  .validar_id_execucao(id)
  id
}

.validar_id_execucao <- function(id) {
  .exigir_auditoria(.texto_auditoria(id) &&
    grepl("\\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\z", id, perl = TRUE),
    "Identificador de execução deve ser um UUID v4.")
}

.utc_auditoria <- function(instante) {
  if (is.null(instante)) return(NULL)
  .exigir_auditoria(inherits(instante, "POSIXct") && length(instante) == 1L && !is.na(instante),
                    "Horário deve ser POSIXct ou NULL.")
  format(instante, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
}

identificar_import_mds <- function(diretorio) {
  git <- Sys.which("git")
  if (!nzchar(git) || !dir.exists(diretorio)) return(NULL)
  consultar <- function(args) {
    resposta <- suppressWarnings(system2(git, c("--no-optional-locks", "-C", shQuote(normalizePath(diretorio)), args),
                                         stdout = TRUE, stderr = FALSE))
    if (!is.null(attr(resposta, "status"))) return(NULL)
    resposta
  }
  commit <- consultar(c("rev-parse", "HEAD"))
  status <- consultar(c("status", "--porcelain", "--untracked-files=all"))
  if (is.null(commit) || is.null(status)) return(NULL)
  list(commit = commit, branch = consultar(c("branch", "--show-current")),
       alteracoes_locais = length(status) > 0L)
}

preparar_metadados_auditoria <- function(sistema, uf = NULL, periodo = NULL,
                                         parametros = NULL, filtros = NULL,
                                         inicio = NULL, python = NULL, import_mds = NULL,
                                         id_execucao = novo_id_execucao()) {
  .exigir_auditoria(.texto_auditoria(sistema), "Sistema solicitado deve ser informado.")
  .validar_id_execucao(id_execucao)
  versao <- function(pacote) {
    if (!requireNamespace(pacote, quietly = TRUE)) return(NULL)
    as.character(utils::packageVersion(pacote))
  }
  # Python deve ser a versão informada pelo chamador; não inferimos o intérprete
  # realmente utilizado a partir de outro executável instalado no PATH.
  list(id_execucao = id_execucao,
       consulta = list(sistema = sistema, uf = uf, periodo = periodo,
                       parametros = parametros, filtros = filtros),
       inicio_execucao_utc = .utc_auditoria(inicio),
       versoes = list(R = as.character(getRversion()), Python = python,
                      microdatasus = versao("microdatasus"), jsonlite = versao("jsonlite"),
                      dplyr = versao("dplyr"), data_table = versao("data.table"), Import_MDS = import_mds))
}

destinos_resultado_auditado <- function(destino_csv, diretorio_logs = NULL) {
  principal <- verificar_destino_csv(destino_csv)
  .exigir_auditoria(endsWith(principal, ".csv"), "Destino principal deve terminar em .csv.")
  base <- substr(principal, 1L, nchar(principal) - 4L)
  if (!is.null(diretorio_logs)) {
    logs <- .diretorio_real_exportacao(diretorio_logs)
    extracao <- .diretorio_real_exportacao(dirname(principal))
    .exigir_auditoria(identical(logs, file.path(extracao, "logs")) &&
      identical(basename(extracao), basename(base)), "Estrutura da extração/logs inválida.")
    base <- file.path(logs, basename(base))
  }
  caminhos <- list(principal = principal, naturalidade = paste0(base, "_auditoria_naturalidade.csv"),
                   relatorio = paste0(base, "_relatorio.json"))
  for (caminho in caminhos) verificar_destino_csv(caminho)
  caminhos
}

sha256_arquivo <- function(caminho) {
  programa <- Sys.which("sha256sum")
  .exigir_auditoria(nzchar(programa), "Utilitário sha256sum indisponível.")
  .exigir_auditoria(file.exists(caminho) && !dir.exists(caminho), "Arquivo para SHA-256 indisponível.")
  resposta <- suppressWarnings(system2(programa, c("--", shQuote(normalizePath(caminho, mustWork = TRUE))),
                                       stdout = TRUE, stderr = TRUE))
  .exigir_auditoria(is.null(attr(resposta, "status")) && length(resposta) == 1L &&
    grepl("^\\\\?[a-f0-9]{64} [ *]", resposta), "Falha do utilitário sha256sum.")
  # GNU prefixa uma barra invertida quando precisa escapar o nome no resultado.
  substr(sub("^\\\\", "", resposta), 1L, 64L)
}

.ler_csv_auditoria <- function(caminho) {
  # Parsing CSV, inclusive campos multilinha. Códigos nunca passam por type.convert.
  # Não interpretar o texto NA como ausência: o auxiliar usa situação/motivo.
  withCallingHandlers(utils::read.csv(caminho, colClasses = "character", na.strings = character(),
    check.names = FALSE, stringsAsFactors = FALSE, strip.white = FALSE,
    blank.lines.skip = FALSE, comment.char = ""), warning = function(w) {
      stop("Falha na leitura de verificação do CSV: ", conditionMessage(w), call. = FALSE)
    })
}

# Única apresentação ambígua com descrição autorizada. O predicado também é
# usado na leitura para não converter esse texto em NA. Não resolve o país.
.descricao_ambigua_aprovada <- function(auditoria) {
  !is.na(auditoria$codigo_original) & auditoria$codigo_original == "44" &
    !is.na(auditoria$situacao) & auditoria$situacao == "ambigua" &
    !is.na(auditoria$motivo) & auditoria$motivo == "codigo_corresponde_a_dois_paises_distintos" &
    !is.na(auditoria$descricao) & auditoria$descricao == "CAMBOJA / LAOS"
}

validar_auditoria_naturalidade <- function(auditoria, total_principal) {
  .exigir_auditoria(.inteiro_auditoria(total_principal), "Quantidade principal inválida.")
  .exigir_auditoria(is.data.frame(auditoria) &&
    identical(names(auditoria), colunas_naturalidade_auditoria()), "Esquema do auxiliar de naturalidade inválido.")
  posicoes <- auditoria$posicao_registro
  .exigir_auditoria(is.numeric(posicoes) && !anyNA(posicoes) &&
    all(is.finite(posicoes) & posicoes == floor(posicoes) & posicoes >= 1 & posicoes <= total_principal) &&
    !anyDuplicated(posicoes), "Posições ordinais devem ser inteiras, únicas e dentro do CSV principal.")
  .exigir_auditoria(all(vapply(colunas_naturalidade_auditoria()[-1L],
    function(nome) is.character(auditoria[[nome]]), logical(1))),
                    "Códigos, situações, motivos e descrições devem ser texto.")
  .exigir_auditoria(!anyNA(auditoria$situacao) && !anyNA(auditoria$motivo) &&
    all(auditoria$situacao %in% c("inequivoca", "ambigua", "sem_correspondencia", "ausente")) &&
    all(nzchar(auditoria$motivo)), "Auxiliar deve conter apenas exceções classificadas pelo processador.")
  ausente_na <- auditoria$motivo == "codigo_ausente_na"
  .exigir_auditoria(identical(is.na(auditoria$codigo_original), ausente_na) &&
    all(!ausente_na | auditoria$situacao == "ausente"), "Ausência NA do código exige a classificação codigo_ausente_na.")
  vazio <- auditoria$motivo == "codigo_ausente_vazio"
  espacos <- auditoria$motivo == "codigo_ausente_espacos"
  .exigir_auditoria(all(!is.na(auditoria$codigo_original[vazio]) & auditoria$codigo_original[vazio] == "") &&
    all(!is.na(auditoria$codigo_original[espacos]) & grepl("\\A +\\z", auditoria$codigo_original[espacos], perl = TRUE)) &&
    all(auditoria$situacao[vazio | espacos] == "ausente"), "Classificação de vazio/espaços inconsistente.")
  sem_descricao <- auditoria$situacao != "inequivoca" & !.descricao_ambigua_aprovada(auditoria)
  .exigir_auditoria(all(is.na(auditoria$descricao[sem_descricao])) &&
    !anyNA(auditoria$descricao[auditoria$situacao == "inequivoca"]),
    "Descrição deve corresponder à classificação da naturalidade.")
  invisible(TRUE)
}

ler_auditoria_naturalidade <- function(caminho, total_principal) {
  dados <- .ler_csv_auditoria(caminho)
  .exigir_auditoria(identical(names(dados), colunas_naturalidade_auditoria()), "Esquema do auxiliar inválido.")
  .exigir_auditoria(all(grepl("\\A[1-9][0-9]*\\z", dados$posicao_registro, perl = TRUE)), "Posição serializada inválida.")
  dados$posicao_registro <- as.numeric(dados$posicao_registro)
  ausente_na <- dados$motivo == "codigo_ausente_na"
  sem_descricao <- dados$situacao != "inequivoca" & !.descricao_ambigua_aprovada(dados)
  .exigir_auditoria(all(dados$codigo_original[ausente_na] == "NA") && all(dados$descricao[sem_descricao] == "NA"),
                    "Representação de ausência inconsistente no auxiliar.")
  dados$codigo_original[ausente_na] <- NA_character_
  dados$descricao[sem_descricao] <- NA_character_
  validar_auditoria_naturalidade(dados, total_principal)
  dados
}

validar_contagens_auditoria <- function(contagens, total_final) {
  .exigir_auditoria(is.list(contagens) && .inteiro_auditoria(total_final), "Contagens devem ser uma lista por etapa.")
  .exigir_auditoria(length(contagens) == 0L ||
    (!is.null(names(contagens)) && !anyDuplicated(names(contagens)) &&
     all(names(contagens) %in% c("etarias", "datas", "naturalidade"))), "Etapas de contagens não reconhecidas.")
  numero <- function(x) .exigir_auditoria(.inteiro_auditoria(x), "Contagem deve ser inteira não negativa.")
  iguais <- function(a, b) .exigir_auditoria(isTRUE(a == b), "Contagens não reconciliam entre etapas.")
  completos <- function(x, nomes) {
    .exigir_auditoria(is.list(x) && !anyDuplicated(names(x)) && all(nomes %in% names(x)), "Contrato de contagens incompleto.")
    for (nome in nomes) numero(x[[nome]])
  }
  e <- contagens$etarias
  d <- contagens$datas
  n <- contagens$naturalidade
  if (!is.null(e)) {
    completos(e, c("entrada", "excluidos_sem_data", "antes_filtro_etario", "idades_validas",
      "idades_desconhecidas", "idades_invalidas", "excluidos_desconhecidos", "excluidos_invalidos",
      "excluidos_fora_limites", "apos_filtro_etario", "apos_demais_filtros"))
    iguais(e$entrada - e$excluidos_sem_data, e$antes_filtro_etario)
    iguais(e$idades_validas + e$idades_desconhecidas + e$idades_invalidas, e$antes_filtro_etario)
    iguais(e$antes_filtro_etario - e$excluidos_desconhecidos - e$excluidos_invalidos - e$excluidos_fora_limites,
           e$apos_filtro_etario)
    .exigir_auditoria(e$excluidos_desconhecidos <= e$idades_desconhecidas &&
      e$excluidos_invalidos <= e$idades_invalidas && e$excluidos_fora_limites <= e$idades_validas &&
      e$apos_demais_filtros <= e$apos_filtro_etario, "Exclusões etárias inconsistentes.")
    iguais(e$apos_demais_filtros, total_final)
  }
  if (!is.null(d)) {
    completos(d, c("entrada", "datas_validas", "datas_ausentes", "datas_invalidas", "preservados_apos_validacao",
      "excluidos_por_data", "apos_filtro_etario", "apos_demais_filtros", "total_final_exportavel"))
    iguais(d$datas_validas + d$datas_ausentes + d$datas_invalidas, d$entrada)
    iguais(d$entrada - d$excluidos_por_data, d$preservados_apos_validacao)
    .exigir_auditoria(d$apos_filtro_etario <= d$preservados_apos_validacao &&
      d$apos_demais_filtros <= d$apos_filtro_etario, "Contagens de datas inconsistentes.")
    iguais(d$apos_demais_filtros, total_final)
    iguais(d$total_final_exportavel, total_final)
    if (!is.null(e)) {
      iguais(d$entrada, e$entrada)
      iguais(d$preservados_apos_validacao, e$antes_filtro_etario)
      iguais(d$apos_filtro_etario, e$apos_filtro_etario)
    }
  }
  if (!is.null(n)) {
    .exigir_auditoria(is.list(n), "Contagens de naturalidade inválidas.")
    for (etapa in c("antes_filtros", "apos_demais_filtros")) {
      x <- n[[etapa]]
      completos(x, c("total", "inequivocas", "ambiguas", "sem_correspondencia", "ausentes"))
      iguais(x$total, x$inequivocas + x$ambiguas + x$sem_correspondencia + x$ausentes)
    }
    numero(n$apos_filtro_etario)
    .exigir_auditoria(n$apos_filtro_etario <= n$antes_filtros$total &&
      n$apos_demais_filtros$total <= n$apos_filtro_etario, "Contagens de naturalidade inconsistentes.")
    iguais(n$apos_demais_filtros$total, total_final)
    for (categoria in c("inequivocas", "ambiguas", "sem_correspondencia", "ausentes")) {
      .exigir_auditoria(n$apos_demais_filtros[[categoria]] <= n$antes_filtros[[categoria]],
                        "Categorias de naturalidade aumentaram após os filtros.")
    }
    if (!is.null(e)) {
      iguais(n$antes_filtros$total, e$antes_filtro_etario)
      iguais(n$apos_filtro_etario, e$apos_filtro_etario)
    }
    if (!is.null(d)) {
      iguais(n$antes_filtros$total, d$preservados_apos_validacao)
      iguais(n$apos_filtro_etario, d$apos_filtro_etario)
    }
  }
  invisible(TRUE)
}

.verificar_csv_preparado <- function(caminho, colunas, quantidade) {
  dados <- .ler_csv_auditoria(caminho)
  .exigir_auditoria(identical(names(dados), colunas) && nrow(dados) == quantidade,
                    "Esquema ou quantidade de registros gravados diverge do esperado.")
  invisible(TRUE)
}

.metadados_arquivo_auditoria <- function(temporario, destino, registros, colunas,
                                        nome_relativo = basename(destino)) {
  list(nome = nome_relativo, registros = registros, bytes = unname(file.info(temporario)$size),
       sha256 = sha256_arquivo(temporario), colunas = as.list(colunas))
}

.conferir_arquivo_auditoria <- function(caminho, esperado) {
  .exigir_auditoria(file.exists(caminho) && !dir.exists(caminho), "Artefato referenciado indisponível.")
  .exigir_auditoria(identical(sha256_arquivo(caminho), esperado$sha256) &&
    isTRUE(unname(file.info(caminho)$size) == esperado$bytes), "Checksum ou tamanho do artefato divergente.")
  .verificar_csv_preparado(caminho, unlist(esperado$colunas, use.names = FALSE), esperado$registros)
}

.exigir_jsonlite <- function() {
  .exigir_auditoria(requireNamespace("jsonlite", quietly = TRUE), "Dependência jsonlite não instalada; consulte DEPENDENCIAS.md.")
}

.escrever_relatorio_auditoria <- function(relatorio, conexao) {
  .exigir_jsonlite()
  writeLines(jsonlite::toJSON(relatorio, auto_unbox = TRUE, null = "null", na = "null",
                             pretty = TRUE, digits = NA), conexao, useBytes = TRUE)
}

.validar_estrutura_relatorio <- function(r, marcador_final = FALSE) {
  .exigir_auditoria(is.list(r) && .texto_auditoria(r$versao_esquema) &&
    r$versao_esquema %in% c("1.0.0", "1.1.0"), "Versão/estrutura do relatório não suportada.")
  organizado <- identical(r$versao_esquema, "1.1.0")
  .validar_id_execucao(r$id_execucao)
  .exigir_auditoria(is.list(r$metadados) &&
    all(c("id_execucao", "consulta", "inicio_execucao_utc", "versoes") %in% names(r$metadados)) &&
    is.list(r$metadados$consulta) && all(c("sistema", "uf", "periodo", "parametros", "filtros") %in% names(r$metadados$consulta)) &&
    is.list(r$metadados$versoes) && all(c("R", "Python", "microdatasus", "jsonlite", "dplyr", "data_table", "Import_MDS") %in% names(r$metadados$versoes)) &&
    is.list(r$horarios) && .texto_auditoria(r$horarios$inicio_preparacao_utc) &&
    is.list(r$informacoes_indisponiveis) && is.list(r$limitacoes) && length(r$limitacoes) > 0L,
    "Campos obrigatórios do relatório ausentes.")
  if (marcador_final) {
    .exigir_auditoria(.texto_auditoria(r$horarios$conferencia_utc) &&
      grepl("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z", r$horarios$conferencia_utc, perl = TRUE),
      "Marcador sem horário UTC da conferência final.")
  }
  .exigir_auditoria(identical(r$id_execucao, r$metadados$id_execucao) &&
    .texto_auditoria(r$metadados$consulta$sistema) &&
    identical(r$publicacao$situacao, "concluida") &&
    identical(r$cobertura_datasus, "nao_verificada") &&
    identical(r$verificacoes$arquivos, TRUE) && identical(r$verificacoes$contagens, TRUE) &&
    identical(r$verificacoes$posicoes_ordinais, TRUE), "Relatório inconsistente ou incompleto.")
  .exigir_auditoria(identical(names(r$arquivos), c("principal", "naturalidade")), "Conjunto de arquivos inválido.")
  nomes <- character()
  for (tipo in names(r$arquivos)) {
    a <- r$arquivos[[tipo]]
    nome <- if (organizado && tipo == "principal" && .texto_auditoria(a$nome) &&
                startsWith(a$nome, "../")) substring(a$nome, 4L) else a$nome
    .exigir_auditoria(is.list(a) && .texto_auditoria(a$nome) &&
      .texto_auditoria(nome) && identical(basename(nome), nome) && !nome %in% c(".", "..") &&
      !grepl("[/\\\\]", nome) && endsWith(nome, ".csv") &&
      (!organizado || tipo != "principal" || identical(a$nome, paste0("../", nome))) &&
      .inteiro_auditoria(a$registros) && .inteiro_auditoria(a$bytes) &&
      .texto_auditoria(a$sha256) && grepl("\\A[a-f0-9]{64}\\z", a$sha256, perl = TRUE) &&
      is.list(a$colunas) && length(a$colunas) > 0L &&
      all(vapply(a$colunas, .texto_auditoria, logical(1))) && !anyDuplicated(unlist(a$colunas)),
      "Metadados de arquivo inválidos.")
    nomes <- c(nomes, a$nome)
  }
  if (organizado) {
    base <- sub("[.]csv$", "", basename(r$arquivos$principal$nome))
    .exigir_auditoria(identical(r$publicacao$base_caminhos, "diretorio_relatorio") &&
      identical(r$publicacao$organizacao, "extracao_logs") &&
      identical(r$arquivos$naturalidade$nome, paste0(base, "_auditoria_naturalidade.csv")),
      "Referências da estrutura extração/logs inconsistentes.")
  }
  .exigir_auditoria(!anyDuplicated(nomes) &&
    identical(unlist(r$arquivos$naturalidade$colunas, use.names = FALSE), colunas_naturalidade_auditoria()),
    "Nomes ou esquema do auxiliar inconsistentes.")
  if (r$metadados$consulta$sistema == "SIM-DO") {
    .exigir_auditoria(identical(unlist(r$arquivos$principal$colunas, use.names = FALSE), colunas_principal_auditoria()),
                      "Esquema legado SIM deve conter as 14 colunas na ordem contratada.")
  }
  validar_contagens_auditoria(r$contagens, r$arquivos$principal$registros)
  invisible(TRUE)
}

.resolver_artefatos_relatorio <- function(caminho_json, relatorio) {
  # O nome é validado antes da resolução. Em 1.1 apenas o principal pode subir
  # EXATAMENTE um nível; todos os outros componentes são nomes simples.
  pasta <- .diretorio_real_exportacao(dirname(caminho_json))
  .exigir_auditoria(!nzchar(Sys.readlink(caminho_json)), "Link simbólico de relatório não permitido.")
  pais <- list(principal = pasta, naturalidade = pasta)
  if (identical(relatorio$versao_esquema, "1.1.0")) {
    # Verifica também a pasta informada ANTES da canonicalização de logs/,
    # para não aceitar uma pasta de extração que seja um link para fora.
    extracao <- .diretorio_real_exportacao(dirname(dirname(caminho_json)))
    base <- sub("[.]csv$", "", basename(relatorio$arquivos$principal$nome))
    .exigir_auditoria(identical(basename(pasta), "logs") &&
      identical(basename(extracao), base) &&
      identical(basename(caminho_json), paste0(base, "_relatorio.json")),
      "Relatório fora da estrutura extração/logs autorizada.")
    pais$principal <- extracao
  }
  caminhos <- list()
  for (tipo in names(pais)) {
    p <- file.path(pais[[tipo]], basename(relatorio$arquivos[[tipo]]$nome))
    .exigir_auditoria(file.exists(p) && !dir.exists(p) && !nzchar(Sys.readlink(p)) &&
      identical(normalizePath(p, mustWork = TRUE), p),
      "Artefato referenciado indisponível ou fora do diretório autorizado.")
    caminhos[[tipo]] <- p
  }
  caminhos
}

verificar_resultado_auditado <- function(caminho_json, id_execucao = NULL) {
  .exigir_jsonlite()
  .exigir_auditoria(.texto_auditoria(caminho_json) && file.exists(caminho_json) && !dir.exists(caminho_json),
                    "Relatório JSON local indisponível.")
  r <- jsonlite::fromJSON(caminho_json, simplifyVector = FALSE)
  .validar_estrutura_relatorio(r, marcador_final = TRUE)
  if (!is.null(id_execucao)) .exigir_auditoria(identical(id_execucao, r$id_execucao), "Identificador de execução divergente.")
  caminhos <- .resolver_artefatos_relatorio(caminho_json, r)
  for (tipo in names(r$arquivos)) .conferir_arquivo_auditoria(caminhos[[tipo]], r$arquivos[[tipo]])
  ler_auditoria_naturalidade(caminhos$naturalidade,
                            r$arquivos$principal$registros)
  invisible(r)
}

publicar_resultado_auditado <- function(dados, auditoria, destino_csv, metadados,
                                        contagens = list(),
                                        colunas_principal = colunas_principal_auditoria(),
                                        diretorio_logs = NULL) {
  .exigir_jsonlite()
  destinos <- destinos_resultado_auditado(destino_csv, diretorio_logs)
  .exigir_auditoria(is.data.frame(dados) && identical(names(dados), colunas_principal) &&
    is.character(colunas_principal) && length(colunas_principal) > 0L &&
    !anyNA(colunas_principal) && !anyDuplicated(colunas_principal), "Esquema principal inválido.")
  validar_auditoria_naturalidade(auditoria, nrow(dados))
  validar_contagens_auditoria(contagens, nrow(dados))
  .validar_id_execucao(metadados$id_execucao)
  inicio_preparacao <- .utc_auditoria(Sys.time())
  temporarios <- character()
  on.exit(limpar_temporarios_exportacao(temporarios), add = TRUE)
  preparar <- function(destino, escrever) {
    caminho <- preparar_arquivo_seguro(destino, escrever)
    temporarios <<- c(temporarios, caminho)
    caminho
  }
  principal <- preparar(destinos$principal, function(con) .escrever_csv_padrao(dados, con))
  auxiliar <- preparar(destinos$naturalidade, function(con) .escrever_csv_padrao(auditoria, con))
  .verificar_csv_preparado(principal, colunas_principal, nrow(dados))
  .verificar_csv_preparado(auxiliar, colunas_naturalidade_auditoria(), nrow(auditoria))
  # Confere também a reconstrução sem perda de zeros/espaços/literal NA.
  lido <- ler_auditoria_naturalidade(auxiliar, nrow(dados))
  for (nome in names(auditoria)) {
    .exigir_auditoria(isTRUE(all.equal(lido[[nome]], auditoria[[nome]], check.attributes = FALSE)),
                      "Conteúdo do auxiliar diverge após a serialização.")
  }
  nome_principal <- if (is.null(diretorio_logs)) basename(destinos$principal) else paste0("../", basename(destinos$principal))
  arquivos <- list(principal = .metadados_arquivo_auditoria(principal, destinos$principal, nrow(dados), colunas_principal,
                                                         nome_relativo = nome_principal),
    naturalidade = .metadados_arquivo_auditoria(auxiliar, destinos$naturalidade, nrow(auditoria), colunas_naturalidade_auditoria()))
  limitacoes <- c("Cobertura dos arquivos DATASUS não verificada.",
    "Publicação individual; não há atomicidade entre os três arquivos nem garantia contra perda de energia.",
    "Checksums verificam bytes; não comprovam qualidade epidemiológica nem autenticidade.",
    "Contagens fornecidas pelo chamador: não reconstruídas a partir das 14 colunas.",
    "Vínculo entre códigos originais e posições fornecido pelo processador; não comprovável pelas 14 colunas.")
  indisponiveis <- character()
  localizar_ausencias <- function(x, prefixo) {
    if (is.null(x) || (is.atomic(x) && anyNA(x))) return(prefixo)
    if (!is.list(x)) return(character())
    unlist(lapply(names(x), function(n) localizar_ausencias(x[[n]], paste0(prefixo, ".", n))), use.names = FALSE)
  }
  indisponiveis <- localizar_ausencias(metadados, "metadados")
  for (etapa in c("etarias", "datas", "naturalidade")) {
    if (is.null(contagens[[etapa]])) {
      indisponiveis <- c(indisponiveis, paste0("contagens.", etapa))
      contagens[etapa] <- list(NULL)
    }
  }
  relatorio <- list(versao_esquema = if (is.null(diretorio_logs)) "1.0.0" else "1.1.0",
    id_execucao = metadados$id_execucao, metadados = metadados,
    horarios = list(inicio_preparacao_utc = inicio_preparacao),
    contagens = contagens, arquivos = arquivos,
    verificacoes = list(arquivos = TRUE, contagens = TRUE, posicoes_ordinais = TRUE),
    cobertura_datasus = "nao_verificada",
    publicacao = list(situacao = "concluida", protocolo = "csv_principal_csv_auxiliar_json_final"),
    informacoes_indisponiveis = as.list(indisponiveis), limitacoes = as.list(limitacoes))
  if (!is.null(diretorio_logs)) {
    relatorio$publicacao$base_caminhos <- "diretorio_relatorio"
    relatorio$publicacao$organizacao <- "extracao_logs"
  }
  .validar_estrutura_relatorio(relatorio)
  # Prepara e valida o JSON antes de qualquer publicação; a versão final recebe
  # o horário da conferência e é reescrita em OUTRO temporário exclusivo.
  json <- preparar(destinos$relatorio, function(con) .escrever_relatorio_auditoria(relatorio, con))
  .validar_estrutura_relatorio(jsonlite::fromJSON(json, simplifyVector = FALSE))
  publicar_arquivo_seguro(principal, destinos$principal)
  publicar_arquivo_seguro(auxiliar, destinos$naturalidade)
  for (nome in names(arquivos)) .conferir_arquivo_auditoria(destinos[[nome]], arquivos[[nome]])
  ler_auditoria_naturalidade(destinos$naturalidade, nrow(dados))
  relatorio$horarios$conferencia_utc <- .utc_auditoria(Sys.time())
  json <- preparar(destinos$relatorio, function(con) .escrever_relatorio_auditoria(relatorio, con))
  .validar_estrutura_relatorio(jsonlite::fromJSON(json, simplifyVector = FALSE), marcador_final = TRUE)
  publicar_arquivo_seguro(json, destinos$relatorio)
  invisible(relatorio)
}
