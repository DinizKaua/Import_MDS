# Executar da raiz: TZ=UTC Rscript --vanilla tests/test_sim_idade.R
# Dados sintéticos; normalização isolada, sem coleta, CSVs ou extração.
modulo <- new.env(parent = baseenv())
source(file.path("R", "sistemas", "sim.R"), local = modulo)
normalizar_idade_sim <- modulo$normalizar_idade_sim

verificar <- function(nome, codigos, unidades, anos, situacoes) {
  antes <- serialize(codigos, NULL)
  esperado <- data.frame(
    idade_codigo_original = unname(codigos),
    idade_unidade_original = unidades,
    idade_anos_completos = anos,
    idade_situacao = situacoes,
    stringsAsFactors = FALSE
  )
  obtido <- normalizar_idade_sim(codigos)
  stopifnot(
    identical(obtido, esperado),
    identical(serialize(codigos, NULL), antes),
    nrow(obtido) == length(codigos)
  )
  cat("OK:", nome, "-", length(codigos), "códigos\n")
  invisible(obtido)
}

verificar(
  "minutos e zeros à esquerda", c("001", "030", "059"),
  c("minutos", "minutos", "minutos"), c(0L, 0L, 0L),
  c("valida", "valida", "valida")
)
verificar(
  "horas", c("100", "101", "123"), c("horas", "horas", "horas"),
  c(0L, 0L, 0L), c("valida", "valida", "valida")
)
verificar(
  "dias", c("200", "201", "228"), c("dias", "dias", "dias"),
  c(0L, 0L, 0L), c("valida", "valida", "valida")
)
verificar(
  "meses: regra conservadora e códigos originais",
  c("300", "301", "306", "311", "312", "399"),
  c("meses", "meses", "meses", "meses", "meses", "meses"),
  c(0L, 0L, 0L, 0L, NA_integer_, NA_integer_),
  c("valida", "valida", "valida", "valida", "invalida", "invalida")
)
verificar(
  "zero anos e limites de faixas", c("400", "417", "418", "459", "460", "499"),
  c("anos", "anos", "anos", "anos", "anos", "anos"),
  c(0L, 17L, 18L, 59L, 60L, 99L),
  c("valida", "valida", "valida", "valida", "valida", "valida")
)
verificar(
  "centena de anos", c("500", "501", "599"),
  c("anos_mais_100", "anos_mais_100", "anos_mais_100"),
  c(100L, 101L, 199L), c("valida", "valida", "valida")
)
verificar(
  "sentinelas e ausentes", c("000", "999", NA_character_),
  c("minutos", NA_character_, NA_character_),
  c(NA_integer_, NA_integer_, NA_integer_),
  c("desconhecida", "desconhecida", "desconhecida")
)
verificar(
  "vazios e espaços sem correção silenciosa", c("", " ", " 418", "418 "),
  c(NA_character_, NA_character_, NA_character_, NA_character_),
  c(NA_integer_, NA_integer_, NA_integer_, NA_integer_),
  c("invalida", "invalida", "invalida", "invalida")
)
verificar(
  "formatos malformados", c("41", "4189", "4.1", "4+1", "4 1", "4e1", "abc", "NA"),
  c(NA_character_, NA_character_, NA_character_, NA_character_, NA_character_, NA_character_, NA_character_, NA_character_),
  c(NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_),
  c("invalida", "invalida", "invalida", "invalida", "invalida", "invalida", "invalida", "invalida")
)
verificar(
  "unidades não reconhecidas", c("600", "700", "800", "900", "998"),
  c(NA_character_, NA_character_, NA_character_, NA_character_, NA_character_),
  c(NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_),
  c("invalida", "invalida", "invalida", "invalida", "invalida")
)
verificar(
  "dígitos ASCII e término exato", c("４１８", "٤١٨", "418\n", "418\r\n", "\t418"),
  c(NA_character_, NA_character_, NA_character_, NA_character_, NA_character_),
  c(NA_integer_, NA_integer_, NA_integer_, NA_integer_, NA_integer_),
  c("invalida", "invalida", "invalida", "invalida", "invalida")
)
verificar(
  "demais unidades sem novos limites fisiológicos", c("099", "199", "299"),
  c("minutos", "horas", "dias"), c(0L, 0L, 0L),
  c("valida", "valida", "valida")
)
verificar(
  "vetor vazio", character(), character(), integer(), character()
)
verificar(
  "ordem, duplicatas e três situações distintas",
  c("418", "000", "400", "600", "001", NA_character_, "418"),
  c("anos", "minutos", "anos", NA_character_, "minutos", NA_character_, "anos"),
  c(18L, NA_integer_, 0L, NA_integer_, 0L, NA_integer_, 18L),
  c("valida", "desconhecida", "valida", "invalida", "valida", "desconhecida", "valida")
)
verificar(
  "vetor nomeado sem alterar entrada", c(a = "001", b = "418"),
  c("minutos", "anos"), c(0L, 18L), c("valida", "valida")
)

# A normalização não tenta reconstruir zeros perdidos por coerção de números.
for (entrada in list(c(1, 418), NA, factor(c("001", "418")), list("418"),
                     matrix("418"), NULL)) {
  antes <- serialize(entrada, NULL)
  mensagem <- tryCatch({ normalizar_idade_sim(entrada); NULL },
                       error = function(e) conditionMessage(e))
  stopifnot(
    identical(mensagem, "codigos deve ser um vetor de caracteres, com NA_character_ para ausentes."),
    identical(serialize(entrada, NULL), antes)
  )
}
cat("OK: rejeição de seis tipos de entrada fora do contrato\n")

# Caracterização local da implementação oficial instalada. Nenhuma coleta.
stopifnot(as.character(packageVersion("microdatasus")) == "3.0.0")
codigos <- c("001", "100", "201", "311", "400", "417", "418", "459", "460", "500", "501", "000", "999", NA_character_)
entrada_oficial <- data.frame(IDADE = codigos, stringsAsFactors = FALSE)
antes <- serialize(entrada_oficial, NULL)
oficial <- microdatasus::process_sim(entrada_oficial, municipality_data = FALSE)
stopifnot(
  identical(serialize(entrada_oficial, NULL), antes),
  identical(oficial$IDADE, c("001", "100", "201", "311", "400", "417", "418", "459", "460", "500", "501", NA_character_, NA_character_, NA_character_)),
  identical(oficial$IDADEminutos, c("1", rep(NA_character_, 13L))),
  identical(oficial$IDADEhoras, c(NA_character_, "0", rep(NA_character_, 12L))),
  identical(oficial$IDADEdias, c(NA_character_, NA_character_, "1", rep(NA_character_, 11L))),
  identical(oficial$IDADEmeses, c(rep(NA_character_, 3L), "11", rep(NA_character_, 10L))),
  identical(oficial$IDADEanos, c(rep(NA_character_, 4L), "0", "17", "18", "59", "60", "100", "101", rep(NA_character_, 3L)))
)
normalizada <- normalizar_idade_sim(codigos)
stopifnot(
  identical(normalizada$idade_codigo_original, codigos),
  identical(normalizada$idade_anos_completos, c(0L, 0L, 0L, 0L, 0L, 17L, 18L, 59L, 60L, 100L, 101L, NA_integer_, NA_integer_, NA_integer_)),
  identical(normalizada$idade_situacao, c(rep("valida", 11L), rep("desconhecida", 3L)))
)
cat("OK: unidades e sentinelas confirmadas no microdatasus 3.0.0 instalado\n")

# Explicita a divergência deliberada de validação: o processador oficial extrai
# substrings permissivamente, enquanto a função nova exige o código completo.
malformados <- c("41", "4189", "4.1", "4+1", "4 1")
oficial_permissivo <- microdatasus::process_sim(
  data.frame(IDADE = malformados, stringsAsFactors = FALSE),
  municipality_data = FALSE
)
stopifnot(
  identical(oficial_permissivo$IDADEanos, c("1", "18", "0.1", "1", "1")),
  identical(normalizar_idade_sim(malformados)$idade_anos_completos, rep(NA_integer_, 5L)),
  identical(normalizar_idade_sim(malformados)$idade_situacao, rep("invalida", 5L))
)
cat("OK: formatos malformados rejeitados apesar da coerção permissiva oficial\n")
cat("PASSOU: 15 grupos de normalização, seis tipos rejeitados e caracterização oficial local.\n")
