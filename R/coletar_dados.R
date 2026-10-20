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

# -------------------------------
# Tratamento UF
# -------------------------------
uf_param <- if (uf == "ALL") "all" else uf

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

  dados <- process_sim(dados_brutos) %>%
    mutate(
      data_evento = as.Date(DTOBITO),
      cid_valor = toupper(CAUSABAS),
      IDADE_NUM = as.numeric(IDADEanos)
    )

} else {
  stop("Sistema não suportado (use SIM-DO).")
}

# Remove sem data e garante 18+
dados <- dados %>%
  filter(!is.na(data_evento)) %>%
  filter(!is.na(IDADE_NUM) & IDADE_NUM >= 18)

# -------------------------------
# FILTROS
# -------------------------------

if (sexo != "ALL") {
  dados <- dados %>% filter(SEXO == sexo)
}

if (raca != "ALL") {
  dados <- dados %>% filter(RACACOR == raca)
}

# Faixa etária 
if (faixa != "ALL") {

  if (faixa == "18-39") {
    dados <- dados %>% filter(IDADE_NUM >= 18 & IDADE_NUM <= 39)
  } else if (faixa == "40-59") {
    dados <- dados %>% filter(IDADE_NUM >= 40 & IDADE_NUM <= 59)
  } else if (faixa == "60+") {
    dados <- dados %>% filter(IDADE_NUM >= 60)
  }
}

if (cid != "ALL") {
  dados <- dados %>%
    filter(startsWith(cid_valor, cid))
}

# -------------------------------
# SELEÇÃO FINAL
# -------------------------------
dados_final <- dados %>%
  select(any_of(c(
    "IDADEanos",
    "DTNASC",
    "ESTCIV",
    "SEXO",
    "RACACOR",
    "LOCOCOR",
    "CODESTAB",
    "data_evento",
    "munResUf",
    "munResNome",
    "NATURAL",
    "CODMUNNATU",
    "ASSISTMED",
    "cid_valor"
  ))) %>%
  rename(
    IDADE = IDADEanos,
    DATA_DE_NASCIMENTO = DTNASC,
    ESTADO_CIVIL = ESTCIV,
    RACA_COR = RACACOR,
    LOCAL_OBITO = LOCOCOR,
    ESTABELECIMENTO = CODESTAB,
    DATA = data_evento,
    ESTADO_RESIDENCIA = munResUf,
    MUNICIPIO_RESIDENCIA = munResNome,
    ESTADO_NATURALIDADE = NATURAL,
    MUNICIPIO_NATURALIDADE = CODMUNNATU,
    ASSISTENCIA_MEDICA = ASSISTMED,
    DOENCA = cid_valor
  )

# -------------------------------
# Nome do arquivo
# -------------------------------
nome_arquivo <- paste0(
  "dados_",
  sistema, "_",
  ifelse(uf_param == "all", "BR", uf_param), "_",
  ano_inicio, "_", ano_fim
)

if (cid != "ALL") nome_arquivo <- paste0(nome_arquivo, "_", cid)
if (sexo != "ALL") nome_arquivo <- paste0(nome_arquivo, "_", sexo)
if (raca != "ALL") nome_arquivo <- paste0(nome_arquivo, "_", raca)
if (faixa != "ALL") nome_arquivo <- paste0(nome_arquivo, "_", faixa)

nome_arquivo <- paste0(nome_arquivo, ".csv")

# -------------------------------
# Exportação
# -------------------------------
write.csv(dados_final, nome_arquivo, row.names = FALSE)

cat("Arquivo gerado:", nome_arquivo, "\n")