# Dependências, instalação e diagnóstico

O procedimento para iniciantes está em [README.md](README.md). A configuração
não coleta microdados, não exige Git no fluxo ZIP e nunca executa sudo.

## Política de versões

| Componente | Política | Ambiente testado / alvo de instalação |
|---|---|---|
| Linux | UUID em /proc, hard links, GNU coreutils | Zorin OS 18.1 x86_64, base Ubuntu 24.04 |
| Bash | Scripts invocados com bash | 5.2.21 |
| Python | ≥3.8, somente biblioteca padrão | 3.12.3 |
| R / Rscript | ≥4.1.0 | 4.3.3 |
| microdatasus | Exatamente 3.0.0, API verificada sem coleta | 3.0.0 |
| jsonlite | Exatamente 2.0.0, contrato da auditoria | 2.0.0 |
| dplyr | ≥1.2.0, exigido pelo microdatasus fixado | 1.2.1 |
| lubridate | ≥1.9.0, política inicial do bootstrap | 1.9.5 |

O mínimo aceito não significa homologação de todas as combinações. R, dplyr ou
lubridate diferentes do ambiente testado produzem aviso quando satisfazem os
mínimos. Versões incompatíveis impedem a inicialização. Nenhum pacote é alterado
sem confirmação no configurar.sh.

Os quatro pacotes R diretamente utilizados são microdatasus, dplyr, lubridate e
jsonlite. data.table também é usado nos testes e identificado pela auditoria;
é dependência obrigatória do microdatasus. O leitor DBC é incorporado à versão
3.0.0: read.dbc não é necessário. Git é opcional para identificar commit/branch;
em cópias ZIP essa identificação pode ficar indisponível no relatório.

## Dependências transitivas e sistema

O [DESCRIPTION fixado](https://github.com/rfsaldanha/microdatasus/blob/7109ec2c42cf674ba453e0d7a20d2f464890b543/DESCRIPTION)
declara checkmate, cli, curl, data.table, dplyr (≥1.2.0), foreign, magrittr,
rlang, stringi, tibble, utils e zip. Dependências adicionais incluem vctrs,
pillar, tidyselect, glue, lifecycle, R6, generics e timechange. O bootstrap
percorre Depends/Imports/LinkingTo e suas restrições. Não instala Suggests,
testthat, remotes, devtools nem bibliotecas Python.

Versões transitivas observadas: data.table 1.18.6.1, curl 8.1.0, stringi 1.8.9,
zip 3.0.2, cli 3.6.6, rlang 1.3.0, tibble 3.3.1, vctrs 0.7.3 e timechange
0.4.0. Isso não é um lockfile: dependências transitivas pendentes são resolvidas
no CRAN para o R disponível, após consentimento. Os pins diretos não reproduzem
sozinhos todo o ambiente.

Vários pacotes compilam C/C++. São necessários make, GCC, G++ e os headers do R;
gfortran pode ser necessário à cadeia de compilação. curl exige libcurl ≥7.73
(libcurl4-openssl-dev no Ubuntu). stringi pode usar ICU do sistema (libicu-dev)
ou sua compilação própria. Certificados HTTPS e zoneinfo são necessários:
ca-certificates e tzdata. O README mostra um comando apt manual, nunca executado
pelos scripts. Em outros Linux, consulte os pacotes equivalentes.

A publicação exige sha256sum, hard links e UUID v4 do kernel em
/proc/sys/kernel/random/uuid. Não é acrescentado digest ou openssl como pacote R.
Windows e macOS nativos são recusados. O bootstrap não adiciona repositórios de
sistema nem atualiza R; distribuições antigas podem não fornecer R/libcurl adequados.

## Biblioteca privada e instalação

Novos pacotes ficam em `.biblioteca-R/<plataforma-R>/<major.minor>/`, ignorada
pelo Git. O caminho é acrescentado a R_LIBS somente nos processos dos scripts
e seus filhos, preservando as demais bibliotecas visíveis, inclusive a do usuário.
Não há escrita em .Rprofile, .Renviron, HOME ou biblioteca global. Sem pendências,
a biblioteca privada nem precisa ser criada.

Uma biblioteca compartilhada do usuário economizaria espaço, mas versões
conflitantes poderiam afetar outros projetos. A biblioteca privada permite
sombrear uma versão incompatível sem substituí-la globalmente. Pacotes já
compatíveis são reaproveitados. Binários compilados não devem ser copiados entre
sistemas como se fossem portáveis; a separação por plataforma/versão R não
constitui isolamento completo de ABI de bibliotecas do sistema.

Configurar.sh mostra os pacotes pendentes e pede s/sim. Enter, EOF ou outra
resposta recusam. Iniciar.sh e --check nunca instalam. O helper R também exige
o argumento interno explícito --confirmado para a ação instalar.

Novas instalações usam:

- microdatasus: fonte oficial no commit
  `7109ec2c42cf674ba453e0d7a20d2f464890b543`, via
  `https://codeload.github.com/rfsaldanha/microdatasus/tar.gz/7109ec2c42cf674ba453e0d7a20d2f464890b543`.
- jsonlite 2.0.0: `https://cloud.r-project.org/src/contrib/jsonlite_2.0.0.tar.gz`,
  com fallback a `https://cloud.r-project.org/src/contrib/Archive/jsonlite/jsonlite_2.0.0.tar.gz`.
- dplyr 1.2.1 e lubridate 1.9.5: releases nomeados do CRAN, com fallback a Archive.

O instalador confere Package/Version do DESCRIPTION, instala primeiro as
dependências obrigatórias e usa lib explícito e dependencies=FALSE. Requisitos
incompatíveis com o R ou com os pins produzem erro. Não há execução de script
remoto por pipe. As fontes usam HTTPS e origens fixas; não há checksum adicional
ou lock completo dessas bibliotecas R. O catálogo CID-10 local tem verificações
próprias de ZIP, índice e geração, independentes da instalação.

A instalação de desenvolvimento declara Repository: CRAN e versão 3.0.0, sem
RemoteSha. O comando original não é recuperável por esses metadados. Ela é
reaproveitada se satisfaz versão, dependências e teste de API; não é reinstalada
apenas por não registrar o commit GitHub.

## Diagnóstico e falhas

```bash
bash configurar.sh --check
bash configurar.sh
bash iniciar.sh
```

--check verifica programas, versões, arquivos, catálogo, UUID e permissões
informadas pelo sistema. Não acessa rede, instala, cria biblioteca ou ensaia
escrita. O modo normal testa escrita/hard links em diretório exclusivo e limpa
somente seus temporários. A exportação real continua reservando e verificando
seus destinos independentemente desse diagnóstico.

O helper usa status 10 para dependências instaláveis pendentes e 1 para erros.
Os scripts públicos retornam erro não zero e não anunciam sucesso após falha.
Após instalação, a verificação é repetida em outro processo R. Uma falha pode
deixar alguns pacotes já instalados na biblioteca privada; não há rollback ou
remoção automática de locks/pacotes. Avalie a causa antes de tentar de novo.
Não apague Dados/ para reparar bibliotecas.

Pacotes presentes que não carregam produzem erro sem reinstalação automática.
Caminhos com espaços e aspas são passados como argumentos; dois-pontos e quebras
de linha na raiz são recusados por incompatibilidade com o separador de R_LIBS.

## Evidências e limites

Verificações reais: Zorin OS 18.1, Python 3.12.3, R 4.3.3 e pacotes já instalados.
Uma cópia temporária sem .git e com espaços foi usada para configuração real,
menu Python e início real do R, com conflito de destino e bloqueio de coleta.
Nenhuma extração foi executada. Falhas e instalação assistida são simuladas nos
testes; isso não demonstra instalação limpa pela internet.

Nenhuma biblioteca precisou ser instalada nesta etapa. O Docker não estava
acessível para uma instalação limpa isolada. Ubuntu, Mint, outras versões do R,
Windows e macOS não foram homologados separadamente. Outros Linux recebem
diagnóstico de requisitos, sem instalador automático de programas do sistema.

Consulte [docs/auditoria.md](docs/auditoria.md), [docs/cid10.md](docs/cid10.md) e o
[manual de instalação do R](https://cran.r-project.org/doc/manuals/r-release/R-admin.html#Add_002don-packages).
