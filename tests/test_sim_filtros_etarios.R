# Executar da raiz: TZ=UTC Rscript --vanilla tests/test_sim_filtros_etarios.R
# Apenas dados sintéticos; o script de coleta é analisado, nunca executado inteiro.
suppressPackageStartupMessages(library(microdatasus))
stopifnot(as.character(packageVersion("microdatasus")) == "3.0.0")
source(file.path("R", "comum", "cid.R"), local = TRUE)
source(file.path("R", "sistemas", "sim.R"), local = TRUE)

idades <- c(
  "000", "001", "123", "228", "306", "311", "312", "399", "400", "417",
  "418", "439", "440", "459", "460", "500", "501", "999", NA, "600",
  "4189", "418", "4.1"
)
entrada <- data.frame(
  IDADE = idades, DTOBITO = rep("01012020", 23L), DTNASC = rep("01012002", 23L),
  ESTCIV = rep("1", 23L), SEXO = rep("1", 23L), RACACOR = rep("1", 23L),
  CAUSABAS = rep("I21", 23L), LOCOCOR = rep("1", 23L),
  CODESTAB = sprintf("%07d", 1:23), CODMUNRES = rep("211130", 23L),
  NATURAL = rep("821", 23L), CODMUNNATU = rep("211130", 23L),
  ASSISTMED = rep("1", 23L), stringsAsFactors = FALSE
)
entrada$DTOBITO[22L] <- NA_character_
entrada$SEXO[c(5L, 11L, 14L, 17L)] <- "2"
entrada$RACACOR[c(5L, 11L, 14L, 17L)] <- "4"
entrada$CAUSABAS[c(5L, 14L, 17L)] <- c("i210", "I219", "C50")
colunas <- c(
  "IDADE", "DATA_DE_NASCIMENTO", "ESTADO_CIVIL", "SEXO", "RACA_COR",
  "LOCAL_OBITO", "ESTABELECIMENTO", "DATA", "ESTADO_RESIDENCIA",
  "MUNICIPIO_RESIDENCIA", "ESTADO_NATURALIDADE", "MUNICIPIO_NATURALIDADE",
  "ASSISTENCIA_MEDICA", "DOENCA"
)
sem_limites <- 1:23
maiores <- c(11:17, 22L)
validas <- c(2:6, 9:17, 22L)
casos <- list(
  nenhum_limite = list(list(), sem_limites),
  apenas_minimo = list(list(idade_min = 18), maiores),
  apenas_maximo = list(list(idade_max = 18), c(2:6, 9:11, 22L)),
  ambos_inclusivos = list(list(idade_min = 18, idade_max = 59), c(11:14, 22L)),
  limite_igual = list(list(idade_min = 18, idade_max = 18), c(11L, 22L)),
  zero_e_menores_de_um_ano = list(list(idade_max = 0), c(2:6, 9L)),
  minimo_zero_exclui_nao_interpretaveis = list(list(idade_min = 0), validas),
  centenarios = list(list(idade_min = 100), 16:17),
  maximo_amplo_ainda_exclui_nao_interpretaveis = list(list(idade_max = 200), validas),
  resultado_vazio = list(list(idade_min = 102), integer()),
  faixa_18_39 = list(list(faixa = "18-39"), c(11:12, 22L)),
  faixa_40_59 = list(list(faixa = "40-59"), 13:14),
  faixa_60_mais = list(list(faixa = "60+"), 15:17),
  faixa_all_e_novos_limites = list(list(faixa = "ALL", idade_min = 18), maiores),
  faixa_desconhecida_sem_efeito_legado = list(list(faixa = "outra"), sem_limites),
  limites_textuais = list(list(idade_min = "018", idade_max = "059"), c(11:14, 22L)),
  sexo_raca_cid_sem_limites = list(list(sexo = "Feminino", raca = "Parda", cid = "I21"), c(5L, 11L, 14L)),
  sexo_raca_cid_com_limites = list(list(sexo = "Feminino", raca = "Parda", cid = "I21", idade_min = 18), c(11L, 14L))
)

resultados <- list()
for (nome in names(casos)) {
  caso <- casos[[nome]]
  antes <- serialize(entrada, NULL)
  resultado <- do.call(preparar_exportacao_sim, c(list(dados_brutos = entrada), caso[[1L]]))
  stopifnot(
    identical(resultado$ESTABELECIMENTO, sprintf("%07d", caso[[2L]])),
    identical(names(resultado), colunas),
    identical(serialize(entrada, NULL), antes)
  )
  resultados[[nome]] <- resultado
  cat("OK:", nome, "-", nrow(resultado), "linhas\n")
}

# A linha 22 (18 anos, data ausente) agora participa da seleção etária.
# Os demais critérios e resultados esperados permanecem os mesmos.
esperado_sem <- list(
  filtro_ativo = FALSE, idade_min = NULL, idade_max = NULL,
  entrada = 23L, excluidos_sem_data = 0L, antes_filtro_etario = 23L,
  idades_validas = 15L, idades_desconhecidas = 3L, idades_invalidas = 5L,
  excluidos_desconhecidos = 0L, excluidos_invalidos = 0L,
  excluidos_fora_limites = 0L, apos_filtro_etario = 23L, apos_demais_filtros = 23L
)
esperado_min <- list(
  filtro_ativo = TRUE, idade_min = 18, idade_max = NULL,
  entrada = 23L, excluidos_sem_data = 0L, antes_filtro_etario = 23L,
  idades_validas = 15L, idades_desconhecidas = 3L, idades_invalidas = 5L,
  excluidos_desconhecidos = 3L, excluidos_invalidos = 5L,
  excluidos_fora_limites = 7L, apos_filtro_etario = 8L, apos_demais_filtros = 8L
)
stopifnot(
  identical(attr(resultados$nenhum_limite, "contagens_etarias"), esperado_sem),
  identical(attr(resultados$apenas_minimo, "contagens_etarias"), esperado_min),
  identical(attr(resultados$sexo_raca_cid_com_limites, "contagens_etarias")$apos_demais_filtros, 2L)
)
cat("OK: contagens explícitas e separadas para desconhecidos, inválidos e fora dos limites\n")

# O CSV conserva o mapeamento de IDADEanos, mesmo para subanuais normalizados
# como zero. A idade usada no filtro fica nas colunas auxiliares, não no CSV.
stopifnot(
  identical(resultados$zero_e_menores_de_um_ano$IDADE, c(rep(NA_character_, 5L), "0")),
  identical(resultados$apenas_minimo$IDADE, c("18", "39", "40", "59", "60", "100", "101", "18"))
)

erro <- function(expr) tryCatch({ force(expr); NULL }, error = function(e) conditionMessage(e))
invalidos <- list(-1, 18.5, "-1", "18.5", "18.0", "1e2", "+18", "18abc", " 18",
                  "18 ", "18\n", "", NA_real_, NA_character_, NaN, Inf, TRUE,
                  c(18, 19), character(), list(18), factor("18"), matrix(18), 18+0i,
                  "9007199254740992")
for (valor in invalidos) {
  for (nome in c("idade_min", "idade_max")) {
    mensagem <- erro(do.call(resolver_limites_idade_sim, setNames(list(valor), nome)))
    stopifnot(!is.null(mensagem))
  }
}
stopifnot(identical(erro(preparar_exportacao_sim(NULL, idade_min = -1)),
                    "idade_min deve ser um inteiro não negativo ou NULL."))
stopifnot(identical(erro(preparar_exportacao_sim(entrada, idade_min = 60, idade_max = 18)),
                    "idade_min não pode ser maior que idade_max."))
for (faixa in c("18-39", "40-59", "60+")) {
  for (limites in list(list(idade_min = 0), list(idade_max = 100), list(idade_min = 18, idade_max = 60))) {
    mensagem <- erro(do.call(preparar_exportacao_sim, c(list(dados_brutos = entrada, faixa = faixa), limites)))
    stopifnot(identical(mensagem, "Não combine --faixa específica com --idade_min ou --idade_max."))
  }
}
cat("OK: limites inválidos, mínimo maior que máximo e conflitos de faixa rejeitados\n")

# Vínculo exato com os códigos ANTES das substituições do processador oficial.
antes <- serialize(entrada, NULL)
processados <- processar_dados_sim(entrada)
ids <- as.character(seq_len(nrow(entrada)))
validacoes <- cbind(normalizar_idade_sim(entrada$IDADE), validar_data_obito_sim(entrada$DTOBITO))
stopifnot(
  identical(serialize(entrada, NULL), antes),
  identical(processados$.import_mds_registro_id, ids),
  identical(processados$CODESTAB, entrada$CODESTAB),
  identical(processados$idade_codigo_original, entrada$IDADE),
  identical(processados$idade_anos_completos,
            c(NA_integer_, 0L, 0L, 0L, 0L, 0L, NA_integer_, NA_integer_, 0L, 17L,
              18L, 39L, 40L, 59L, 60L, 100L, 101L, NA_integer_, NA_integer_,
              NA_integer_, NA_integer_, 18L, NA_integer_)),
  all(is.na(processados$IDADE[c(1L, 18L, 19L)])),
  identical(associar_validacoes_sim(processados[23:1, ], ids, validacoes), processados)
)
corrompidos <- list(
  perda = processados[-1L, ],
  duplicacao = processados[c(seq_len(23L), 1L), ],
  id_ausente = processados,
  id_desconhecido = processados,
  id_duplicado = processados,
  coluna_ausente = processados[, names(processados) != ".import_mds_registro_id"]
)
corrompidos$id_ausente$.import_mds_registro_id[1L] <- NA_character_
corrompidos$id_desconhecido$.import_mds_registro_id[1L] <- "inexistente"
corrompidos$id_duplicado$.import_mds_registro_id[2L] <- "1"
for (dados in corrompidos) {
  stopifnot(identical(erro(associar_validacoes_sim(dados, ids, validacoes)),
                      "Não foi possível garantir a correspondência entre registros brutos e processados do SIM."))
}
colisao <- entrada
colisao$.import_mds_registro_id <- ids
stopifnot(identical(erro(processar_dados_sim(colisao)),
                    "Dados brutos do SIM contêm colunas reservadas para associação de registros."))
cat("OK: associação por ID, restauração da ordem e interrupção em perdas/duplicações/corrupção\n")

duplicadas <- entrada[c(11L, 11L, 5L), ]
antes <- serialize(duplicadas, NULL)
saida <- preparar_exportacao_sim(duplicadas, idade_min = 18)
stopifnot(
  identical(saida$ESTABELECIMENTO, c("0000011", "0000011")),
  identical(serialize(duplicadas, NULL), antes)
)
invertida <- preparar_exportacao_sim(entrada[23:1, ], idade_min = 18)
stopifnot(identical(invertida$ESTABELECIMENTO, rev(resultados$apenas_minimo$ESTABELECIMENTO)))
cat("OK: duplicatas legítimas e ordem dos sobreviventes preservadas\n")

# A mesma garantia vale para data.table, sem mutação por referência da entrada.
tab <- data.table::as.data.table(entrada)
antes <- serialize(tab, NULL)
saida <- preparar_exportacao_sim(tab, idade_min = 18)
stopifnot(identical(serialize(tab, NULL), antes), identical(saida, resultados$apenas_minimo))

# Valida o prefixo REAL do orquestrador, excluindo fisicamente o nó de fetch.
# Usa commandArgs sintético e o despacho real; não executa coleta nem exportação.
codigo <- parse(file = "R/coletar_dados.R")
indice <- function(nome) which(vapply(codigo, function(expr) {
  is.call(expr) && identical(expr[[1L]], as.name("<-")) && identical(expr[[2L]], as.name(nome))
}, logical(1)))
indice_fetch <- indice("dados_brutos")
stopifnot(length(indice_fetch) == 1L)
prefixo <- codigo[2L:(indice_fetch - 1L)]
stopifnot(!"fetch_datasus" %in% all.names(prefixo))
despacho <- codigo[[which(vapply(codigo, function(expr) {
  is.call(expr) && identical(expr[[1L]], as.name("if")) &&
    identical(expr[[2L]], quote(grepl("^SIM", sistema)))
}, logical(1)))]]
simular_cli <- function(argumentos) {
  raiz <- getwd()
  diretorio <- tempfile("import-mds-cli-filtros-")
  dir.create(file.path(diretorio, "R", "sistemas"), recursive = TRUE)
  dir.create(file.path(diretorio, "R", "comum"), recursive = TRUE)
  on.exit({ setwd(raiz); unlink(diretorio, recursive = TRUE) }, add = TRUE)
  for (arquivo in c("R/comum/cid.R", "R/coletar_dados.R", "R/sistemas/sim.R", "R/comum/exportacao.R", "R/comum/auditoria.R")) {
    stopifnot(file.copy(file.path(raiz, arquivo), file.path(diretorio, arquivo)))
  }
  setwd(diretorio)
  ambiente <- new.env(parent = globalenv())
  ambiente$commandArgs <- function(trailingOnly = FALSE) {
    if (trailingOnly) argumentos else c("Rscript", paste0("--file=", file.path(diretorio, "R/coletar_dados.R")), argumentos)
  }
  ambiente$fetch_datasus <- function(...) stop("Acesso à rede proibido nos testes.")
  invisible(capture.output(eval(prefixo, envir = ambiente)))
  ambiente$dados_brutos <- entrada
  eval(despacho, envir = ambiente)
  ambiente
}
for (argumentos in list(
  c("--idade_min", "-1"), c("--idade_max", "18.5"), c("--idade_min"),
  c("--idade_min", "18", "--idade_max", "17"),
  c("--faixa", "18-39", "--idade_min", "18")
)) stopifnot(!is.null(erro(simular_cli(argumentos))))
cli <- simular_cli(c("--idade_min", "18", "--idade_max", "59", "--faixa", "ALL", "--uf", "ALL"))
stopifnot(
  identical(cli$limites_idade, list(idade_min = 18, idade_max = 59)),
  identical(cli$uf_param, "all"),
  identical(cli$dados_final$ESTABELECIMENTO, sprintf("%07d", c(11:14, 22L))),
  identical(simular_cli(character())$dados_final$ESTABELECIMENTO, sprintf("%07d", sem_limites)),
  identical(simular_cli(c("--faixa", "60+"))$dados_final$ESTABELECIMENTO, sprintf("%07d", 15:17))
)
cat("OK: argumentos R validados antes do fetch, encaminhados ao módulo e faixa legada compatível\n")
cat("PASSOU: 18 cenários de seleção, contagens, parâmetros inválidos, vínculo e orquestração sem downloads.\n")
