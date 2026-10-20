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
  nome <- indice_atribuicao(codigo, "nome_arquivo")
  # Na versão segura o nome é determinado antes do fetch; o processamento novo
  # está todo no despacho. Na linha de base, os filtros seguem esse despacho.
  fim <- if (nome > inicio) nome - 1L else inicio
  bloco <- codigo[inicio:fim]
  # A coleta fica fora do bloco executado, inclusive na versão original.
  stopifnot(!any(c("fetch_datasus", "write.csv") %in% all.names(bloco)))
  bloco
}

bloco_base <- bloco_sim(codigo_base)
bloco_novo <- bloco_sim(codigo_novo)

# As cargas de módulos, os parâmetros etários e o destino seguro precedem a
# coleta. Os demais argumentos e a chamada de fetch permanecem iguais.
prefixo_novo <- codigo_novo[seq_len(indice_despacho(codigo_novo) - 1L)]
adicao_orquestracao <- vapply(prefixo_novo, function(expr) {
  is.call(expr) && (
    identical(expr[[1L]], as.name("source")) ||
      identical(expr, quote(.exigir_jsonlite())) ||
      identical(expr, quote(if (!nzchar(Sys.which("sha256sum"))) stop("Utilitário sha256sum indisponível."))) ||
      (identical(expr[[1L]], as.name("<-")) &&
         as.character(expr[[2L]]) %in% c("idade_min", "idade_max", "limites_idade",
                                       "nome_arquivo", "caminho_arquivo", "destinos", "metadados"))
  )
}, logical(1))
stopifnot(sum(adicao_orquestracao) == 12L)
stopifnot(identical(
  codigo_base[seq_len(indice_despacho(codigo_base) - 1L)],
  prefixo_novo[!adicao_orquestracao]
))
# A publicação mudou intencionalmente. Os bytes CSV e as falhas de publicação
# são comparados com write.csv nos testes específicos de exportação.
stopifnot(any(vapply(codigo_novo, function(expr) {
  identical(expr, quote(relatorio <- publicar_resultado_auditado(
    dados_final, auditoria_saida, caminho_arquivo, metadados, contagens
  )))
}, logical(1))))

executar_sim <- function(bloco, entrada, filtros = list(), sistema = "SIM-DO") {
  ambiente <- list2env(list(
    dados_brutos = entrada, sistema = sistema,
    sexo = "ALL", raca = "ALL", faixa = "ALL", cid = "ALL",
    idade_min = NULL, idade_max = NULL,
    fetch_datasus = function(...) stop("Coleta proibida nos testes locais.")
  ), parent = globalenv())
  list2env(filtros, envir = ambiente)
  if (identical(bloco, bloco_novo)) {
    source(file.path("R", "sistemas", "sim.R"), local = ambiente)
    # A configuração explícita de 18 anos reproduz a seleção da linha de base.
    # As três faixas específicas já fornecem seus próprios limites equivalentes.
    if (!ambiente$faixa %in% c("18-39", "40-59", "60+")) ambiente$idade_min <- 18
  }
  eval(bloco, envir = ambiente)
  resultado <- ambiente$dados_final
  # A auditoria nova é testada separadamente; aqui comparamos todos os valores,
  # tipos e demais atributos da saída legada, sem mudar resultados esperados.
  attr(resultado, "contagens_etarias") <- NULL
  attr(resultado, "contagens_datas") <- NULL
  attr(resultado, "contagens_naturalidade") <- NULL
  attr(resultado, "auditoria_naturalidade") <- NULL
  resultado
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
  # As linhas 11 (NA) e 26 (vazio), ambas adultas, são preservadas agora.
  # Sua inclusão é explícita nos cenários cujos demais filtros as selecionam.
  extras <- if (nome %in% c("sem_opcionais", "masculino", "branca", "faixa_18_39",
                            "faixa_desconhecida_legada", "prefixo_i21", "prefixo_i2")) {
    c(11L, 26L)
  } else integer()
  com_data <- novo[!is.na(novo$DATA), ]
  # identical continua verificando todos os valores, tipos e ordem do subconjunto
  # legado. A população completa nova também tem identificadores esperados.
  stopifnot(
    identical(antigo, com_data), identical(names(novo), colunas),
    identical(novo$ESTABELECIMENTO, sprintf("%07d", sort(c(caso[[2L]], extras)))),
    identical(novo$ESTABELECIMENTO[is.na(novo$DATA)], sprintf("%07d", extras)),
    identical(csv_em_memoria(antigo), csv_em_memoria(com_data))
  )
  cat("OK:", nome, "-", nrow(novo), "linhas\n")
}

resultado <- executar_sim(bloco_novo, entrada)
resultado_com_data <- resultado[!is.na(resultado$DATA), ]
stopifnot(
  identical(resultado_com_data$IDADE, as.character(c(18, 19, 39, 40, 59, 60, 80, 41, 50, 101, 18, 18, 39, 40, 59, 60))),
  identical(resultado_com_data$DATA, rep(as.Date("2020-01-01"), length(todos))),
  identical(resultado_com_data$DATA_DE_NASCIMENTO, rep("2002-01-01", length(todos))),
  identical(resultado_com_data$DOENCA, toupper(entrada$CAUSABAS[todos])),
  identical(resultado$IDADE[is.na(resultado$DATA)], c("38", "18")),
  identical(resultado$DOENCA[is.na(resultado$DATA)], c("I21", "I21")),
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
  com_data <- novo[!is.na(novo$DATA), ]
  stopifnot(identical(antigo, com_data), identical(csv_em_memoria(antigo), csv_em_memoria(com_data)))
  if (nome == "todas_excluidas") stopifnot(
    nrow(antigo) == 0L, nrow(novo) == 2L, all(is.na(novo$DATA)),
    identical(novo$ESTABELECIMENTO, c("0000011", "0000026"))
  )
  if (nome == "data_invalida") stopifnot(
    nrow(antigo) == 0L, nrow(novo) == 1L, is.na(novo$DATA),
    identical(novo$ESTABELECIMENTO, "0000002")
  )
  if (nome == "duplicatas") stopifnot(identical(novo$ESTABELECIMENTO, c("0000002", "0000002", "0000003")))
  if (nome == "ordem_invertida") stopifnot(identical(novo$ESTABELECIMENTO, rev(resultado$ESTABELECIMENTO)))
  cat("OK:", nome, "\n")
}

# Erros de esquema/entrada e SIH não suportado continuam sendo propagados.
for (dados in list(entrada[, names(entrada) != "DTNASC"])) {
  antigo <- capturar_erro(executar_sim(bloco_base, dados))
  novo <- capturar_erro(executar_sim(bloco_novo, dados))
  stopifnot(!is.null(antigo), identical(antigo, novo))
}
# Uma entrada NULL continua falhando, agora no guard de integridade anterior ao
# processador; a mensagem nova é explícita em vez do erro indireto de mutate.
stopifnot(
  !is.null(capturar_erro(executar_sim(bloco_base, NULL))),
  identical(capturar_erro(executar_sim(bloco_novo, NULL)),
            "Dados brutos do SIM devem conter a coluna IDADE original.")
)
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
  ambiente <- list2env(list(
    sistema = "SIM-DO", uf_param = uf_param, ano_inicio = 2015, ano_fim = 2024,
    cid = "ALL", sexo = "ALL", raca = "ALL", faixa = "ALL",
    idade_min = NULL, idade_max = NULL, mes_inicio = 1, mes_fim = 12,
    limites_idade = list(idade_min = NULL, idade_max = NULL)
  ), parent = baseenv())
  list2env(filtros, envir = ambiente)
  if (identical(codigo, codigo_novo)) {
    source(file.path("R", "comum", "exportacao.R"), local = ambiente)
    eval(codigo[[inicio]], envir = ambiente)
    return(ambiente$nome_arquivo)
  }
  fim <- which(vapply(codigo, function(expr) {
    is.call(expr) && identical(expr[[1L]], as.name("write.csv"))
  }, logical(1)))
  stopifnot(length(fim) == 1L)
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
cat("OK: idade explícita de 18 anos reproduz o legado nas datas válidas; linhas sem data são preservadas; coleta/exportação e nomes mantidos\n")
cat("PASSOU: 20 cenários de filtros e 4 entradas adicionais; nenhuma coleta executada.\n")
