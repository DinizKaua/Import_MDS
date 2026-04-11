suppressPackageStartupMessages({
  library(microdatasus)
  library(dplyr)
  library(lubridate)
})

# -------------------------------
#   Parse de argumentos (--param valor)
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
#   Parâmetros com fallback
# -------------------------------
sistema <- if (!is.null(args$system)) args$system else "SIM-DO"
ano_inicio <- as.numeric(if (!is.null(args$year_start)) args$year_start else 2020)
ano_fim <- as.numeric(if (!is.null(args$year_end)) args$year_end else 2020)
mes_inicio <- as.numeric(if (!is.null(args$month_start)) args$month_start else 1)
mes_fim <- as.numeric(if (!is.null(args$month_end)) args$month_end else 12)
uf <- if (!is.null(args$uf)) toupper(args$uf) else "ALL"
sexo <- if (!is.null(args$sexo)) args$sexo else "ALL"
cid <- if (!is.null(args$cid)) toupper(args$cid) else "ALL"

# -------------------------------
#   Tratamento UF (corrige erro do ifelse)
# -------------------------------
if (uf == "ALL") {
  uf_param <- NULL
} else {
  uf_param <- uf
}

cat("Parâmetros recebidos:\n")
cat("Sistema:", sistema, "\n")
cat("Período:", ano_inicio, "-", ano_fim, "\n")
cat("UF:", uf, "\n")
cat("Sexo:", sexo, "\n")
cat("CID:", cid, "\n\n")

# -------------------------------
#   Download dos dados
# -------------------------------
dados_brutos <- fetch_datasus(
  year_start = ano_inicio,
  year_end = ano_fim,
  month_start = mes_inicio,
  month_end = mes_fim,
  uf = uf_param,
  information_system = sistema
)

# -------------------------------
#   Processamento
# -------------------------------
if (grepl("^SIM", sistema)) {

  dados <- process_sim(dados_brutos) %>%
    mutate(
      data_evento = as.Date(DTOBITO),
      cid_valor = toupper(CAUSABAS)
    )

} else if (sistema == "SIH-RD") {

  dados <- process_sih(dados_brutos)

  # Detecta colunas automaticamente
  date_col <- intersect(c("DT_INTER", "DT_INTERNA", "DT_ENTRADA"), colnames(dados))[1]
  cid_col <- intersect(c("DIAG_PRINC", "CIDPRI"), colnames(dados))[1]

  dados <- dados %>%
    mutate(
      data_evento = as.Date(.data[[date_col]]),
      cid_valor = toupper(.data[[cid_col]])
    )

} else {
  stop("Sistema não suportado ainda.")
}

# Remove dados sem data
dados <- dados %>% filter(!is.na(data_evento))

# -------------------------------
#   FILTROS
# -------------------------------

# Sexo
if (sexo != "ALL") {
  dados <- dados %>% filter(SEXO == sexo)
}

# CID (prefixo)
if (cid != "ALL") {
  dados <- dados %>%
    filter(startsWith(cid_valor, cid))
}

# -------------------------------
#   Nome do arquivo inteligente
# -------------------------------
nome_arquivo <- paste0(
  "dados_",
  sistema, "_",
  ifelse(is.null(uf_param), "BR", uf_param), "_",
  ano_inicio, "_", ano_fim,
  ifelse(cid != "ALL", paste0("_", cid), ""),
  ifelse(sexo != "ALL", paste0("_", sexo), ""),
  ".csv"
)

# -------------------------------
#   SELEÇÃO E PADRONIZAÇÃO
# -------------------------------

dados_final <- dados %>%
  mutate(
    ANO = lubridate::year(data_evento)
  ) %>%
  select(
    IDADE = IDADEanos,
    SEXO,
    RACA_COR = RACACOR,
    ESTADO = munResUf,
    MUNICIPIO = munResNome,
    ANO,
    DOENCA = cid_valor
  )

# -------------------------------
#   Exportação
# -------------------------------
write.csv(dados_final, nome_arquivo, row.names = FALSE)

cat("Arquivo gerado:", nome_arquivo, "\n")