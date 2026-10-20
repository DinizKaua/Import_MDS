suppressPackageStartupMessages({
  library(microdatasus)
  library(dplyr)
  library(lubridate)
})

# -------------------------------
# Parse de argumentos (--param valor)
# -------------------------------
parse_args <- function(args) {
  out <- list()
  i <- 1
  while (i <= length(args)) {
    key <- args[i]
    if (startsWith(key, "--")) {
      name <- substring(key, 3)
      out[[name]] <- args[i + 1]
      i <- i + 2
    } else {
      i <- i + 1
    }
  }
  out
}

args <- parse_args(commandArgs(trailingOnly = TRUE))

# -------------------------------
# Parâmetros
# -------------------------------
sistema <- if (!is.null(args$system)) args$system else "SIM-DO"
ano_inicio <- as.numeric(if (!is.null(args$year_start)) args$year_start else 2020)
ano_fim <- as.numeric(if (!is.null(args$year_end)) args$year_end else 2020)
mes_inicio <- as.numeric(if (!is.null(args$month_start)) args$month_start else 1)
mes_fim <- as.numeric(if (!is.null(args$month_end)) args$month_end else 12)
uf <- if (!is.null(args$uf)) toupper(args$uf) else "ALL"
sexo <- if (!is.null(args$sexo)) args$sexo else "ALL"
cid <- if (!is.null(args$cid)) toupper(args$cid) else "ALL"
raca <- if (!is.null(args$raca)) args$raca else "ALL"
faixa <- if (!is.null(args$faixa)) args$faixa else "ALL"
idade_min <- args$idade_min
idade_max <- args$idade_max

# Carrega apenas funções; valida os limites antes de qualquer chamada de coleta.
source(file.path("R", "sistemas", "sim.R"), local = TRUE)
limites_idade <- resolver_limites_idade_sim(idade_min, idade_max, faixa)

# -------------------------------
# Tratamento UF
# -------------------------------
uf_param <- if (uf == "ALL") "all" else uf

source(file.path("R", "comum", "exportacao.R"), local = TRUE)
source(file.path("R", "comum", "auditoria.R"), local = TRUE)
.exigir_jsonlite()
if (!nzchar(Sys.which("sha256sum"))) stop("Utilitário sha256sum indisponível.")
nome_arquivo <- construir_nome_csv(
  sistema, uf_param, ano_inicio, ano_fim,
  cid = cid, sexo = sexo, raca = raca, faixa = faixa,
  idade_min = if (is.null(idade_min)) NULL else limites_idade$idade_min,
  idade_max = if (is.null(idade_max)) NULL else limites_idade$idade_max,
  mes_inicio = mes_inicio, mes_fim = mes_fim
)
destinos <- destinos_resultado_auditado(nome_arquivo)
caminho_arquivo <- destinos$principal
metadados <- preparar_metadados_auditoria(
  sistema = sistema, uf = uf,
  periodo = list(year_start = ano_inicio, year_end = ano_fim,
                 month_start = mes_inicio, month_end = mes_fim),
  parametros = list(year_start = ano_inicio, year_end = ano_fim,
                    month_start = mes_inicio, month_end = mes_fim,
                    uf = uf_param, information_system = sistema, stop_on_error = TRUE),
  filtros = list(sexo = sexo, raca = raca, cid = cid, faixa_legada_informada = faixa,
                 idade_min = limites_idade$idade_min, idade_max = limites_idade$idade_max),
  inicio = Sys.time(), python = NULL, import_mds = identificar_import_mds(".")
)

cat("Parâmetros:\n")
cat("Sistema:", sistema, "\n")
cat("Período:", ano_inicio, "-", ano_fim, "\n")
cat("UF:", uf, "\n")
cat("Sexo:", sexo, "\n")
cat("Raça:", raca, "\n")
cat("Faixa:", faixa, "\n")
cat("CID:", cid, "\n\n")

# -------------------------------
# Download
# -------------------------------
dados_brutos <- fetch_datasus(
  year_start = ano_inicio,
  year_end = ano_fim,
  month_start = mes_inicio,
  month_end = mes_fim,
  uf = uf_param,
  information_system = sistema,
  stop_on_error = TRUE
)

# -------------------------------
# Processamento
# -------------------------------
if (grepl("^SIM", sistema)) {
  dados_final <- preparar_exportacao_sim(
    dados_brutos,
    sexo = sexo,
    raca = raca,
    faixa = faixa,
    cid = cid,
    idade_min = idade_min,
    idade_max = idade_max
  )
} else {
  stop("Sistema não suportado (use SIM-DO).")
}

# -------------------------------
# Exportação
# -------------------------------
contagens <- list(
  etarias = attr(dados_final, "contagens_etarias", exact = TRUE),
  datas = attr(dados_final, "contagens_datas", exact = TRUE),
  naturalidade = attr(dados_final, "contagens_naturalidade", exact = TRUE)
)
auditoria_completa <- attr(dados_final, "auditoria_naturalidade", exact = TRUE)
campos_auditoria <- c("posicao_csv", "registro_id", "naturalidade_codigo_original",
                      "naturalidade_descricao", "naturalidade_situacao", "naturalidade_motivo")
if (!is.data.frame(auditoria_completa) ||
    !identical(names(auditoria_completa), campos_auditoria) ||
    nrow(auditoria_completa) != nrow(dados_final) ||
    !identical(auditoria_completa$posicao_csv, seq_len(nrow(dados_final))) ||
    !is.character(auditoria_completa$registro_id) ||
    anyNA(auditoria_completa$registro_id) || anyDuplicated(auditoria_completa$registro_id) ||
    !identical(auditoria_completa$naturalidade_descricao, dados_final$ESTADO_NATURALIDADE)) {
  stop("Auditoria de naturalidade não corresponde aos registros finais do SIM.")
}
auditoria_saida <- data.frame(
  posicao_registro = auditoria_completa$posicao_csv,
  codigo_original = auditoria_completa$naturalidade_codigo_original,
  situacao = auditoria_completa$naturalidade_situacao,
  motivo = auditoria_completa$naturalidade_motivo,
  descricao = auditoria_completa$naturalidade_descricao,
  stringsAsFactors = FALSE
)
validar_auditoria_naturalidade(auditoria_saida, nrow(dados_final))
# Traduções normais não precisam do auxiliar. Repetições idênticas e outras
# ressalvas da tabela também são exceções, mesmo com descrição inequívoca.
excecoes <- auditoria_saida$situacao != "inequivoca" |
  auditoria_saida$motivo != "correspondencia_unica"
auditoria_saida <- auditoria_saida[excecoes, , drop = FALSE]
relatorio <- publicar_resultado_auditado(
  dados_final, auditoria_saida, caminho_arquivo, metadados, contagens
)
verificar_resultado_auditado(destinos$relatorio, id_execucao = metadados$id_execucao)

cat("Arquivo gerado:", nome_arquivo, "\n")
cat("Auditoria de naturalidade:", basename(destinos$naturalidade), "\n")
cat("Relatório de conclusão:", basename(destinos$relatorio), "\n")
