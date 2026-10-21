# Infraestrutura de auditoria persistente — esquemas 1.0.0 e 1.1.0

O fluxo SIM de `R/coletar_dados.R` utiliza esta infraestrutura para produzir
principal, auxiliar e relatório final em uma única execução. Os módulos continuam
reutilizáveis: carregar `R/comum/exportacao.R` e depois `R/comum/auditoria.R` no
mesmo ambiente. O processamento epidemiológico permanece em `R/sistemas/sim.R`.

## Organização das novas saídas

O orquestrador resolve a raiz pela localização real de `R/coletar_dados.R`,
inclusive via `Rscript`, `source()` ou `sys.source()`. Não usa o diretório atual
como raiz implícita nem grava caminhos específicos do computador no relatório.
A interface Python passa o caminho absoluto do script, calculado a partir de
`app.py`; pode ser iniciada de outra pasta por `python3 /caminho/Import_MDS/app.py`.

O nome principal continua sendo construído por `construir_nome_csv()`. Para
`dados_SIM-DO_MA_2014_2014_I21_idade_18mais.csv`, a disposição de novas extrações é:

```text
Dados/
├── .gitkeep
└── dados_SIM-DO_MA_2014_2014_I21_idade_18mais/
    ├── dados_SIM-DO_MA_2014_2014_I21_idade_18mais.csv
    └── logs/
        ├── dados_SIM-DO_MA_2014_2014_I21_idade_18mais_auditoria_naturalidade.csv
        └── dados_SIM-DO_MA_2014_2014_I21_idade_18mais_relatorio.json
```

O exemplo descreve a nomenclatura; os resultados históricos não são migrados.
Cada conjunto continua com somente três artefatos. `logs/` contém o auxiliar de
naturalidade e o marcador JSON, sem um novo arquivo de log de console.
`Dados/.gitkeep` mantém a pasta no clone. As extrações em `Dados/` são ignoradas
pelo Git, assim como relatórios de saída com padrão `dados_*_relatorio.json` na
raiz; os demais arquivos JSON não são ignorados indiscriminadamente.

Antes da coleta, `preparar_diretorio_extracao()` cria `Dados/` se necessário e
reserva a pasta da extração com `mkdir` exclusivo. Pasta já existente, mesmo
vazia, arquivo ou link no destino provocam erro, sem reutilização ou mistura.
Somente o vencedor da reserva pode avançar; os destinos dos três arquivos são
conferidos em seguida, ainda antes de `fetch_datasus()`. Links simbólicos no
diretório `Dados/`, na pasta da extração ou em `logs/` não são aceitos.

## Base dos caminhos e compatibilidade

No esquema histórico `1.0.0`, `arquivos.*.nome` contém somente nomes simples e
os CSVs são resolvidos ao lado do JSON, como antes. Nenhum relatório histórico
precisa ser reescrito ou movido.

No esquema `1.1.0`, a base de resolução é **o diretório que contém o JSON**:
`publicacao.base_caminhos = "diretorio_relatorio"` e
`publicacao.organizacao = "extracao_logs"`. O principal é referenciado por
`../<nome-base>.csv`, e o auxiliar por `<nome-base>_auditoria_naturalidade.csv`.
Os nomes físicos não mudam e não há caminhos absolutos no contrato de artefatos.

O consumidor aceita apenas essa subida única do principal, sem outros componentes
de caminho. O auxiliar deve ser um nome simples derivado do principal; o JSON
deve estar em `logs/` na pasta com o nome-base da extração. Caminhos absolutos,
subidas adicionais, subpastas arbitrárias e links para artefatos externos são
rejeitados. O conjunto inteiro pode ser transportado preservando essa estrutura.

A mudança de base é incompatível com o contrato de resolução anterior, por isso
novas saídas organizadas usam `1.1.0`. Consumidores que aceitam apenas `1.0.0`
precisam ser atualizados. O consumidor atualizado suporta as duas versões;
as demais validações de contagens, posições, bytes, SHA-256 e 14 colunas permanecem.

## Integração SIM

O orquestrador verifica os três destinos antes de sua única chamada a
`fetch_datasus()`, mantendo os mesmos parâmetros de coleta. Registra anos e meses
solicitados, UF solicitada e efetiva, `stop_on_error`, sexo, raça/cor, prefixo CID
e limites etários efetivos. `faixa_legada_informada` conserva o argumento legado;
os limites resolvidos indicam seu efeito real.
O CID também aceita intervalos inclusivos de categorias segundo a referência
local descrita em [cid10.md](cid10.md). Prefixos continuam literais. O objeto
opcional `metadados.consulta.filtros.cid_intervalo` registra modalidade, limites,
referência e categorias elegíveis, sem alterar o campo textual `cid`, as contagens
ou a versão JSON 1.1.0. A validação antecede a reserva da pasta e a coleta.
Os meses não passam a ser um filtro
de ocorrência no SIM. O início registrado antecede a coleta, após a validação
dos parâmetros e dos destinos. Python fica explicitamente indisponível: a
integração não recebe uma versão verificável do chamador. A identificação Git é
consultada na raiz do projeto, incluindo a indicação de alterações locais.

Os atributos `contagens_etarias`, `contagens_datas` e `contagens_naturalidade`
são passados diretamente como grupos `etarias`, `datas` e `naturalidade`, sem
recalcular categorias a partir das 14 colunas. Categorias anteriores aos filtros
mantêm esse significado; não descrevem automaticamente a população final.

O atributo completo `auditoria_naturalidade` deve ter uma linha para cada registro
final, posições exatamente de 1 a N, identificadores internos de texto únicos e
não ausentes e descrições correspondentes à coluna `ESTADO_NATURALIDADE`.
Ausência ou corrupção desse vínculo provoca erro antes da publicação.
O auxiliar seleciona situações diferentes de `inequivoca` OU motivos diferentes
de `correspondencia_unica`, incluindo ressalvas de uma tradução inequívoca.
As posições já existentes são mantidas, sem renumeração após essa seleção.
Os identificadores internos não são exportados. Um auxiliar sem exceções mantém
as cinco colunas e zero registros.

Depois da publicação, o orquestrador chama `verificar_resultado_auditado()` com
o UUID esperado. Somente então anuncia os três arquivos. Se essa conferência
final falhar, propaga erro sem anunciar sucesso nem excluir definitivos. Como o
JSON já pode existir nessa etapa, consumidores devem sempre validá-lo novamente.

## Contratos

- `preparar_metadados_auditoria(sistema, uf, periodo, parametros, filtros,
  inicio, python, import_mds, id_execucao)` cria metadados explícitos. Somente
  `sistema` é obrigatório; ausências são `null` no JSON e relacionadas em
  `informacoes_indisponiveis`. `inicio` aceita POSIXct ou NULL e é convertido
  para UTC. O identificador padrão é um UUID v4 do kernel Linux.
- `identificar_import_mds(diretorio)` consulta Git somente para leitura e
  retorna commit, branch e indicação de alterações locais, ou NULL. O chamador
  fornece esse resultado ao construtor; não há inferência sobre qual projeto
  um diretório de trabalho arbitrário representa.
- `preparar_diretorio_extracao(raiz_projeto, nome_csv)` reserva exclusivamente
  a pasta da extração e cria `logs/`. Retorna `diretorio`, `logs` e `principal`.
- `destinos_resultado_auditado(destino_csv, diretorio_logs = NULL)` determina e
  verifica TODOS os destinos. Não cria arquivos. Sem `diretorio_logs`, preserva
  o contrato anterior; com ele, exige a organização descrita acima.
- `validar_contagens_auditoria(contagens, total_final)` recebe listas opcionais
  `etarias`, `datas`, `naturalidade`, com os contratos atuais dos atributos
  `contagens_*` do SIM. Cada grupo fornecido precisa estar completo. Reconcilia
  categorias, exclusões, totais finais e etapas comuns. Grupos não fornecidos
  ficam explicitamente nulos no relatório. Não infere categorias dos 14 campos.
- `validar_auditoria_naturalidade(auditoria, total_principal)` valida o esquema,
  textos/classificações e posições inteiras únicas entre 1 e o total final.
- `publicar_resultado_auditado(dados, auditoria, destino_csv, metadados,
  contagens, colunas_principal, diretorio_logs = NULL)` prepara, verifica e publica
  o conjunto. Sem `diretorio_logs`, mantém a disposição histórica e o esquema
  `1.0.0`; com ele, utiliza a estrutura extração/logs e `1.1.0`.
  Retorna invisivelmente o relatório somente após a publicação do JSON. Falhas
  são erros R; o chamador não deve capturá-los para anunciar sucesso.
- `verificar_resultado_auditado(caminho_json, id_execucao = NULL)` é a porta de
  entrada do consumidor: valida versão/estrutura, identidade, contagens,
  caminhos relativos, esquema, tamanhos, hashes, registros CSV e posições.
  Um JSON existente, sozinho, não comprova que o resultado está íntegro.
- `sha256_arquivo(caminho)` executa `sha256sum`, exige saída válida/código zero
  e retorna 64 dígitos hexadecimais; indisponibilidade ou falha são erros.

O esquema principal padrão contém os 14 campos atuais do SIM, na ordem atual.
O argumento explícito `colunas_principal` permite reutilização futura com outro
esquema; relatórios SIM-DO exigem sempre as 14 colunas legadas. Nenhuma função
realiza processamento epidemiológico, seleção de exceções ou junção de registros.
`data.frame` e `data.table` recebidos permanecem inalterados.

O contrato anterior `exportar_csv_seguro(dados, destino)` permanece disponível.
Ele e o novo módulo compartilham `preparar_arquivo_seguro(destino, escrever)`,
`publicar_arquivo_seguro(temporario, destino)` e
`limpar_temporarios_exportacao(caminhos)`. A preparação entrega um temporário
exclusivo já fechado; quem o recebe é responsável por sua limpeza.

## Arquivos e vínculo por posição

Para `consulta.csv`, os destinos são:

1. `consulta.csv`: exatamente `write.csv(dados, row.names = FALSE)`, incluindo
   ordem, valores ausentes e serialização existentes. Atributos não viram campos.
2. `consulta_auditoria_naturalidade.csv`: campos, nesta ordem,
   `posicao_registro,codigo_original,situacao,motivo,descricao`. Mesmo sem
   exceções, tem cabeçalho e zero registros.
3. `consulta_relatorio.json`: marcador final do conjunto, publicado por último.

O chamador constrói o auxiliar a partir do atributo `auditoria_naturalidade`
DEPOIS de todos os filtros, mapear `posicao_csv` para `posicao_registro`, selecionar
as exceções e os outros quatro campos correspondentes. A integração não modifica
o processador. O identificador temporário interno não vai
para nenhum CSV. Posição 1 é o primeiro registro de dados, excluindo o cabeçalho;
campos com quebras de linha não alteram essa definição. Duplicatas legítimas em
posições distintas são mantidas. Não há deduplicação.

Situações suportadas: `ambigua`, `sem_correspondencia`, `ausente`; uma exceção
`inequivoca` também pode ser informada pelo processador, por exemplo para auditar
repetições idênticas da tabela auxiliar. As situações diferentes de `inequivoca`
mantêm descrição NA, com uma exceção explícita de apresentação do SIM: código
exato `44`, situação `ambigua`, motivo `codigo_corresponde_a_dois_paises_distintos`
e descrição `CAMBOJA / LAOS`. Essa descrição não determina um país: o caso segue
contabilizado como ambíguo e permanece no auxiliar. O leitor e o validador admitem
somente essa combinação, sem liberar descrições arbitrárias para ambiguidades.

Os códigos exatos `73` e `81` recebem `IRLANDA` e `ILHAS FALKLAND (MALVINAS)`,
respectivamente, com situação `inequivoca` e motivo
`equivalencia_nomenclatura_geografica`. Também são exportados no auxiliar como
padronizações rastreáveis, sem contar como ambiguidades geográficas. São regras
de apresentação aprovadas do projeto; a referência instalada não é alterada.
Não há conversão numérica, remoção de espaços ou de zeros dos códigos. O esquema
de campos do auxiliar permanece igual; essa padronização não muda, por si só,
a versão JSON. A disposição física dos artefatos define `1.0.0` ou `1.1.0`.
Consumidores com
o validador anterior precisam ser atualizados para aceitar a descrição do caso 44;
os artefatos históricos continuam aceitos pelo validador atualizado.

Os campos de texto são lidos sem conversão automática de tipos e sem remover
espaços. A serialização CSV padrão escreve ausências como NA. Para distinguir
o código originalmente ausente do texto literal `"NA"`, o contrato exige:

- `codigo_original = NA_character_`: `situacao = "ausente"` e
  `motivo = "codigo_ausente_na"`;
- código vazio ou composto apenas por espaços: manter o texto exato e motivos
  `codigo_ausente_vazio` ou `codigo_ausente_espacos`;
- código literal `"NA"`: permanece texto, com a classificação do processador,
  nunca `codigo_ausente_na`.

Use `ler_auditoria_naturalidade(caminho, total_principal)` para reconstruir
essas distinções. Na situação inequívoca uma descrição literal `"NA"` também
é preservada como texto. Não use a inferência padrão de `read.csv` para códigos.
Não são incluídos identificadores pessoais. Posições e códigos continuam sendo
informações vinculáveis; controle o acesso ao conjunto conforme o uso científico.

## Relatório JSON

`versao_esquema` é `"1.1.0"` nas novas extrações organizadas, ou `"1.0.0"` no
contrato anterior de publicação no mesmo diretório. `id_execucao` e
`metadados.id_execucao` coincidem.
`metadados` contém consulta solicitada, UF, período, parâmetros/filtros efetivos,
início da execução (quando informado) e versões. `horarios` registra preparação
e conferência em UTC; a conferência antecede a publicação do marcador, não é
uma garantia de durabilidade nem um horário posterior à publicação.

`contagens` preserva grupos e nomes de etapas recebidos; `arquivos.principal`
e `arquivos.naturalidade` contêm nome relativo, número de registros, tamanho em
bytes, SHA-256 e colunas na ordem. Não há checksum do próprio JSON.
`verificacoes` informa o sucesso das verificações de arquivos, das contagens
fornecidas e das posições. Consulte também `informacoes_indisponiveis`:
verificações aprovadas não significam que todos os grupos foram fornecidos.

`publicacao.situacao = "concluida"` só é observável no destino final após as
conferências. `cobertura_datasus` permanece `"nao_verificada"` mesmo com sucesso.
`limitacoes` explicita que checksum não comprova qualidade epidemiológica,
autenticidade ou cobertura dos arquivos de origem. Metadados são fornecidos
pelo chamador, sem reconstruir informações perdidas no CSV principal.

## Protocolo e falhas

Antes da escrita, todos os destinos são verificados, incluindo arquivos,
diretórios e links simbólicos quebrados. Os três conteúdos são preparados em
temporários exclusivos no diretório de destino. Esquemas e contagens são
conferidos por parsing CSV (nunca por quantidade de quebras de linha); posições,
texto do auxiliar, tamanhos e SHA-256 também são verificados. O JSON preparado
é relido e validado antes de qualquer publicação.

Publicação: principal → auxiliar → conferência dos CSVs publicados → JSON final.
O horário de conferência é escrito em um novo temporário JSON exclusivo e
validado. Cada publicação usa hard link sem substituição, sem fallback de
rename/cópia. Conflitos posteriores à verificação inicial continuam protegidos.
Na organização nova, execuções com o mesmo nome disputam primeiro a reserva da
pasta, antes da coleta. A proteção por hard link continua ativa para conflitos
de arquivo surgidos depois dessa reserva. No contrato legado, execuções disputam
primeiro o principal; a que perder não publica seus arquivos seguintes.

Não há atomicidade entre arquivos. Se ocorrer erro antes da publicação do JSON,
nenhum marcador próprio é publicado; CSVs definitivos já publicados ficam preservados. Um marcador
conflitante criado por outra execução não é removido nem confundido com sucesso.
Somente temporários explicitamente criados pela execução são limpos. Não há
remoção automática de definitivos, retomada nem recuperação automática. Uma nova
tentativa com os mesmos destinos ocupados falha. Conjuntos sem JSON validado são
incompletos e exigem decisão manual antes do reaproveitamento.

Falhas de criação de diretórios também são propagadas. Não removemos diretórios
automaticamente, nem mesmo os recém-criados que ficaram vazios. Se a coleta ou a
publicação falhar, a pasta permanece reservada e uma nova execução com o mesmo
nome será recusada. Inspecione e preserve o conjunto incompleto antes de decidir
manualmente seu destino; não basta criar ou editar um JSON para declará-lo válido.

Para identificar uma extração concluída, carregue os dois módulos compartilhados
no mesmo ambiente e execute
`verificar_resultado_auditado("Dados/<extracao>/logs/<extracao>_relatorio.json")`.
Esse caminho do exemplo é relativo à pasta de trabalho do consumidor; depois de
localizado o JSON, seus CSVs são resolvidos relativamente ao próprio relatório.
Somente a existência do JSON não comprova a conclusão: ele e os dois arquivos
referenciados precisam passar pela validação. Cobertura DATASUS segue não verificada.

Interrupção abrupta (SIGKILL/queda de energia) pode deixar temporários. Não há
fsync ou garantia contra perda de energia. Mudanças nos arquivos depois da
conferência são detectadas pelo consumidor ao validar novamente seus hashes;
não há assinatura digital ou proteção contra alteração coordenada do JSON e
dos CSVs. O vínculo do código original à posição vem do processador: não pode
ser provado a partir das 14 colunas, que já não contêm esse código.

## Testes

`TZ=UTC Rscript --vanilla tests/test_auditoria.R` usa somente dados sintéticos,
diretórios temporários e erros/conflitos controlados. Compara os bytes do principal
com a serialização anterior; cobre CSVs vazios, multilinha, duplicatas, zeros,
espaços, NA literal, metadados adulterados, contagens e posições inválidas, falhas
de escrita e de publicação, preservação de destinos e limpeza exclusiva.
As interrupções simuladas são erros R entre etapas; não equivalem a testes de
SIGKILL, desligamento físico ou concorrência de múltiplos processos reais.

`TZ=UTC Rscript --vanilla tests/test_sim_auditoria_integracao.R` avalia o
orquestrador real em cópias temporárias do projeto, com `fetch_datasus()`
substituída no ambiente do script. O processador e o pacote instalados não são
modificados. Compara posições, valores, contagens e bytes esperados e executa
também processos R filhos para verificar sucesso e códigos de saída de falhas.
CSV histórico e temporário alheio usados na suíte são exclusivamente sintéticos.

`TZ=UTC Rscript --vanilla tests/test_organizacao_saida.R` cobre a nova organização,
leitura das duas versões, bytes equivalentes, diretórios com espaços, falhas de
criação/publicação, tentativas de escapar da base autorizada, links, execução de
Rscript a partir de outra pasta e regras do Git. Dois processos Linux reais
disputam uma reserva de diretório; isso demonstra exclusividade nesse cenário,
sem representar testes de estresse ou proteção contra alterações maliciosas do
sistema de arquivos. Os testes Python simulam o subprocesso ao conferir o caminho
do script com outro diretório de trabalho.
