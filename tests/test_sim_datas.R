# Executar da raiz: TZ=UTC Rscript --vanilla tests/test_sim_datas.R
# Validação isolada, dados sintéticos em memória; sem coleta ou escrita de CSV.
modulo <- new.env(parent = baseenv())
source(file.path("R", "sistemas", "sim.R"), local = modulo)
validar <- modulo$validar_data_obito_sim

verificar <- function(nome, codigos, datas, situacoes, motivos) {
  antes <- serialize(codigos, NULL)
  esperado <- data.frame(
    data_obito_original = unname(codigos),
    data_obito_validada = as.Date(datas, format = "%Y-%m-%d"),
    data_obito_situacao = situacoes,
    data_obito_motivo = motivos,
    stringsAsFactors = FALSE
  )
  obtido <- validar(codigos)
  stopifnot(
    identical(obtido, esperado),
    identical(serialize(codigos, NULL), antes),
    nrow(obtido) == length(codigos),
    inherits(obtido$data_obito_validada, "Date"),
    identical(vapply(obtido, typeof, character(1)),
              c(data_obito_original = "character", data_obito_validada = "double",
                data_obito_situacao = "character", data_obito_motivo = "character"))
  )
  cat("OK:", nome, "-", length(codigos), "entradas\n")
  invisible(obtido)
}

verificar(
  "bissexto e ano comum", c("29022020", "28022021"),
  c("2020-02-29", "2021-02-28"), rep("valida", 2L), rep("codigo_valido", 2L)
)
verificar(
  "datas impossíveis", c("29022021", "31022020", "32132020", "31042020", "00012020", "01002020"),
  rep(NA_character_, 6L), rep("invalida", 6L), rep("data_calendario_invalida", 6L)
)
verificar(
  "truncamentos, excedentes e formatos alternativos",
  c("01012020xyz", "1012020", "010120", "2020-02-29", "29/02/2020", "010120200"),
  rep(NA_character_, 6L), rep("invalida", 6L), rep("formato_invalido", 6L)
)
verificar(
  "ausências distintas e espaços originais",
  c(NA_character_, "", " ", "   "), rep(NA_character_, 4L), rep("ausente", 4L),
  c("ausente_na", "ausente_vazio", "ausente_espacos", "ausente_espacos")
)
verificar(
  "zero à esquerda e limites de mês e ano",
  c("01012020", "31012020", "01022020", "31122020", "01012021", "30042020", "01052020"),
  c("2020-01-01", "2020-01-31", "2020-02-01", "2020-12-31", "2021-01-01", "2020-04-30", "2020-05-01"),
  rep("valida", 7L), rep("codigo_valido", 7L)
)
verificar(
  "ASCII e correspondência do código inteiro",
  c("abcdefgh", "０１０１２０２０", "٠١٠١٢٠٢٠", "01012020\n", "01012020\r\n",
    " 01012020", "01012020 ", "\t", "\n", "\u00a0", "NA"),
  rep(NA_character_, 11L), rep("invalida", 11L), rep("formato_invalido", 11L)
)
verificar(
  "sentinelas sem regra aprovada são inválidas", c("00000000", "99999999"),
  rep(NA_character_, 2L), rep("invalida", 2L), rep("data_calendario_invalida", 2L)
)
verificar(
  "calendário gregoriano secular",
  c("29021900", "29022000", "29021500", "29021600"),
  c(NA_character_, "2000-02-29", NA_character_, "1600-02-29"),
  c("invalida", "valida", "invalida", "valida"),
  c("data_calendario_invalida", "codigo_valido", "data_calendario_invalida", "codigo_valido")
)
verificar(
  "anos de quatro dígitos sem limites epidemiológicos",
  c("01010000", "01010001", "01010020", "31120999", "01011000", "31129999"),
  c("0000-01-01", "0001-01-01", "0020-01-01", "0999-12-31", "1000-01-01", "9999-12-31"),
  rep("valida", 6L), rep("codigo_valido", 6L)
)
verificar("vetor vazio", character(), character(), character(), character())

codigos <- c("29022020", NA_character_, "31022020", "29022020", "", "  ", "1012020", "28022021")
esperado <- verificar(
  "ordem, duplicatas e separação de situações", codigos,
  c("2020-02-29", NA_character_, NA_character_, "2020-02-29", NA_character_, NA_character_, NA_character_, "2021-02-28"),
  c("valida", "ausente", "invalida", "valida", "ausente", "ausente", "invalida", "valida"),
  c("codigo_valido", "ausente_na", "data_calendario_invalida", "codigo_valido",
    "ausente_vazio", "ausente_espacos", "formato_invalido", "codigo_valido")
)
verificar(
  "vetor nomeado sem mutação", c(a = "01012020", b = NA_character_),
  c("2020-01-01", NA_character_), c("valida", "ausente"), c("codigo_valido", "ausente_na")
)

# A conversão usa formato explícito, sem inferir o formato pela primeira linha.
for (ordem in list(rev(seq_along(codigos)), c(3L, 6L, 2L, 8L, 7L, 1L, 4L, 5L))) {
  reordenado <- validar(codigos[ordem])
  referencia <- esperado[ordem, , drop = FALSE]
  rownames(referencia) <- NULL
  stopifnot(identical(reordenado, referencia))
}
for (i in seq_along(codigos)) {
  referencia <- esperado[i, , drop = FALSE]
  rownames(referencia) <- NULL
  stopifnot(identical(validar(codigos[i]), referencia))
}
cat("OK: resultado independente da ordem e do processamento em lote/individual\n")

for (entrada in list(1012020, NA, factor("01012020"), list("01012020"),
                     matrix("01012020"), NULL, as.Date("2020-01-01"))) {
  antes <- serialize(entrada, NULL)
  mensagem <- tryCatch({ validar(entrada); NULL }, error = function(e) conditionMessage(e))
  stopifnot(
    identical(mensagem, "codigos deve ser um vetor de caracteres, com NA_character_ para ausentes."),
    identical(serialize(entrada, NULL), antes)
  )
}
cat("OK: entradas fora do contrato rejeitadas, sem reconstruir zeros perdidos\n")

# Caracteriza o problema do processador oficial instalado, sem chamar fetch.
stopifnot(as.character(packageVersion("microdatasus")) == "3.0.0")
brutos <- c("01012020xyz", "1012020", "010120", "29022020", NA_character_, "", "31022020")
entrada <- data.frame(DTOBITO = brutos, stringsAsFactors = FALSE)
antes <- serialize(entrada, NULL)
oficial <- microdatasus::process_sim(entrada, municipality_data = FALSE)
stopifnot(
  identical(oficial$DTOBITO, c("2020-01-01", "20-12-10", "20-01-01", "2020-02-29", NA_character_, NA_character_, NA_character_)),
  identical(serialize(entrada, NULL), antes),
  identical(validar(brutos)$data_obito_situacao,
            c("invalida", "invalida", "invalida", "valida", "ausente", "ausente", "invalida"))
)
cat("OK: coerção permissiva do microdatasus 3.0.0 rejeitada pela validação isolada\n")

# Simula uma conversão normalizada indevidamente: a ida e volta deve rejeitá-la.
# Não altera as.Date global nem depende de comportamento específico da plataforma.
guardado <- new.env(parent = baseenv())
sys.source(file.path("R", "sistemas", "sim.R"), envir = guardado)
guardado$as.Date <- function(x, ...) {
  if (identical(x, "31022020")) return(base::as.Date("2020-03-02"))
  base::as.Date(x, ...)
}
rejeitado <- guardado$validar_data_obito_sim("31022020")
stopifnot(
  identical(rejeitado$data_obito_original, "31022020"),
  identical(rejeitado$data_obito_validada, as.Date(NA_character_)),
  identical(rejeitado$data_obito_situacao, "invalida"),
  identical(rejeitado$data_obito_motivo, "conversao_nao_reversivel")
)
cat("OK: correspondência de ida e volta rejeita conversão incorreta simulada\n")
cat("PASSOU: 12 grupos, ordem/cardinalidade, tipos, caracterização oficial e guarda de ida e volta; sem downloads.\n")
