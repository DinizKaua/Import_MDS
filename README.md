# Import_MDS

O Import_MDS baixa e filtra microdados do DATASUS. Você faz as escolhas em um
menu no terminal; o Python abre esse menu e o R realiza a coleta e o processamento.
Os resultados são CSVs acompanhados de auditoria, com proteção contra sobrescrita.

**Esta versão trabalha com óbitos do SIM-DO. SIH-RD ainda não está funcional.**
Apesar de aparecer no menu atual, a opção de internações não deve ser utilizada.

## Funcionalidades

- Seleção de UF e período da consulta.
- Idades mínima e máxima opcionais, em anos completos, com limites inclusivos.
- Filtros de sexo e raça/cor, ou ausência desses filtros.
- Prefixo CID-10 (`I21`), intervalo de categorias (`E10-E14`, `I10-I15`) ou `ALL`.
- CSV principal com 14 colunas, auditoria de naturalidade e relatório JSON.
- Diretório próprio por extração, sem sobrescrita automática.

## Requisitos

O suporte inicial é para **Linux**, com orientações para Ubuntu, Linux Mint e
Zorin OS. O fluxo foi efetivamente testado em **Zorin OS 18.1, x86_64**, com
Python **3.12.3**, Bash **5.2.21**, R **4.3.3** e microdatasus **3.0.0**.
Ubuntu e Mint são alvos compatíveis, mas não foram testados separadamente nesta
etapa. Windows e macOS nativos não são suportados pelos scripts.

Você precisa ter Python ≥3.8, R ≥4.1 e ferramentas básicas do Linux. Não é
necessário conhecer R, instalar bibliotecas Python, usar `pip` ou ter Git no
procedimento com ZIP. As bibliotecas R podem ser instaladas pela configuração,
**somente depois da sua confirmação**.

Quando faltar um programa do sistema, a configuração mostrará uma orientação.
Ela não executa `sudo` nem instala programas do sistema automaticamente. Para
Ubuntu/Mint/Zorin, um administrador pode revisar e executar manualmente:

```bash
sudo apt update
sudo apt install python3 r-base r-base-dev coreutils ca-certificates tzdata build-essential gfortran libcurl4-openssl-dev libicu-dev pkg-config
```

A senha solicitada por `sudo` é a do computador. Você nunca precisa fornecer
senha ou token do GitHub para baixar este projeto público. Em outras distribuições,
os nomes dos pacotes podem variar. Versões antigas podem não fornecer requisitos
suficientemente novos; consulte [DEPENDENCIAS.md](DEPENDENCIAS.md).

Internet é necessária para instalar bibliotecas ausentes e consultar o DATASUS.
As verificações e a referência CID-10 funcionam sem rede. O disco de saída precisa
permitir hard links, usados pela publicação segura.

## 1. Baixar o projeto

### Opção A — ZIP, para iniciantes

1. Abra [o repositório](https://github.com/DinizKaua/Import_MDS).
2. Confirme que a branch selecionada é `main`.
3. Clique em **Code → Download ZIP**.
4. Abra o ZIP no gerenciador de arquivos e escolha **Extrair**.
5. Coloque a pasta extraída em uma pasta pessoal onde você possa gravar arquivos.

Entre na pasta que contém `app.py`, `configurar.sh`, `iniciar.sh` e `R/`.
Não execute de dentro do ZIP nem baixe apenas um script.

### Opção B — Git, para quem já utiliza

```bash
git clone https://github.com/DinizKaua/Import_MDS.git
cd Import_MDS
```

## 2. Abrir o terminal na pasta

No gerenciador de arquivos, entre na pasta extraída. Clique com o botão direito
em uma área vazia e procure **Abrir no terminal** ou **Abrir terminal aqui**.
O nome varia conforme o sistema. A pasta correta contém `configurar.sh`.
Digite os comandos abaixo e pressione Enter após cada um.

## 3. Configurar

```bash
bash configurar.sh
```

A configuração verifica programas, arquivos, referência CID-10, permissão de
escrita, hard links e bibliotecas R. Um pequeno teste de escrita é criado e
removido pela própria execução, sem alterar resultados existentes.

Se faltarem bibliotecas R ou houver versões incompatíveis, ela explicará quais
precisam ser instaladas e perguntará se você autoriza. Digite `s` e Enter para
autorizar; Enter ou `n` recusam. A compilação pode demorar e mostrar mensagens
técnicas: espere o comando terminar.

As novas bibliotecas ficam em `.biblioteca-R/`, dentro do projeto, separadas por
plataforma e versão do R. Pacotes já compatíveis são reaproveitados. A biblioteca
global não é alterada. Você pode repetir a configuração sem reinstalar pacotes
corretos. Não é preciso editar arquivos de configuração.

Uma mensagem **ERRO** exige resolver o requisito antes de continuar. **AVISO**
informa uma limitação. Ao terminar com sucesso, será mostrado o próximo comando.

Para somente diagnosticar, sem instalar nem criar arquivos de teste:

```bash
bash configurar.sh --check
```

Nesse modo, escrita e hard links não são ensaiados de fato.

## 4. Iniciar

```bash
bash iniciar.sh
```

O inicializador verifica o ambiente e abre o menu existente. Ele não instala
pacotes nem consulta o DATASUS por conta própria. Mantenha o terminal aberto.
Se faltar algo, execute `bash configurar.sh`.

Os scripts também aceitam execução por caminho completo a partir de outra pasta.
Caminhos com espaços são aceitos quando colocados entre aspas. Evite dois-pontos
ou quebras de linha no nome da pasta: não são compatíveis com R_LIBS neste fluxo.

## 5. Responder ao menu

1. **Tipo de dado:** escolha `1`, óbitos SIM-DO. Não use SIH-RD nesta versão.
2. **Período:** escolha `1`, anual, e informe os anos inicial e final. Para um
   único ano, repita o ano nas duas perguntas. O menu também pergunta por meses,
   mas SIM-DO usa arquivos anuais; isso não implementa um filtro mensal adicional
   pela data de óbito.
3. **UF:** informe uma sigla como `MA`, ou `ALL` para consultar todas as UFs.
4. **Sexo:** `1` masculino, `2` feminino ou `3` sem filtro.
5. **Raça/cor:** selecione uma opção ou `6` sem filtro. Veja a limitação legada
   da opção Indígena ao final deste documento.
6. **Idade mínima/máxima:** inteiros não negativos. Enter deixa cada limite
   ausente. Ambos vazios significam ausência de filtro etário, sem mínimo
   implícito de 18 anos. Idades desconhecidas/inválidas não satisfazem limites ativos.
7. **CID:** prefixo (`I21`), intervalo (`E10-E14`) ou `ALL`. Enter equivale a
   `ALL`. Intervalos exigem categorias completas de três caracteres, mesma letra,
   limites válidos e hífen único. `I14`, por exemplo, não é categoria atribuída.

Nos prefixos, `I210` e `I21.0` continuam diferentes. Nos intervalos, formas
compactas e pontuadas válidas são reconhecidas. CID é filtrado depois da coleta;
uma consulta específica ainda pode baixar todos os registros das partições.

### Exemplo ilustrativo: diabetes no Maranhão em 2014

| Pergunta | Resposta |
|---|---|
| Tipo de dado | `1` — SIM-DO |
| Período | `1` — anual |
| Ano inicial / final | `2014` / `2014` |
| UF | `MA` |
| Sexo | `3` — não filtrar |
| Raça/cor | `6` — não filtrar |
| Idade mínima | `18` |
| Idade máxima | Enter |
| CID | `E10-E14` |

Este exemplo apenas explica as escolhas. Configurar o ambiente não faz essa
consulta. Ao concluir as respostas do menu, o programa inicia a coleta.
Ctrl+C interrompe o comando, podendo deixar uma pasta incompleta; preserve-a
para diagnóstico antes de tentar novamente.

## Onde encontrar os resultados

Eles ficam em `Dados/` na pasta do projeto, mesmo quando iniciado de outra pasta:

```text
Dados/
└── <nome-da-extracao>/
    ├── <nome-da-extracao>.csv
    └── logs/
        ├── <nome-da-extracao>_auditoria_naturalidade.csv
        └── <nome-da-extracao>_relatorio.json
```

No exemplo, o nome-base é `dados_SIM-DO_MA_2014_2014_cid-intervalo-E10-E14_idade_18mais`.

- **Principal:** os registros selecionados, com as 14 colunas epidemiológicas.
- **Auditoria de naturalidade:** exceções e posições no principal. Pode ter apenas
  cabeçalho quando não há exceções, sem indicar falha.
- **JSON:** parâmetros, versões disponíveis, contagens, tamanhos e hashes dos CSVs.
  Ele é publicado por último.

A conclusão exige sucesso da verificação dos três artefatos. Um CSV isolado ou
a simples existência do JSON não bastam. [A documentação técnica](docs/auditoria.md)
explica como o consumidor valida o conjunto e seus hashes. Arquivos gerados são
ignorados pelo Git: isso **não é backup**. Preserve cópias dos resultados importantes
em local seguro. Não publique microdados individuais em mensagens de suporte.

## Execuções repetidas e pastas incompletas

Se a pasta daquela extração já existir, o programa interrompe **antes da coleta**.
Ele não mistura execuções, não sobrescreve resultados e não recupera pastas
incompletas automaticamente.

Não exclua uma pasta apenas para repetir a consulta. Preserve os arquivos e o
relatório. Se outra execução for necessária, planeje-a em outra cópia do projeto
ou após organização manual segura dos resultados anteriores. Pastas incompletas
também são recusadas e não devem ser tratadas como resultados concluídos.

## Solução de problemas

| Situação | Orientação |
|---|---|
| Python não encontrado | Instale Python 3 pelo gerenciador do sistema e repita a configuração. |
| R ou Rscript não encontrado | Instale R. RStudio sozinho não substitui o R. Reabra o terminal se necessário. |
| Pacote R ausente/incompatível | Execute `bash configurar.sh`, leia a lista e autorize somente se concordar. |
| Falha ao instalar bibliotecas | Confira os erros de compilação e os requisitos em [DEPENDENCIAS.md](DEPENDENCIAS.md). Não use `sudo R`. |
| Pacote instalado não carrega | Pode haver incompatibilidade do sistema ou de uma instalação anterior. Peça ajuda com a mensagem técnica; não atualize tudo indiscriminadamente. |
| Sem permissão | Use uma pasta pessoal com escrita. Não execute como administrador para contornar isso. |
| Hard links indisponíveis | Use um sistema de arquivos Linux que os suporte. Não há fallback com sobrescrita. |
| Falha de internet na configuração | Verifique conexão/certificados. Somente bibliotecas R são baixadas nessa fase. |
| DATASUS indisponível | Preserve o diagnóstico e os artefatos incompletos. Falha de coleta não significa zero eventos. Avalie serviço e destino antes de outra tentativa. |
| Intervalo CID inválido | Confira limites, mesma letra e hífen único. O menu solicitará nova entrada. |
| Diretório já existe | Preserve a execução anterior; siga a seção sobre consultas repetidas. |
| CSV só com cabeçalho | Confira filtros, contagens e referência no JSON. Não conclua ausência de eventos sem investigar. |
| Falha na auditoria/publicação | Não utilize arquivos parciais como concluídos. Preserve-os e consulte [docs/auditoria.md](docs/auditoria.md). |
| Projeto incompleto/referência inválida | Extraia novamente o ZIP completo em outra pasta, preservando resultados anteriores. |

## Limitações

- Integridade técnica não comprova cobertura DATASUS ou qualidade epidemiológica.
  A cobertura registrada permanece `nao_verificada`.
- UF seleciona arquivos pelo microdatasus. Não há filtro adicional por município
  de ocorrência; não interprete `MA` automaticamente como todos os óbitos ocorridos
  no estado.
- Período solicitado e ano do evento não são necessariamente equivalentes. Não há
  filtro adicional por período de ocorrência.
- A referência OMS é fixa, sem tabela de vigência histórica do SIM. Diabetes
  E10–E14 foi corrigido; outros modificadores compartilhados ainda não são
  expandidos. Consulte [docs/cid10.md](docs/cid10.md).
- A opção legada de raça/cor **Indígena** envia `Indigena`, enquanto o pacote
  instalado traduz `Indígena`; ela pode produzir resultado vazio. Esta etapa
  de instalação não altera esse filtro.
- Datas de óbito ausentes/inválidas são preservadas como NA. O nascimento ainda
  é convertido pelo pacote. Os microdados podem conter ausências e divergências
  entre idade, datas e outros campos.
- As 14 colunas não identificam um óbito de maneira única. Não elimine linhas
  iguais automaticamente. Planeje a interpretação de NA e códigos textuais ao
  importar para banco de dados.
- Bibliotecas R compiladas não são portáveis entre todos os computadores.
  Use uma cópia nova do projeto e configure novamente ao mudar de sistema;
  não distribua `.biblioteca-R/` como parte do projeto.

## Documentação e referências

- [Dependências e diagnóstico técnico](DEPENDENCIAS.md).
- [Auditoria, arquivos e publicação segura](docs/auditoria.md).
- [Referência CID-10 e limitações dos filtros](docs/cid10.md).
- [DATASUS — Ministério da Saúde](https://datasus.saude.gov.br/).
- [microdatasus — repositório oficial](https://github.com/rfsaldanha/microdatasus).
- [Fonte fixada para novas instalações](https://github.com/rfsaldanha/microdatasus/tree/7109ec2c42cf674ba453e0d7a20d2f464890b543).
- [OMS — CID-10 2019](https://icd.who.int/browse10/2019/en/).
