# Interpretação CID sem coleta. Fonte local: docs/cid10.md.
# Prefixos são literais; somente intervalos consultam a classificação.
carregar_referencia_cid <- local({
  arquivos <- unlist(lapply(sys.frames(), function(q) {
    valores <- lapply(c("ofile", "file"), function(n) q[[n]])
    unlist(Filter(function(x) is.character(x) && length(x) == 1L && !is.na(x), valores))
  }))
  arquivos <- arquivos[basename(arquivos) == "cid.R" & file.exists(arquivos)]
  if (!length(arquivos)) stop("Não foi possível localizar o módulo cid.R.")
  modulo <- normalizePath(utils::tail(arquivos, 1L), mustWork = TRUE)
  padrao <- file.path(dirname(dirname(dirname(modulo))), "referencias", "cid10", "oms_2019_codigos.json")
  function(caminho = padrao) {
    if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Dependência jsonlite indisponível.")
    if (!is.character(caminho) || length(caminho) != 1L || is.na(caminho) ||
        !file.exists(caminho) || dir.exists(caminho)) stop("Referência CID-10 deve ser um arquivo local disponível.")
    referencia <- jsonlite::fromJSON(normalizePath(caminho, mustWork = TRUE), simplifyVector = TRUE)
    validar_referencia_cid(referencia)
    referencia
  }
})

validar_referencia_cid <- function(referencia) {
  texto <- function(x) is.character(x) && length(x) == 1L && !is.na(x) && nzchar(x)
  vetor <- function(x, formato) is.character(x) && !anyNA(x) && !anyDuplicated(x) &&
    all(grepl(formato, x, perl = TRUE))
  r <- referencia$referencia
  if (!is.list(referencia) || !identical(referencia$versao_indice, "1.0.0") ||
      !is.list(r) || !all(vapply(r[c("origem", "versao", "identificador", "data_titulo", "url",
                                    "obtido_em_utc", "sha256_zip", "sha256_xml", "escopo")], texto, logical(1))) ||
      !all(c("origem", "versao", "identificador", "data_titulo", "url", "obtido_em_utc", "sha256_zip", "sha256_xml", "escopo") %in% names(r)) ||
      !vetor(referencia$categorias, "\\A[A-Z][0-9]{2}\\z") || !length(referencia$categorias) ||
      !vetor(referencia$subcategorias, "\\A[A-Z][0-9]{2}[.][0-9]\\z") ||
      !all(substr(referencia$subcategorias, 1L, 3L) %in% referencia$categorias) ||
      !isTRUE(r$quantidade_categorias == length(referencia$categorias)) ||
      !isTRUE(r$quantidade_subcategorias == length(referencia$subcategorias))) {
    stop("Referência local CID-10 inválida ou incompleta.")
  }
  invisible(TRUE)
}

interpretar_consulta_cid <- function(cid, referencia = NULL) {
  if (!is.character(cid) || length(cid) != 1L || is.na(cid)) stop("CID deve ser um texto escalar não ausente.")
  consulta <- list(modalidade = if (cid == "ALL") "all" else "prefixo", valor = cid)
  if (grepl("-", cid, fixed = TRUE)) {
    valor <- toupper(cid)
    formato <- "\\A[ \t]*([A-Z][0-9]{2})[ \t]*-[ \t]*([A-Z][0-9]{2})[ \t]*\\z"
    partes <- regmatches(valor, regexec(formato, valor, perl = TRUE))[[1L]]
    if (!length(partes)) stop("Intervalo CID inválido: use categorias completas, como I10-I15, com um único hífen.")
    inicio <- partes[2L]; fim <- partes[3L]
    if (substr(inicio, 1L, 1L) != substr(fim, 1L, 1L)) stop("Os limites CID devem ter a mesma letra.")
    if (as.integer(substr(inicio, 2L, 3L)) > as.integer(substr(fim, 2L, 3L))) stop("Intervalo CID com limites invertidos.")
    if (is.null(referencia)) referencia <- carregar_referencia_cid()
    validar_referencia_cid(referencia)
    if (!all(c(inicio, fim) %in% referencia$categorias)) stop("Limite CID inexistente na referência local utilizada.")
    categorias <- referencia$categorias
    numeros <- as.integer(substr(categorias, 2L, 3L))
    categorias <- sort(categorias[substr(categorias, 1L, 1L) == substr(inicio, 1L, 1L) &
      numeros >= as.integer(substr(inicio, 2L, 3L)) & numeros <= as.integer(substr(fim, 2L, 3L))])
    subcategorias <- referencia$subcategorias[substr(referencia$subcategorias, 1L, 3L) %in% categorias]
    consulta <- list(modalidade = "intervalo", valor = paste0(inicio, "-", fim),
      limite_inicial = inicio, limite_final = fim, categorias = categorias,
      codigos = c(categorias, gsub(".", "", subcategorias, fixed = TRUE)), referencia = referencia$referencia)
  }
  structure(consulta, class = "consulta_cid")
}

resolver_consulta_cid <- function(cid, consulta = NULL) {
  if (is.null(consulta)) return(interpretar_consulta_cid(cid))
  if (!inherits(consulta, "consulta_cid") || !identical(consulta$valor, cid)) {
    stop("Consulta CID interpretada não corresponde ao parâmetro informado.")
  }
  consulta
}

selecionar_cid <- function(codigos, consulta) {
  if (!is.character(codigos) || !inherits(consulta, "consulta_cid")) stop("Contrato de seleção CID inválido.")
  if (consulta$modalidade == "all") return(rep(TRUE, length(codigos)))
  if (consulta$modalidade == "prefixo") return(startsWith(codigos, consulta$valor))
  if (consulta$modalidade != "intervalo") stop("Modalidade CID não reconhecida.")
  # Só remover o ponto depois de validar o código INTEIRO. Não limpar espaços
  # nem truncar sufixos. A associação usa códigos atribuídos, não apenas regex.
  formato <- !is.na(codigos) & grepl("\\A[A-Z][0-9]{2}([.]?[0-9])?\\z", codigos, perl = TRUE)
  compacto <- gsub(".", "", codigos, fixed = TRUE)
  formato & substr(compacto, 1L, 3L) %in% consulta$categorias & compacto %in% consulta$codigos
}

complementar_filtros_cid <- function(filtros, consulta) {
  if (consulta$modalidade == "intervalo") {
    filtros$cid_intervalo <- list(modalidade = "intervalo", limite_inicial = consulta$limite_inicial,
      limite_final = consulta$limite_final, referencia = consulta$referencia,
      categorias_elegiveis = as.list(consulta$categorias))
  }
  filtros
}
