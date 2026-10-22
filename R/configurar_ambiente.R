# Apoio interno aos scripts Bash. Somente a ação instalar acessa a rede.
# Não carrega o orquestrador nem chama fetch_datasus().
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2L) stop("Use configurar.sh ou iniciar.sh.")
acao <- args[1L]
raiz <- normalizePath(args[2L], mustWork = TRUE)
if (getRversion() < "4.1.0") stop("ERRO: R 4.1.0 ou superior é necessário.")
biblioteca <- file.path(raiz, ".biblioteca-R", R.version$platform,
                        paste(R.version$major, strsplit(R.version$minor, ".", fixed = TRUE)[[1]][1], sep = "."))
if (acao == "biblioteca") { cat(biblioteca); quit(status = 0L) }
if (dir.exists(biblioteca)) .libPaths(c(biblioteca, .libPaths()))
if (!nzchar(Sys.getenv("TZ"))) Sys.setenv(TZ = "UTC")

politica <- list(microdatasus = c("==", "3.0.0"), jsonlite = c("==", "2.0.0"),
                 dplyr = c(">=", "1.2.0"), lubridate = c(">=", "1.9.0"))
versoes_instalacao <- c(microdatasus = "3.0.0", jsonlite = "2.0.0", dplyr = "1.2.1", lubridate = "1.9.5")
commit_microdatasus <- "7109ec2c42cf674ba453e0d7a20d2f464890b543"
# Imports do DESCRIPTION oficial nesse commit; permite diagnosticar uma
# instalação incompleta mesmo quando o próprio microdatasus está ausente.
imports_microdatasus <- c("checkmate", "cli", "curl", "data.table", "dplyr", "foreign",
                         "magrittr", "rlang", "stringi", "tibble", "utils", "zip")

descricao_instalada <- function(pacote) {
  caminho <- suppressWarnings(find.package(pacote, quiet = TRUE))
  if (!length(caminho)) return(NULL)
  as.list(read.dcf(file.path(caminho, "DESCRIPTION"))[1L, ])
}
compativel <- function(versao, op, requerida) {
  if (is.null(versao)) return(FALSE)
  diferenca <- utils::compareVersion(versao, requerida)
  switch(op, ">=" = diferenca >= 0, "<=" = diferenca <= 0,
         "==" = diferenca == 0, ">" = diferenca > 0, "<" = diferenca < 0,
         stop("Restrição de versão não suportada: ", op))
}
dependencias <- function(descricao) {
  campos <- unlist(descricao[intersect(c("Depends", "Imports", "LinkingTo"), names(descricao))])
  entradas <- trimws(unlist(strsplit(paste(campos, collapse = ","), ",", fixed = TRUE)))
  lapply(entradas[nzchar(entradas)], function(entrada) {
    partes <- regmatches(entrada, regexec("^([A-Za-z][A-Za-z0-9.]*)[[:space:]]*(\\((>=|<=|==|>|<)[[:space:]]*([0-9][0-9.-]*)\\))?$", entrada))[[1]]
    if (!length(partes)) stop("Dependência não interpretável: ", entrada)
    list(pacote = partes[2], op = if (nzchar(partes[4])) partes[4] else ">=",
         versao = if (nzchar(partes[5])) partes[5] else "0")
  })
}
atende <- function(pacote, op = ">=", versao = "0") {
  d <- descricao_instalada(pacote)
  !is.null(d) && compativel(d$Version, op, versao) &&
    (is.null(politica[[pacote]]) || compativel(d$Version, politica[[pacote]][1], politica[[pacote]][2]))
}
planejar <- function() {
  pendentes <- character(); visitados <- character()
  fila <- lapply(unique(c(names(politica), imports_microdatasus)), function(p) {
    regra <- politica[[p]]
    list(pacote = p, op = if (is.null(regra)) ">=" else regra[1], versao = if (is.null(regra)) "0" else regra[2])
  })
  while (length(fila)) {
    requisito <- fila[[1]]; fila <- fila[-1]
    p <- requisito$pacote
    if (p == "R") {
      if (!compativel(as.character(getRversion()), requisito$op, requisito$versao)) stop("ERRO: versão do R incompatível com as bibliotecas.")
      next
    }
    if (!atende(p, requisito$op, requisito$versao)) pendentes <- union(pendentes, p)
    if (p %in% visitados) next
    visitados <- c(visitados, p)
    d <- descricao_instalada(p)
    if (!is.null(d)) fila <- c(fila, dependencias(d))
  }
  pendentes
}
verificar <- function() {
  cat("R", as.character(getRversion()), "— biblioteca privada:", biblioteca, "\n")
  for (p in names(politica)) {
    d <- descricao_instalada(p)
    cat(p, if (is.null(d)) "AUSENTE" else d$Version, "— requerido", paste(politica[[p]], collapse = " "), "\n")
  }
  pendentes <- planejar()
  if (length(pendentes)) {
    cat("ATENÇÃO: ausentes ou incompatíveis:", paste(pendentes, collapse = ", "), "\n")
    cat("Versões dos pacotes diretos para instalação:", paste(names(versoes_instalacao), versoes_instalacao, collapse = "; "), "\n")
    return(10L)
  }
  for (p in names(politica)) {
    if (!requireNamespace(p, quietly = TRUE)) stop("ERRO: ", p, " está instalado, mas não carrega. Consulte as mensagens e DEPENDENCIAS.md.")
  }
  exigir <- function(ok) if (!ok) stop("ERRO: API do microdatasus incompatível com o Import_MDS.")
  exigir(all(c("year_start", "year_end", "month_start", "month_end", "uf", "information_system", "stop_on_error") %in% names(formals(microdatasus::fetch_datasus))))
  exigir("data" %in% names(formals(microdatasus::process_sim)))
  # Somente processamento em memória, sem campos que executem junções auxiliares.
  prova <- microdatasus::process_sim(data.frame(IDADE = c("418", "500"), SEXO = c("1", "2")))
  exigir(identical(as.numeric(prova$IDADEanos), c(18, 100)))
  exigir(identical(as.character(prova$SEXO), c("Masculino", "Feminino")))
  cat("Pacotes, dependências transitivas e API verificados sem coleta.\n")
  if (getRversion() != "4.3.3") cat("AVISO: R diferente de 4.3.3; requisitos mínimos atendidos, mas essa combinação não foi homologada neste ambiente.\n")
  for (p in c("dplyr", "lubridate")) {
    if (descricao_instalada(p)$Version != versoes_instalacao[[p]]) cat("AVISO:", p, "atende ao mínimo, mas difere da versão testada", versoes_instalacao[[p]], ".\n")
  }
  0L
}

instalar <- function() {
  if (length(args) != 3L || args[3] != "--confirmado") stop("Instalação exige confirmação em configurar.sh.")
  for (ferramenta in c("make", "gcc", "g++")) {
    if (!nzchar(Sys.which(ferramenta))) stop("ERRO: compilador/ferramenta ausente: ", ferramenta, ". Consulte DEPENDENCIAS.md; nenhum pacote foi instalado.")
  }
  if (!capabilities("libcurl")) stop("ERRO: este R não oferece downloads HTTPS por libcurl.")
  if (!dir.exists(biblioteca) && !dir.create(biblioteca, recursive = TRUE)) stop("ERRO: não foi possível criar a biblioteca privada.")
  if (file.access(biblioteca, 2L) != 0L) stop("ERRO: biblioteca privada sem permissão de escrita.")
  .libPaths(c(biblioteca, .libPaths()))
  temporario <- tempfile("import-mds-instalacao-"); dir.create(temporario)
  on.exit(unlink(temporario, recursive = TRUE), add = TRUE)
  disponiveis <- NULL; ativos <- character()
  garantir <- function(p, op = ">=", versao = "0") {
    if (p == "R") {
      if (!compativel(as.character(getRversion()), op, versao)) stop("ERRO: fonte exige R ", op, " ", versao, ". Atualize R manualmente antes de continuar.")
      return(invisible(NULL))
    }
    if (atende(p, op, versao)) return(invisible(NULL))
    if (p %in% ativos) stop("ERRO: ciclo de dependências ao instalar ", p)
    ativos <<- c(ativos, p)
    on.exit({ativos <<- setdiff(ativos, p)}, add = TRUE)
    v <- unname(versoes_instalacao[p])
    if (is.na(v)) {
      if (is.null(disponiveis)) disponiveis <<- utils::available.packages(repos = "https://cloud.r-project.org", type = "source")
      if (!p %in% rownames(disponiveis)) stop("ERRO: dependência não disponível para este R no CRAN: ", p)
      v <- disponiveis[p, "Version"]
    }
    if (!compativel(v, op, versao)) stop("ERRO: versão disponível/fixada incompatível de ", p)
    urls <- if (p == "microdatasus") {
      paste0("https://codeload.github.com/rfsaldanha/microdatasus/tar.gz/", commit_microdatasus)
    } else c(paste0("https://cloud.r-project.org/src/contrib/", p, "_", v, ".tar.gz"),
             paste0("https://cloud.r-project.org/src/contrib/Archive/", p, "/", p, "_", v, ".tar.gz"))
    arquivo <- file.path(temporario, paste0(p, "_", v, ".tar.gz"))
    baixado <- FALSE
    for (url in urls) {
      cat("Obtendo fonte de", p, v, "de", url, "\n")
      baixado <- tryCatch(utils::download.file(url, arquivo, mode = "wb", method = "libcurl") == 0L, error = function(e) FALSE)
      if (baixado) break
    }
    if (!baixado) stop("ERRO: não foi possível baixar a biblioteca ", p, ". Verifique internet e certificados.")
    entradas <- utils::untar(arquivo, list = TRUE)
    if (any(grepl("^/|(^|/)\\.\\.(/|$)", entradas))) stop("ERRO: caminhos inseguros no pacote fonte.")
    pasta <- file.path(temporario, p); dir.create(pasta)
    utils::untar(arquivo, exdir = pasta)
    descricoes <- list.files(pasta, pattern = "^DESCRIPTION$", recursive = TRUE, full.names = TRUE)
    # Pode haver DESCRIPTION em fixtures; somente o diretório superior é pacote.
    descricoes <- descricoes[dirname(dirname(descricoes)) == pasta]
    if (length(descricoes) != 1L) stop("ERRO: pacote fonte sem DESCRIPTION único na raiz.")
    d <- as.list(read.dcf(descricoes)[1L, ])
    if (!identical(d$Package, p) || !identical(d$Version, v)) stop("ERRO: identificação/versão do fonte divergente.")
    for (dep in dependencias(d)) garantir(dep$pacote, dep$op, dep$versao)
    cat("Instalando", p, v, "somente na biblioteca privada...\n")
    utils::install.packages(dirname(descricoes), lib = biblioteca, repos = NULL, type = "source", dependencies = FALSE)
    instalado <- suppressWarnings(utils::packageDescription(p, lib.loc = biblioteca))
    if (!is.list(instalado) || !identical(instalado$Version, v)) stop("ERRO: falha de instalação de ", p, ". Consulte o erro de compilação acima.")
  }
  for (p in planejar()) garantir(p)
  if (length(planejar())) stop("ERRO: ainda existem dependências incompatíveis após a instalação.")
  cat("Instalação terminada. A configuração fará uma nova verificação em outro processo R.\n")
}

status <- tryCatch({
  if (acao == "verificar") verificar()
  else if (acao == "instalar") {instalar(); 0L}
  else stop("Ação desconhecida. Use configurar.sh ou iniciar.sh.")
}, error = function(e) {message(conditionMessage(e)); 1L})
quit(status = status)
