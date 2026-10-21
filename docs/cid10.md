# Prefixos e intervalos CID-10

`--cid` admite `ALL`, um prefixo literal legado ou um intervalo inclusivo de
categorias. Python mantém Enter como `ALL`. O R valida intervalos antes de
reservar `Dados/<extracao>/` ou executar a única chamada a `fetch_datasus()`.
Os argumentos de coleta do pacote permanecem iguais: CID é um filtro local.

## Referência oficial fixada

- Origem: Organização Mundial da Saúde (OMS).
- Navegador: <https://icd.who.int/browse10/2019/en/>.
- Arquivo oficial: <https://icdcdn.who.int/icd10/claml/icd102019en.xml.zip>.
- Versão declarada pelo XML: **2019-covid-expanded**; nome `ICD-10-EN`.
- Identificador WHO: `icd10_20210322`.
- Data declarada no elemento Title: `2020-03-22`.
- Obtido em UTC: `2026-10-21T00:51:39Z`.
- ZIP original, sem alterações: `referencias/cid10/icd102019en.xml.zip`.
- SHA-256 do ZIP: `344c571aa9aed3b9ad1c80261b7828c45cfb5fc0b1a5da64aecef354dff5b3d9`.
- Índice local: `referencias/cid10/oms_2019_codigos.json`, contendo todas as
  2.090 categorias de três caracteres, 9.153 subcategorias explicitamente
  declaradas como classes `category` e 50 subcategorias derivadas de `S04E10_4`,
  totalizando **9.203 subcategorias**. Inclui procedência e SHA-256 do XML original.
  Não contém títulos ou descrições clínicas.
- Formato do índice: `versao_indice: "1.0.0"`, preservado para os consumidores
  existentes. Revisão do algoritmo: `referencia.geracao.versao: "1.1.0"`.
  O índice anterior não possuía `geracao` e omitia as subdivisões de diabetes.
  Esta revisão é do Import_MDS; **não é uma nova edição da classificação OMS**.

O nome do download contém 2019, mas a versão interna inclui a expansão COVID.
As datas e o identificador acima são registrados como declarados pela fonte;
não inferimos deles uma data única de publicação ou de vigência no Brasil.
I10, I11, I12, I13 e I15 existem nessa referência; I14 não existe.

O ZIP e o índice são versionáveis e precisam acompanhar o projeto. Nenhuma
consulta de extração acessa a OMS, DATASUS ou outro serviço para validar CID.
A única obtenção externa desta etapa foi a classificação oficial da OMS,
sem download de microdados. Não há novas dependências: Python usa a biblioteca
padrão; R usa `jsonlite`, já adotado pelo projeto.

### Reprodução sem rede

Com o ZIP local, gere um arquivo NOVO para comparação (o gerador recusa substituir
um destino existente):

```sh
python3 -B scripts/gerar_referencia_cid10.py \
  referencias/cid10/icd102019en.xml.zip /tmp/oms_2019_codigos_reproduzidos.json \
  --obtido-em 2026-10-21T00:51:39Z
cmp referencias/cid10/oms_2019_codigos.json /tmp/oms_2019_codigos_reproduzidos.json
```

O gerador exige o SHA-256 do ZIP fixado, rejeita duplicatas, formatos desconhecidos
e subcategorias sem categoria correspondente. Não expande classes por sequências
numéricas nem por suposições sobre códigos intermediários. Uma atualização da
referência exige nova revisão, regeneração, testes e identificação nos metadados;
o arquivo remoto não é consultado automaticamente durante uma execução. A mesma
fonte e o mesmo `--obtido-em` produzem bytes idênticos. A data de obtenção continua
identificando o download original do ZIP, não a data de regeneração do índice.

## Correção direcionada das subdivisões de diabetes

O ClaML pode declarar subdivisões compartilhadas com `Modifier`, `ModifierClass`
e vínculos `ModifiedBy`, sem enumerar cada código completo como uma `Class`.
O gerador anterior lia somente as classes explícitas. Como consequência,
`E10-E14` rejeitava subcategorias válidas como `E109`, `E119`, `E142`, `E148`
e `E149`, tanto compactas quanto pontuadas.

A função `expandir_diabetes(raiz)` trata exclusivamente o modificador `S04E10_4`.
Ela confirma sua definição, as dez classes de sufixos `.0` a `.9` e os cinco
vínculos diretos das categorias E10, E11, E12, E13 e E14 ao bloco E10–E14.
Os 50 códigos resultam dessas associações lidas do XML. Não são uma lista manual.
`all` omitido ou `true` admite os dez sufixos nessa estrutura. Qualquer restrição
`ValidModifierClass`, exclusão do modificador, posição, variante, categoria extra,
vínculo adicional ou estrutura técnica diferente interrompe a geração para revisão;
nenhuma dessas estruturas restritivas existe no caso aprovado da fonte fixada.

A união com as classes explícitas preserva todos os códigos anteriores e impede
duplicação, inclusive se um código também estiver enumerado explicitamente. Os
metadados `referencia.geracao` registram o modificador, as categorias, os códigos
derivados, as quantidades explícitas/derivadas/adicionadas e a ausência de expansão
dos outros modificadores. Essa procedência segue para os relatórios novos de
intervalos pelo campo de referência já existente, sem alterar o esquema 1.1.0.

A extração MA, 1996–2024, E10-E14, idade mínima 18, realizada com o índice anterior,
recebeu 805.956 registros, preservou 720.155 após idade e terminou com zero. Seu
resultado está comprometido pelo defeito conhecido e **não demonstra ausência de
óbitos por diabetes**. Seus arquivos devem permanecer intactos para diagnóstico.
Esta correção não os migra nem repete a coleta. Uma futura execução requer
planejamento próprio e preservação do resultado anterior.

## Interpretação e seleção

`R/comum/cid.R` deve ser carregado no mesmo ambiente antes de `sim.R`:

- `carregar_referencia_cid()` lê o índice relativamente ao próprio módulo,
  independente do diretório de trabalho, e valida seu contrato.
- `interpretar_consulta_cid(cid, referencia = NULL)` retorna `consulta_cid`, com
  modalidade `all`, `prefixo` ou `intervalo`. O argumento opcional permite
  referências controladas em testes. A referência só é carregada para intervalos.
- `selecionar_cid(codigos, consulta)` retorna uma máscara de seleção; não altera
  os registros ou seus códigos. O fluxo SIM usa o `cid_valor` em maiúsculas que
  já existia antes desta implementação.
- `complementar_filtros_cid()` acrescenta somente os metadados de intervalos.

A presença do hífen ASCII `-` indica tentativa de intervalo. Exige-se exatamente
`LNN-LNN`, admitindo letras minúsculas e espaços/tabulações externos e em torno
do hífen. Não são admitidos espaços internos (`I 10`), sufixos nos limites,
quebras de linha, separadores repetidos ou letras diferentes. Ambos os limites
precisam existir na referência. Limites invertidos são rejeitados; iguais são
aceitos. `I10 - I15` e `i10-i15` tornam-se `I10-I15`.

Categorias elegíveis são a interseção da referência com a letra e os limites
numéricos inclusivos; lacunas não são preenchidas. Para os registros, admite-se
categoria de três caracteres e subcategoria de quatro caracteres em forma
compacta (`I110`) ou com ponto (`I11.0`). O código inteiro deve corresponder ao
formato e à referência; por exemplo, `I111`, `I11.1`, `I11XYZ`, `I1100`, `I10.0`
e códigos com espaços não satisfazem I10-I15 nessa referência. Não se utiliza
apenas `substr()` ou uma comparação textual entre códigos completos.

Todas as categorias de três caracteres presentes na referência são elegíveis
como categoria, mesmo quando possuem subdivisões. Isso é uma regra de seleção
por categoria, não uma declaração de que qualquer categoria agregadora pode ser
usada como código final de causa básica em certificação de óbito.

Sem hífen ASCII, o texto continua sendo prefixo literal: não há trim, remoção de
pontos, validação de existência ou interpretação de listas/separadores alternativos.
`I2`, `I21`, `I210`, `I21.0`, prefixos com espaços e o vazio direto no R mantêm
`startsWith()`. `I210` e `I21.0` continuam diferentes. O vazio direto no R não é
convertido em `ALL`: ele seleciona por prefixo vazio e exclui CID NA; `ALL`
preserva CID NA. A interface e o orquestrador mantêm a conversão anterior para
maiúsculas. Uma revisão das entradas legadas permanece fora desta etapa.

## Artefatos e metadados

Prefixos preservam os nomes anteriores. Para intervalos, o orquestrador entrega
a consulta validada a `construir_nome_csv(..., consulta_cid = consulta_cid)`:

```text
Dados/dados_SIM-DO_MA_2014_2014_cid-intervalo-I10-I15_idade_18mais/
  dados_SIM-DO_MA_2014_2014_cid-intervalo-I10-I15_idade_18mais.csv
  logs/…_auditoria_naturalidade.csv
  logs/…_relatorio.json
```

A versão JSON permanece **1.1.0**. `metadados.consulta.filtros.cid` mantém seu tipo
texto, com o intervalo canonizado. Somente para intervalos existe o objeto opcional
`cid_intervalo`: modalidade, limites, metadados da referência e categorias elegíveis.
Não são criadas contagens novas. Os totais existentes continuam correspondendo às
mesmas etapas e incluem a seleção final de CID. O consumidor segue aceitando
artefatos antigos sem esse objeto e relatórios 1.0.0 nos diretórios históricos.

Idade, sexo, raça/cor, datas, naturalidade, IDs, duplicatas, ordem e as 14 colunas
não recebem novas transformações. A normalização CID para intervalos só constrói
a máscara; não altera CAUSABAS ou DOENCA além da regra de maiúsculas preexistente.
Continuam vigentes reserva exclusiva do diretório, hard links sem sobrescrita,
temporários próprios, checksums e JSON publicado por último.

## Limitações históricas

É uma fotografia fixa da classificação internacional, não uma tabela de vigência
por ano do SIM nem uma conciliação com todas as adaptações brasileiras. Códigos
introduzidos posteriormente, descontinuados ou com representação local diferente
podem não existir nela. A referência contém também classes para uso emergencial;
sua presença não comprova vigência ou autorização de uso no Brasil naquele ano.
Não há mapeamento automático entre versões.

São aceitas as subcategorias explícitas e as 50 derivadas do caso autorizado
`S04E10_4`. **Os demais modificadores continuam sem expansão.** Alguns são
qualificadores separados, como local de ocorrência e atividade; outros contêm
extensões suplementares e restrições que exigem análise própria. Este gerador
não é um interpretador universal de ClaML. Resultados vazios de outros intervalos
exigem cautela: a ausência de um código no índice não prova sua inexistência na
classificação completa. Códigos com mais de quatro caracteres não são reconhecidos
pelo ramo de intervalo desta versão. Esse limite não é imposto ao prefixo legado.
A referência não comprova qualidade epidemiológica nem cobertura dos arquivos
DATASUS, que permanece `nao_verificada`.

## Testes

`tests/test_filtro_intervalo_cid.R` testa a referência local, referências sintéticas
com lacunas, códigos inválidos, prefixos legados, filtros combinados, registros e
contagens preservados, nomes e três artefatos, além de rejeição antes da reserva
e da coleta simulada. `tests/test_cli_intervalo_cid.py` cobre perguntas, argumentos,
referência indisponível e reprodução do índice a partir do ZIP local. Todos os
testes funcionam sem internet e sem modificar o pacote microdatasus.

`tests/test_gerar_referencia_cid10.py` verifica a expansão direcionada na fonte
original e em fixtures em memória, a recusa de estruturas inesperadas, preservação
dos códigos explícitos, não expansão de outros modificadores, ZIP intacto e
regeneração determinística byte a byte. A suíte R também reproduz oito adultos
com subcategorias de diabetes: o catálogo anterior selecionava zero e o corrigido
seleciona os oito, preservando filtros, IDs, duplicatas e os três artefatos.
