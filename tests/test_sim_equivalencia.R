# Executar da raiz: TZ=UTC Rscript --vanilla tests/test_sim_equivalencia.R
# Não executa os scripts de coleta. Apenas os blocos de processamento extraídos
# da árvore sintática são avaliados, com dados sintéticos e sem chamada de fetch.

suppressPackageStartupMessages({
  library(microdatasus)
  library(dplyr)
})

if (as.character(packageVersion("microdatasus")) != "3.0.0") {
  stop("Esta comparação caracteriza a API microdatasus 3.0.0 da linha de base.")
}

baseline <- "0d3c0ba8aef42f70ddddf61331b8491e57faf215"
texto_base <- system2(
  "git", c("show", paste0(baseline, ":R/coletar_dados.R")),
  stdout = TRUE
)
if (!is.null(attr(texto_base, "status"))) {
  stop("Não foi possível ler o script do commit da linha de base.")
}
codigo_base <- parse(text = texto_base)
codigo_novo <- parse(file = "R/coletar_dados.R")

indice_atribuicao <- function(codigo, nome) {
  indices <- which(vapply(codigo, function(expr) {
    is.call(expr) && identical(expr[[1L]], as.name("<-")) &&
      identical(expr[[2L]], as.name(nome))
  }, logical(1)))
  # nome_arquivo recebe o nome inicial e, depois, a extensão.
  stopifnot(length(indices) >= 1L)
  indices[[1L]]
}

indice_despacho <- function(codigo) {
  indices <- which(vapply(codigo, function(expr) {
    is.call(expr) && identical(expr[[1L]], as.name("if")) &&
      identical(expr[[2L]], quote(grepl("^SIM", sistema)))
  }, logical(1)))
  stopifnot(length(indices) == 1L)
  indices
}

bloco_sim <- function(codigo) {
  inicio <- indice_despacho(codigo)
  fim <- indice_atribuicao(codigo, "nome_arquivo") - 1L
  bloco <- codigo[inicio:fim]
  # A coleta fica fora do bloco executado, inclusive na versão original.
  stopifnot(!any(c("fetch_datasus", "write.csv") %in% all.names(bloco)))
  bloco
}

bloco_base <- bloco_sim(codigo_base)
bloco_novo <- bloco_sim(codigo_novo)

# Parse, parâmetros, chamada de coleta, nomenclatura e exportação permanecem
# estruturalmente idênticos. A chamada de coleta é inspecionada, nunca executada.
stopifnot(identical(
  codigo_base[seq_len(indice_despacho(codigo_base) - 1L)],
  codigo_novo[seq_len(indice_despacho(codigo_novo) - 1L)]
))
exportacao_base <- codigo_base[
  indice_atribuicao(codigo_base, "nome_arquivo"):length(codigo_base)
]
exportacao_nova <- codigo_novo[
  indice_atribuicao(codigo_novo, "nome_arquivo"):length(codigo_novo)
]
stopifnot(identical(exportacao_base, exportacao_nova))

executar_sim <- function(bloco, entrada, filtros = list(), sistema = "SIM-DO") {
  ambiente <- list2env(list(
    dados_brutos = entrada, sistema = sistema,
    sexo = "ALL", raca = "ALL", faixa = "ALL", cid = "ALL",
    fetch_datasus = function(...) stop("Coleta proibida nos testes locais.")
  ), parent = globalenv())
  list2env(filtros, envir = ambiente)
  eval(bloco, envir = ambiente)
  ambiente$dados_final
}

capturar_erro <- function(expr) {
  tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
}

csv_em_memoria <- function(dados) {
  capture.output(utils::write.csv(dados, file = "", row.names = FALSE))
}

# Estabelecimentos numerados servem apenas para identificar linhas sintéticas.
idades <- c(
  "417", "418", "419", "439", "440", "459", "460", "480", "999", NA,
  "438", "441", "450", "501", "301", "201", "101", "001", "418", "418",
  "439", "440", "459", "460", "000", "418"
)
n <- length(idades)
entrada <- data.frame(
  DTOBITO = rep("01012020", n), DTNASC = rep("01012002", n),
  IDADE = idades, ESTCIV = rep("1", n),
  SEXO = c(
    "1", "1", "2", "1", "2", "1", "2", "1", "1", "2", "1", "2", "0",
    "1", "1", "1", "1", "1", "1", "2", "2", "1", "2", "1", "1", "1"
  ),
  RACACOR = c(
    "1", "1", "2", "4", "3", "5", "1", "4", "1", "1", "1", NA, "1",
    "2", "1", "1", "1", "1", "2", "1", "4", "1", "2", "3", "1", "1"
  ),
  CAUSABAS = c(
    "I21", "I21", "i210", "I219", "C50", "I21", "I210", "J189", "I21",
    "I21", "I21", NA, "I21", "C509", "I21", "I21", "I21", "I21", "I2",
    " I21", "I21", "I21", "I219", "I210", "I21", "I21"
  ),
  LOCOCOR = rep("1", n), CODESTAB = sprintf("%07d", seq_len(n)),
  CODMUNRES = rep("211130", n), NATURAL = rep("821", n),
  CODMUNNATU = rep("211130", n), ASSISTMED = rep("1", n),
  COLUNA_EXTRA = rep("descartar", n), stringsAsFactors = FALSE
)
entrada$DTOBITO[11L] <- NA_character_
entrada$DTOBITO[26L] <- ""

colunas <- c(
  "IDADE", "DATA_DE_NASCIMENTO", "ESTADO_CIVIL", "SEXO", "RACA_COR",
  "LOCAL_OBITO", "ESTABELECIMENTO", "DATA", "ESTADO_RESIDENCIA",
  "MUNICIPIO_RESIDENCIA", "ESTADO_NATURALIDADE", "MUNICIPIO_NATURALIDADE",
  "ASSISTENCIA_MEDICA", "DOENCA"
)
todos <- c(2L, 3L, 4L, 5L, 6L, 7L, 8L, 12L, 13L, 14L, 19L, 20L, 21L, 22L, 23L, 24L)
casos <- list(
  sem_opcionais = list(list(), todos),
  masculino = list(list(sexo = "Masculino"), c(2L, 4L, 6L, 8L, 14L, 19L, 22L, 24L)),
  feminino = list(list(sexo = "Feminino"), c(3L, 5L, 7L, 12L, 20L, 21L, 23L)),
  branca = list(list(raca = "Branca"), c(2L, 7L, 13L, 20L, 22L)),
  preta = list(list(raca = "Preta"), c(3L, 14L, 19L, 23L)),
  parda = list(list(raca = "Parda"), c(4L, 8L, 21L)),
  amarela = list(list(raca = "Amarela"), c(5L, 24L)),
  indigena_acentuada = list(list(raca = "Indígena"), 6L),
  indigena_cli_legada = list(list(raca = "Indigena"), integer()),
  faixa_18_39 = list(list(faixa = "18-39"), c(2L, 3L, 4L, 19L, 20L, 21L)),
  faixa_40_59 = list(list(faixa = "40-59"), c(5L, 6L, 12L, 13L, 22L, 23L)),
  faixa_60_mais = list(list(faixa = "60+"), c(7L, 8L, 14L, 24L)),
  faixa_desconhecida_legada = list(list(faixa = "outra"), todos),
  prefixo_i21 = list(list(cid = "I21"), c(2L, 3L, 4L, 6L, 7L, 13L, 21L, 22L, 23L, 24L)),
  prefixo_i2 = list(list(cid = "I2"), c(2L, 3L, 4L, 6L, 7L, 13L, 19L, 21L, 22L, 23L, 24L)),
  prefixo_i210 = list(list(cid = "I210"), c(3L, 7L, 24L)),
  prefixo_c50 = list(list(cid = "C50"), c(5L, 14L)),
  prefixo_com_espaco_legado = list(list(cid = " I21"), 20L),
  filtros_combinados = list(
    list(sexo = "Feminino", raca = "Preta", faixa = "18-39", cid = "I21"), 3L
  ),
  resultado_vazio = list(list(cid = "Z999"), integer())
)

for (nome in names(casos)) {
  caso <- casos[[nome]]
  antigo <- executar_sim(bloco_base, entrada, caso[[1L]])
  novo <- executar_sim(bloco_novo, entrada, caso[[1L]])
  # identical verifica valores, tipos, ordem de linhas/colunas e atributos.
  stopifnot(
    identical(antigo, novo), identical(names(novo), colunas),
    identical(novo$ESTABELECIMENTO, sprintf("%07d", caso[[2L]])),
    identical(csv_em_memoria(antigo), csv_em_memoria(novo))
  )
  cat("OK:", nome, "-", nrow(novo), "linhas\n")
}

resultado <- executar_sim(bloco_novo, entrada)
stopifnot(
  identical(resultado$IDADE, as.character(c(18, 19, 39, 40, 59, 60, 80, 41, 50, 101, 18, 18, 39, 40, 59, 60))),
  identical(resultado$DATA, rep(as.Date("2020-01-01"), length(todos))),
  identical(resultado$DATA_DE_NASCIMENTO, rep("2002-01-01", length(todos))),
  identical(resultado$DOENCA, toupper(entrada$CAUSABAS[todos])),
  is.na(resultado$SEXO[match("0000013", resultado$ESTABELECIMENTO)]),
  is.na(resultado$RACA_COR[match("0000012", resultado$ESTABELECIMENTO)])
)
cat("OK: valores independentes esperados, ausentes e identificadores com zeros\n")

# Todas as linhas excluídas; duplicatas; ordem da entrada; data inválida.
entradas_adicionais <- list(
  todas_excluidas = entrada[c(1L, 9L, 10L, 11L, 15L:18L, 25L, 26L), ],
  duplicatas = entrada[c(2L, 2L, 3L), ],
  ordem_invertida = entrada[rev(seq_len(n)), ],
  data_invalida = transform(entrada[2L, ], DTOBITO = "32132020")
)
for (nome in names(entradas_adicionais)) {
  dados <- entradas_adicionais[[nome]]
  antigo <- executar_sim(bloco_base, dados)
  novo <- executar_sim(bloco_novo, dados)
  stopifnot(identical(antigo, novo), identical(csv_em_memoria(antigo), csv_em_memoria(novo)))
  if (nome %in% c("todas_excluidas", "data_invalida")) stopifnot(nrow(novo) == 0L)
  if (nome == "duplicatas") stopifnot(identical(novo$ESTABELECIMENTO, c("0000002", "0000002", "0000003")))
  if (nome == "ordem_invertida") stopifnot(identical(novo$ESTABELECIMENTO, rev(resultado$ESTABELECIMENTO)))
  cat("OK:", nome, "\n")
}

# Erros de esquema/entrada e SIH não suportado continuam sendo propagados.
for (dados in list(entrada[, names(entrada) != "DTNASC"], NULL)) {
  antigo <- capturar_erro(executar_sim(bloco_base, dados))
  novo <- capturar_erro(executar_sim(bloco_novo, dados))
  stopifnot(!is.null(antigo), identical(antigo, novo))
}
for (bloco in list(bloco_base, bloco_novo)) {
  stopifnot(identical(
    capturar_erro(executar_sim(bloco, entrada, sistema = "SIH-RD")),
    "Sistema não suportado (use SIM-DO)."
  ))
}
cat("OK: erros propagados e SIH não suportado\n")

# Exercita a nomenclatura legada sem executar write.csv ou ler CSVs existentes.
nome_legado <- function(codigo, uf_param, filtros = list()) {
  inicio <- indice_atribuicao(codigo, "nome_arquivo")
  fim <- which(vapply(codigo, function(expr) {
    is.call(expr) && identical(expr[[1L]], as.name("write.csv"))
  }, logical(1)))
  stopifnot(length(fim) == 1L)
  ambiente <- list2env(list(
    sistema = "SIM-DO", uf_param = uf_param, ano_inicio = 2015, ano_fim = 2024,
    cid = "ALL", sexo = "ALL", raca = "ALL", faixa = "ALL"
  ), parent = baseenv())
  list2env(filtros, envir = ambiente)
  eval(codigo[inicio:(fim - 1L)], envir = ambiente)
  ambiente$nome_arquivo
}
for (codigo in list(codigo_base, codigo_novo)) {
  stopifnot(
    identical(nome_legado(codigo, "all"), "dados_SIM-DO_BR_2015_2024.csv"),
    identical(nome_legado(codigo, "MA", list(cid = "I21")), "dados_SIM-DO_MA_2015_2024_I21.csv"),
    identical(
      nome_legado(codigo, "MA", list(cid = "I21", sexo = "Feminino", raca = "Preta", faixa = "18-39")),
      "dados_SIM-DO_MA_2015_2024_I21_Feminino_Preta_18-39.csv"
    )
  )
}
cat("OK: parâmetros/coleta/exportação inalterados e nomes nacionais/UF/filtros\n")
cat("PASSOU: 20 cenários de filtros e 4 entradas adicionais; nenhuma coleta executada.\n")
