# Dependências de execução

Esta etapa acrescenta somente **jsonlite 2.0.0**, versão estável do
[CRAN](https://cran.r-project.org/web/packages/jsonlite/index.html), para ler e
gerar JSON. A versão efetivamente instalada e testada é 2.0.0, com R 4.3.3.
Nenhum pacote sugerido pelo jsonlite é necessário à infraestrutura.

Para reproduzir esta instalação em uma biblioteca do usuário, sem privilégios
administrativos nem atualização de outros pacotes:

```r
biblioteca <- Sys.getenv("R_LIBS_USER")
stopifnot(nzchar(biblioteca))
dir.create(biblioteca, recursive = TRUE, showWarnings = FALSE)
install.packages(
  "https://cran.r-project.org/src/contrib/jsonlite_2.0.0.tar.gz",
  lib = biblioteca, repos = NULL, type = "source", dependencies = FALSE
)
stopifnot(as.character(packageVersion("jsonlite")) == "2.0.0")
```

Se o arquivo deixar a área corrente do CRAN, o mesmo release fica no
[arquivo oficial](https://cran.r-project.org/src/contrib/Archive/jsonlite/).
A instalação a partir do fonte requer o compilador utilizado pelo R.
Não há instalação automática ao carregar os módulos ou executar testes.

A infraestrutura usa `/proc/sys/kernel/random/uuid` para gerar UUID v4 no Linux,
e exige `sha256sum` no PATH. Não usa `digest` nem `openssl`. A publicação exige
hard links no mesmo sistema de arquivos e falha explicitamente quando eles não
estão disponíveis. O projeto continua utilizando microdatasus 3.0.0; as versões
disponíveis de R, microdatasus, dplyr, data.table e jsonlite são registradas pelo
construtor de metadados. Python é informado pelo chamador ou registrado como
indisponível, sem inferir qual interpretador iniciou a execução.

Para os contratos, limitações e testes da infraestrutura, consulte
[docs/auditoria.md](docs/auditoria.md).
