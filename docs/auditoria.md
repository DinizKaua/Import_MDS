# Infraestrutura de auditoria persistente — esquema 1.0.0

Esta infraestrutura está isolada do fluxo de `R/coletar_dados.R`. Nenhuma
extração atual passa a gerar artefatos adicionais automaticamente. Carregar
`R/comum/exportacao.R` e depois `R/comum/auditoria.R` no mesmo ambiente.

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
- `destinos_resultado_auditado(destino_csv)` determina e verifica TODOS os
  destinos. Pode ser usado futuramente antes da coleta. Não cria arquivos.
- `validar_contagens_auditoria(contagens, total_final)` recebe listas opcionais
  `etarias`, `datas`, `naturalidade`, com os contratos atuais dos atributos
  `contagens_*` do SIM. Cada grupo fornecido precisa estar completo. Reconcilia
  categorias, exclusões, totais finais e etapas comuns. Grupos não fornecidos
  ficam explicitamente nulos no relatório. Não infere categorias dos 14 campos.
- `validar_auditoria_naturalidade(auditoria, total_principal)` valida o esquema,
  textos/classificações e posições inteiras únicas entre 1 e o total final.
- `publicar_resultado_auditado(dados, auditoria, destino_csv, metadados,
  contagens, colunas_principal)` prepara, verifica e publica o conjunto.
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

O chamador deve construir o auxiliar a partir do atributo `auditoria_naturalidade`
DEPOIS de todos os filtros, mapear `posicao_csv` para `posicao_registro`, selecionar
as exceções desejadas e os outros quatro campos correspondentes. Esta etapa não
conecta nem modifica o processador. O identificador temporário interno não vai
para nenhum CSV. Posição 1 é o primeiro registro de dados, excluindo o cabeçalho;
campos com quebras de linha não alteram essa definição. Duplicatas legítimas em
posições distintas são mantidas. Não há deduplicação.

Situações suportadas: `ambigua`, `sem_correspondencia`, `ausente`; uma exceção
`inequivoca` também pode ser informada pelo processador, por exemplo para auditar
repetições idênticas da tabela auxiliar. Só a situação `inequivoca` admite uma
descrição determinada; as outras mantêm descrição NA. A infraestrutura não
escolhe descrições nem resolve ambiguidades.

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

`versao_esquema = "1.0.0"`, `id_execucao` e `metadados.id_execucao` coincidem.
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
Execuções concorrentes com os mesmos destinos disputam primeiro o principal;
a que perder não publica seus arquivos seguintes.

Não há atomicidade entre arquivos. Se ocorrer erro, nenhum marcador próprio é
publicado; CSVs definitivos já publicados ficam preservados. Um marcador
conflitante criado por outra execução não é removido nem confundido com sucesso.
Somente temporários explicitamente criados pela execução são limpos. Não há
remoção automática de definitivos, retomada nem recuperação automática. Uma nova
tentativa com os mesmos destinos ocupados falha. Conjuntos sem JSON validado são
incompletos e exigem decisão manual antes do reaproveitamento.

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
