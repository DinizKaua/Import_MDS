# Construção de nomes e publicação CSV compartilhadas, sem coleta ou processamento.
construir_nome_csv <- function(sistema, uf, ano_inicio, ano_fim,
                               cid = "ALL", sexo = "ALL", raca = "ALL", faixa = "ALL",
                               idade_min = NULL, idade_max = NULL,
                               mes_inicio = NULL, mes_fim = NULL) {
  texto <- function(valor, permitir_vazio = FALSE) {
    if (length(valor) != 1L || is.na(valor) ||
        (!permitir_vazio && !nzchar(as.character(valor)))) {
      stop("Componente inválido para o nome CSV.")
    }
    as.character(valor)
  }
  # Componentes livres usam codificação reversível dos bytes, preservando
  # separadores e caminhos como texto, sem aliases por normalização/case folding.
  componente <- function(valor, completo = FALSE) {
    bytes <- as.integer(charToRaw(enc2utf8(texto(valor, permitir_vazio = TRUE))))
    seguros <- as.integer(charToRaw("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-+"))
    paste0(vapply(bytes, function(b) {
      if (!completo && b %in% seguros) rawToChar(as.raw(b)) else sprintf("%%%02X", b)
    }, character(1)), collapse = "")
  }
  idade <- function(valor) {
    if (!is.numeric(valor) || length(valor) != 1L || is.na(valor) ||
        !is.finite(valor) || valor < 0 || valor != floor(valor) || valor > 2^53 - 1) {
      stop("Os limites usados no nome devem ser inteiros não negativos já validados.")
    }
    format(valor, scientific = FALSE, trim = TRUE)
  }
  for (valor in list(sistema, uf, ano_inicio, ano_fim)) texto(valor)
  for (valor in list(cid, sexo, raca, faixa)) texto(valor, permitir_vazio = TRUE)
  nome <- paste0(
    "dados_", componente(sistema), "_", if (uf == "all") "BR" else componente(uf),
    "_", componente(ano_inicio), "_", componente(ano_fim)
  )
  # SIM continua anual; os meses identificam partições apenas nos sistemas SIH.
  if (startsWith(sistema, "SIH-")) {
    nome <- paste0(nome, "_meses_", componente(mes_inicio), "-", componente(mes_fim))
  }
  # O formato legado é inequívoco para os domínios usuais. Entradas atípicas
  # continuam com a mesma semântica de filtro, mas recebem campos identificados.
  rotulos <- c("Masculino", "Feminino", "Branca", "Preta", "Parda", "Amarela", "Indigena", "Indígena")
  legado <- (cid == "ALL" || (grepl("\\A[A-Z][A-Z0-9]*\\z", cid, perl = TRUE) &&
                              !cid %in% toupper(rotulos))) &&
    sexo %in% c("ALL", "Masculino", "Feminino") &&
    raca %in% c("ALL", "Branca", "Preta", "Parda", "Amarela", "Indigena", "Indígena") &&
    faixa %in% c("ALL", "18-39", "40-59", "60+")
  filtros <- list(cid = cid, sexo = sexo, raca = raca, faixa = faixa)
  for (chave in names(filtros)) {
    valor <- filtros[[chave]]
    if (legado) {
      if (valor != "ALL") nome <- paste0(nome, "_", valor)
    } else {
      nome <- paste0(nome, "__", chave, "-", componente(valor, completo = TRUE))
    }
  }
  if (!is.null(idade_min) && !is.null(idade_max)) {
    nome <- paste0(nome, "_idade_", idade(idade_min), "-", idade(idade_max))
  } else if (!is.null(idade_min)) {
    nome <- paste0(nome, "_idade_", idade(idade_min), "mais")
  } else if (!is.null(idade_max)) {
    nome <- paste0(nome, "_idade_ate", idade(idade_max))
  }
  paste0(nome, ".csv")
}

verificar_destino_csv <- function(destino) {
  if (!is.character(destino) || length(destino) != 1L || is.na(destino) || !nzchar(destino)) {
    stop("O destino CSV deve ser um caminho não vazio.")
  }
  destino <- path.expand(destino)
  diretorio <- normalizePath(dirname(destino), mustWork = TRUE)
  if (!dir.exists(diretorio)) stop("O diretório de destino não existe.")
  destino <- file.path(diretorio, basename(destino))
  # file.exists segue links; Sys.readlink detecta também links simbólicos quebrados.
  link <- Sys.readlink(destino)
  if (file.exists(destino) || (!is.na(link) && nzchar(link))) {
    stop("Destino CSV já existe; nenhum arquivo foi substituído: ", destino)
  }
  invisible(destino)
}

.escrever_csv_padrao <- function(dados, conexao) {
  utils::write.csv(dados, file = conexao, row.names = FALSE)
}

exportar_csv_seguro <- function(dados, destino) {
  destino <- verificar_destino_csv(destino)
  temporario <- tempfile(".import-mds-csv-", tmpdir = dirname(destino), fileext = ".tmp")
  # A criação exclusiva evita truncar um temporário que pertença a outra execução.
  conexao <- file(temporario, open = "wx")
  aberta <- TRUE
  on.exit({
    if (aberta) try(close(conexao), silent = TRUE)
    if (unlink(temporario) != 0L) warning("Não foi possível limpar o temporário: ", temporario)
  }, add = TRUE)
  withCallingHandlers({
    .escrever_csv_padrao(dados, conexao)
    close(conexao)
    aberta <- FALSE
  }, warning = function(w) {
    stop("Falha na escrita do CSV: ", conditionMessage(w), call. = FALSE)
  })
  # file.link cria uma nova entrada para o arquivo COMPLETO, sem substituir um
  # destino existente. Não há fallback para rename/cópia que possa sobrescrever.
  if (!isTRUE(suppressWarnings(file.link(temporario, destino)))) {
    verificar_destino_csv(destino)
    stop("Publicação CSV sem sobrescrita indisponível; o sistema de arquivos deve suportar hard links: ", destino)
  }
  invisible(destino)
}
