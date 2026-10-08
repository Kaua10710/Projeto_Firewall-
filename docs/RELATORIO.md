# Firewall Linux, Arquitetura Netfilter & Iptables

### Segmentação da rede de uma arena parceira da Kovenza Sports

| | |
|---|---|
| **Disciplina** | Segurança da Informação |
| **Instituição** | IF Goiano — Campus Ceres |
| **Docente** | Prof. Roitier Campos Gonçalves |
| **Modalidade** | Individual |
| **Repositório** | https://github.com/Kaua10710/Projeto_Firewall- |

> Este trabalho é um laboratório isolado em contêineres. Nenhum arquivo,
> endpoint ou credencial do sistema Kovenza Sports em produção foi utilizado,
> importado ou modificado. O Kovenza entra como tema do estudo de caso.

---

## Sumário

1. [Definição do Case](#1-definição-do-case)
2. [Diagnóstico](#2-diagnóstico)
3. [Matriz de Regras de Segurança](#3-matriz-de-regras-de-segurança)
4. [Metodologia de Testes e Validação](#4-metodologia-de-testes-e-validação)

---

## 1. Definição do Case

### 1.1 A empresa e o produto

A **Kovenza Sports** opera um sistema de *replay* instantâneo para quadras
esportivas. O jogador faz uma jogada, aperta um botão físico na beira da quadra,
e em segundos o vídeo dos últimos 60 segundos aparece no aplicativo.

O produto existe e está em operação. Não é um cenário hipotético.

### 1.2 Como o sistema funciona

Em cada quadra atendida, a Kovenza instala três peças de hardware:

- um **mini-PC com Windows**, que faz todo o processamento local;
- uma **câmera IP**, que fornece a imagem da quadra;
- um **botão físico**, ligado ao mini-PC por porta serial.

O mini-PC grava a câmera continuamente em memória temporária. Quando o botão é
acionado, o sistema recorta os últimos 60 segundos e envia o arquivo para a
nuvem. O mesmo mini-PC também empurra a transmissão ao vivo da quadra para o
YouTube, por RTMPS.

A nuvem é o **Supabase** (banco PostgreSQL, autenticação e armazenamento de
arquivos), e a aplicação que o jogador usa é publicada na Vercel.

### 1.3 Os serviços que precisam operar

Para o negócio funcionar, três fluxos de rede são indispensáveis:

| Fluxo | Protocolo | Por que o negócio depende dele |
|---|---|---|
| Mini-PC → Supabase | HTTPS (443) | É por aqui que o replay chega ao aplicativo do jogador. Sem isso, o produto não entrega nada. |
| Mini-PC → ingestão de vídeo | RTMP (1935) | É a transmissão ao vivo da partida. É um diferencial comercial para a arena. |
| Recepção da arena → painel do mini-PC | HTTP (8080) | O dono da arena precisa saber, sem ligar para a Kovenza, se a quadra está transmitindo. É suporte de primeiro nível. |

### 1.4 O ponto que torna este um problema de segurança de rede

**O equipamento da Kovenza fica dentro da arena do cliente.**

A arena é um estabelecimento de terceiros. O mini-PC e a câmera são ligados na
mesma rede Wi-Fi que atende a recepção, o computador do caixa e os
frequentadores do local. A Kovenza **não administra essa rede**: não escolhe o
roteador, não define a senha, não controla quem se conecta.

Dois patrimônios com donos diferentes, níveis de confiança diferentes e
responsabilidades legais diferentes compartilham o mesmo domínio de broadcast.
É daí que vem todo o resto deste relatório.

---

## 2. Diagnóstico

### 2.1 Cenário atual

O levantamento abaixo não é especulativo: são decisões e pendências registradas
no próprio projeto da Kovenza.

#### Problema 1 — A proteção da imagem ao vivo depende de uma linha de código

O serviço de captura espelha o vídeo já codificado num endereço UDP local, para
que o processo de transmissão leia a mesma imagem sem precisar abrir a câmera
duas vezes. Esse espelhamento escuta em `127.0.0.1`, deliberadamente, e o
comentário no código registra o motivo: em `0.0.0.0`, a imagem da quadra ficaria
disponível para **qualquer pessoa conectada à rede da arena, sem autenticação
nenhuma**.

O raciocínio está correto. O problema é o que ele implica: **hoje a única coisa
que impede o vazamento da imagem da quadra é um literal de endereço no código
da aplicação.** Uma refatoração distraída, um parâmetro de configuração mal
preenchido ou uma versão futura que precise expor o fluxo para outro processo
revertem a proteção sem que ninguém perceba. Não existe nenhuma camada de rede
que segure o erro.

Vale notar o que está em jogo: a imagem é de pessoas praticando esporte, muitas
vezes menores de idade, em um espaço que elas consideram privado. Vazamento aqui
não é incidente técnico, é exposição de pessoas.

#### Problema 2 — Credencial de amplo privilégio em máquina de terceiros

O mini-PC carrega hoje uma chave `service_role` do Supabase. Esse tipo de
credencial **contorna as políticas de segurança por linha** (RLS) e permite ler
e escrever o banco inteiro — não apenas os dados daquela quadra.

Essa chave está em uma máquina que fica num estabelecimento de terceiros, sem
disco criptografado, fisicamente acessível a quem tenha acesso à sala onde o
equipamento está instalado. Substituir a chave por credencial por dispositivo é
uma pendência conhecida e reconhecida do projeto.

Enquanto ela existe, o mini-PC não é apenas um ponto de captura: é uma chave
mestra do banco de dados de todos os clientes, guardada fora do perímetro da
empresa.

#### Problema 3 — A câmera é escolhida pelo cliente

A arena escolhe e compra a câmera IP. Câmeras de prateleira têm duas
características bem conhecidas:

- **fazem *phone-home*** — abrem conexões espontâneas para servidores do
  fabricante, frequentemente enviando *thumbnails*, metadados ou o próprio fluxo
  de vídeo, sob o rótulo de "serviço de nuvem";
- **têm interface web com senha fraca ou padrão**, e firmware que raramente
  recebe atualização.

A Kovenza não controla qual modelo será instalado. Portanto precisa tratar a
câmera como **dispositivo não confiável dentro do próprio perímetro**.

#### Problema 4 — Não existe segmentação

Mini-PC, câmera IP e o computador do caixa da arena estão na mesma rede plana.
Isso significa:

- a câmera comprometida alcança o computador do caixa;
- o mini-PC comprometido alcança o computador do caixa;
- um computador qualquer da arena — ou um frequentador no Wi-Fi — alcança a
  câmera e o mini-PC;
- e, por consequência, um incidente em qualquer um dos lados alcança o outro.

### 2.2 Resumo do risco

| Problema | Consequência se explorado | Quem é lesado |
|---|---|---|
| Proteção por literal no código | Imagem ao vivo da quadra acessível sem autenticação | Jogadores (dados pessoais) |
| Chave `service_role` em campo | Leitura/escrita do banco de todos os clientes | Kovenza e todos os clientes |
| Câmera não confiável | Vídeo enviado ao fabricante sem consentimento | Jogadores e a arena |
| Rede plana | Qualquer comprometimento se propaga lateralmente | Kovenza **e** a arena |

O quarto problema é o multiplicador dos outros três. Sem rede plana, os três
primeiros ficam contidos. É por isso que a segmentação é a intervenção escolhida.

### 2.3 Proposta de solução

#### O argumento central

> O equipamento da Kovenza e a operação da arena **têm donos diferentes e níveis
> de confiança diferentes**. Compartilhar rede significa que um incidente em
> qualquer um dos lados alcança o outro.

Isso corta nos dois sentidos, e é o que torna a proposta aceitável para o
cliente: a segmentação protege a Kovenza de um malware vindo da rede da arena, e
protege a arena de um equipamento da Kovenza comprometido. Não é a Kovenza se
blindando contra o cliente; é a eliminação de uma responsabilidade cruzada que
nenhum dos dois quer ter.

#### A arquitetura

Três zonas, em sub-redes distintas, com um firewall Linux como único ponto de
passagem entre elas:

| Zona | Sub-rede | O que representa | Nível de confiança |
|---|---|---|---|
| **Rede Arena** | `172.28.10.0/24` | Recepção, caixa e Wi-Fi dos frequentadores | Não confiável — rede de terceiros |
| **DMZ Kovenza** | `172.28.20.0/24` | Mini-PC, câmera IP e banco local | Parcialmente confiável — equipamento próprio em local alheio |
| **Nuvem** | `172.28.30.0/24` | Supabase e ingestão de vídeo | Destino autorizado de saída |

![topologia](diagrama-rede.md)
*Diagramas completos em [diagrama-rede.md](diagrama-rede.md).*

#### Por que esta arquitetura e não outra

**Por que um firewall e não apenas VLANs?** VLAN separa domínios de broadcast,
mas não decide *o quê* pode trafegar entre eles. O requisito aqui não é "separar"
— é "separar e permitir exatamente três fluxos". Isso exige filtragem por
origem, destino e porta, com estado.

**Por que política `DROP` por padrão?** Com política `ACCEPT` o administrador
precisa prever todo o tráfego indesejado — uma lista infinita e sempre
incompleta. Com `DROP`, precisa prever apenas o tráfego **desejado**, que são as
três linhas da seção 1.3. Um fluxo novo que apareça por engano, por atualização
de firmware ou por ação de um invasor é barrado por omissão, não por previsão.

**Por que a câmera na DMZ e não numa zona própria?** Numa implantação real ela
deveria ficar isolada. Nesta simulação ela compartilha a DMZ com o mini-PC
porque é dali que o mini-PC consome o vídeo; a consequência disso está
documentada honestamente na [seção 4.4](#44-limitação-conhecida-a-regra-r8-não-é-aplicável-nesta-topologia).

**O que a segmentação não resolve.** Ela **contém** os problemas 1, 2 e 3, não os
elimina. A chave `service_role` continua existindo e continua sendo uma pendência
a tratar; a segmentação apenas garante que, se ela vazar, o atacante não ganha
de brinde a rede administrativa da arena. Um relatório que afirmasse o contrário
estaria mentindo sobre o escopo de um controle de rede.

#### Implementação

| Componente | Decisão | Justificativa técnica |
|---|---|---|
| Firewall | `iptables` sobre Netfilter, em Alpine Linux | Filtragem com estado (`conntrack`), presente em qualquer kernel Linux, sem dependência de appliance proprietário |
| Zonas | Três *bridges* Docker isoladas, com `ipam` explícito | Sub-rede e gateway determinísticos, não sorteados pelo Docker |
| Ponto de passagem | Só o `fw-kovenza` participa de mais de uma rede | É o que **obriga** o tráfego inter-zona a atravessar a chain `FORWARD` |
| Roteamento | Rota estática `/24` em cada contêiner, apontando para o firewall | Uma rota `/24` vence a rota *default* por especificidade; ver [seção 4.2](#42-por-que-o-tráfego-realmente-atravessa-o-firewall) |
| Automação | Regras no `ENTRYPOINT` do contêiner | A política é aplicada em todo `docker compose up`, sem passo manual |

---

## 3. Matriz de Regras de Segurança

Implementada em [firewall/entrypoint.sh](../firewall/entrypoint.sh). Cada regra
leva um `-m comment --comment "Rn: ..."`, de modo que a listagem do `iptables`
possa ser lida lado a lado com esta tabela.

| # | Origem | Destino | Porta/Protocolo | Ação | Justificativa do negócio |
|---|---|---|---|---|---|
| 1 | Rede Arena | DMZ `edge-captura` | TCP 8080 | **ACCEPT** | O dono da arena precisa conferir se a quadra está transmitindo |
| 2 | Rede Arena | DMZ `camera-rtsp` | TCP 554 | **DROP** | A imagem ao vivo da quadra não tem autenticação; exibi-la na rede da arena exporia os jogadores |
| 3 | Rede Arena | DMZ `db-local` | TCP 5432 | **DROP** | O banco guarda dados pessoais e nunca é acessado diretamente por estação de trabalho |
| 4 | DMZ `edge-captura` | Nuvem `nuvem-supabase` | TCP 443 | **ACCEPT** | Publicar o replay e informar o estado da quadra |
| 5 | DMZ `edge-captura` | Nuvem `nuvem-rtmp` | TCP 1935 | **ACCEPT** | Transmissão ao vivo da partida |
| 6 | DMZ `edge-captura` | Rede Arena | qualquer | **DROP** | Se o mini-PC for comprometido, ele não alcança a rede administrativa da arena |
| 7 | DMZ `camera-rtsp` | Nuvem | qualquer | **DROP** | Impede o *phone-home* do fabricante da câmera, que enviaria imagem para fora sem consentimento |
| 8 | DMZ `camera-rtsp` | DMZ `edge-captura` | TCP 554 | **ACCEPT** | Apenas o mini-PC consome o vídeo da câmera |
| 9 | Qualquer | Qualquer | qualquer | **DROP** | Política padrão: nada que não esteja explicitamente liberado passa |

### 3.1 Comentários sobre regras específicas

**Regra 7 — a que defende saída, não entrada.** Praticamente todo trabalho de
firewall pensa em quem entra. A regra 7 bloqueia a câmera de **sair**. A ameaça
que ela trata não é um invasor: é o comportamento normal, documentado e
anunciado como funcionalidade do próprio fabricante da câmera, que abre conexão
para a nuvem dele e envia imagem para fora. Do ponto de vista jurídico isso é
transferência de dados pessoais a terceiro sem base legal; do ponto de vista de
rede, é tráfego de saída de um dispositivo que não deveria ter nenhum. A câmera
precisa falar com exatamente um host — o mini-PC. Mais nada.

**Regra 6 — contenção de pivô.** A regra 6 não protege a Kovenza, protege a
arena. Se o mini-PC for comprometido (e ele é a máquina mais exposta do
conjunto: Windows, em local de terceiros, com credencial privilegiada), o
atacante não consegue alcançar o computador do caixa a partir dele. É a regra
que torna a proposta defensável numa conversa com o dono da arena.

**Regra 9 — a política.** É a regra que transforma as outras oito de "lista de
bloqueios" em "lista de permissões". Sem ela, qualquer porta não mencionada na
matriz estaria aberta.

### 3.2 Ordem de avaliação

O Netfilter avalia a chain de cima para baixo e para no primeiro alvo terminal.
A ordem implementada é fixa e intencional:

```
1. conntrack ESTABLISHED,RELATED  →  ACCEPT
2. ACCEPTs específicos            →  R1, R4, R5, R8
3. DROPs explícitos               →  R2, R3, R6, R7
4. LOG                            →  prefixo KOVENZA-FW-DROP:
5. DROP final + policy DROP       →  R9
```

Duas consequências de projeto:

**O conntrack vem primeiro e é obrigatório.** Uma conexão TCP tem dois sentidos.
Se apenas o `SYN` de ida fosse liberado, o `SYN/ACK` de volta bateria na
política `DROP` e todos os testes positivos falhariam. A regra de `conntrack`
reconhece o pacote de retorno como pertencente a um fluxo já autorizado, sem
precisar de uma regra espelhada para cada liberação.

**Os `DROP` explícitos são redundantes — e são a prova do trabalho.** A política
padrão já descartaria esse tráfego. Eles existem porque aparecem na listagem com
**contador de pacotes**, demonstrando que a tentativa chegou ao firewall e foi
barrada — e não que simplesmente ninguém tentou. A diferença entre essas duas
coisas é o assunto da [seção 4.2](#42-por-que-o-tráfego-realmente-atravessa-o-firewall).

---

## 4. Metodologia de Testes e Validação

### 4.1 Preparação do ambiente

Pré-requisitos: Docker e Docker Compose v2.

```sh
git clone https://github.com/Kaua10710/Projeto_Firewall-.git
cd Projeto_Firewall-
docker compose up -d --build
```

As regras são aplicadas automaticamente pelo `ENTRYPOINT` do `fw-kovenza`. Não
há passo manual. Para conferir:

```sh
docker compose ps
docker compose logs fw-kovenza
```

Duas observações para o avaliador, para que nada seja interpretado como falha:

- **Os testes usam IP, não nome de contêiner.** O DNS do Docker resolve nomes
  apenas dentro da mesma rede. A `estacao-recepcao` está em `rede_arena` e o
  `edge-captura` em `rede_dmz` — a estação não resolve o nome. Isso é
  consequência direta da segmentação, não defeito.
- **O `curl` para a nuvem usa `-k`.** O `nuvem-supabase` serve HTTPS com
  certificado autoassinado, gerado no build. O `-k` desativa a validação da
  cadeia de certificação, não o TLS.

### 4.2 Por que o tráfego realmente atravessa o firewall

Esta subseção existe porque é o ponto onde um laboratório de firewall costuma
ser aprovado sem funcionar.

No Docker, contêineres da **mesma** *bridge* conversam diretamente, sem passar
por gateway nenhum. Se a estação e a DMZ estivessem na mesma rede, o firewall
seria decorativo: o tráfego nunca atravessaria a chain `FORWARD`, e os testes
positivos passariam pelo motivo errado.

Aqui cada zona é uma *bridge* separada e só o `fw-kovenza` participa das três.
Isso resolve o problema e cria o seguinte: por padrão as zonas não se enxergam,
porque não existe rota entre elas. A única rota para fora da própria sub-rede é
a *default*, que aponta para o gateway da *bridge* no host.

A solução é uma **rota estática em cada contêiner não-firewall**, instalada por
[scripts/rotas.sh](../scripts/rotas.sh) na subida:

```sh
# dentro de estacao-recepcao
ip route add 172.28.20.0/24 via 172.28.10.254
ip route add 172.28.30.0/24 via 172.28.10.254
```

Uma rota `/24` é mais específica que `0.0.0.0/0`, portanto vence na tabela de
roteamento e o pacote sobe para o firewall. Por isso **todos** os contêineres
declaram `cap_add: [NET_ADMIN]`, não apenas o firewall — alterar tabela de
roteamento é operação privilegiada.

### 4.3 O critério que separa bloqueio de ausência de rota

Um teste negativo pode falhar por dois motivos opostos:

| Motivo | O que significa | No terminal |
|---|---|---|
| O firewall recebeu o pacote e descartou | Segmentação **por desenho** | timeout |
| Não havia rota e o pacote nunca saiu | Segmentação **por acidente** | timeout |

**Os dois são visualmente idênticos.** Um trabalho que só observe o terminal não
distingue um do outro.

O [scripts/testes-negativos.sh](../scripts/testes-negativos.sh) implementa a
distinção. Para cada teste negativo:

1. zera os contadores — `iptables -Z FORWARD`;
2. executa a tentativa de conexão;
3. lê o contador de pacotes da regra de `DROP` correspondente.

O critério de aprovação é duplo:

- conexão falhou **e** contador > 0 → bloqueado **pelo firewall**. **Aprovado.**
- conexão falhou **e** contador = 0 → o pacote não chegou ao firewall. O script
  **reprova** e avisa para verificar as rotas estáticas.

### 4.4 Limitação conhecida: a regra R8 não é aplicável nesta topologia

A regra 8 (`camera-rtsp` → `edge-captura`, TCP 554) está implementada e aparece
na listagem do `iptables`, mas **seu contador permanece em zero por construção**:
câmera e mini-PC estão na mesma *bridge* (`rede_dmz`), portanto esse tráfego é
entregue diretamente pelo Docker e nunca atravessa a chain `FORWARD`.

A regra foi mantida porque registra a intenção de projeto e documenta a
expectativa de fluxo. Em uma implantação real — ou numa versão futura deste
laboratório — a câmera moraria em uma quarta zona isolada, e aí a regra passaria
a ser efetivamente aplicada. Pelo mesmo motivo, a proteção intra-DMZ entre
câmera e mini-PC hoje depende do próprio host, não do firewall.

Registrar isso é mais útil que omitir: o contador em zero seria notado em
qualquer inspeção cuidadosa da chain.

### 4.5 Testes positivos — o negócio precisa que funcionem

```sh
sh scripts/testes-positivos.sh
```

| # | Teste | Regra | Comando | Esperado |
|---|---|---|---|---|
| 1 | Recepção acessa o painel da quadra | R1 | `docker compose exec estacao-recepcao curl -s -o /dev/null -w "%{http_code}\n" http://172.28.20.10:8080/health` | HTTP `200` |
| 2 | Mini-PC publica no Supabase | R4 | `docker compose exec edge-captura curl -k -s -o /dev/null -w "%{http_code}\n" https://172.28.30.10` | HTTP `200` |
| 3 | Mini-PC alcança a ingestão de vídeo | R5 | `docker compose exec edge-captura nc -zv -w 3 172.28.30.20 1935` | porta aberta |

#### Resultado obtido

Execução em Docker Desktop 29.7.2 / Windows 11. **3 aprovados, 0 reprovados.**

| # | Esperado | Obtido | Resultado |
|---|---|---|---|
| 1 | HTTP `200` | HTTP `200` | **APROVADO** |
| 2 | HTTP `200` | HTTP `200` | **APROVADO** |
| 3 | porta aberta | `Connection to 172.28.30.20 1935 port [tcp/*] succeeded!` | **APROVADO** |

Contadores das regras de `ACCEPT` imediatamente após os três testes:

```
num   pkts bytes target  prot  source           destination
2        1    60 ACCEPT  tcp   172.28.10.0/24   172.28.20.10   dpt:8080  /* R1: arena -> painel da quadra 8080 */
3        1    60 ACCEPT  tcp   172.28.20.10     172.28.30.10   dpt:443   /* R4: edge -> supabase 443 */
4        1    60 ACCEPT  tcp   172.28.20.10     172.28.30.20   dpt:1935  /* R5: edge -> ingest rtmp 1935 */
```

Um pacote contabilizado por regra: é o `SYN` de abertura de cada conexão. Os
pacotes seguintes de cada fluxo são contados pela regra 1 (`conntrack`), que já
os reconhece como `ESTABLISHED`. Isso confirma que o tráfego legítimo foi
**autorizado por regra específica**, e não liberado por acaso.

### 4.6 Testes negativos — o firewall precisa barrar

```sh
sh scripts/testes-negativos.sh
```

| # | Teste | Regra | Comando | Esperado |
|---|---|---|---|---|
| 4 | Recepção tenta o banco | R3 | `docker compose exec estacao-recepcao nmap -Pn -p 5432 172.28.20.30` | `filtered` |
| 5 | Recepção tenta a câmera | R2 | `docker compose exec estacao-recepcao nc -zv -w 3 172.28.20.20 554` | falha |
| 6 | Câmera tenta sair para a internet | R7 | `docker compose exec camera-rtsp nc -zv -w 3 172.28.30.10 443` | falha |
| 7 | Mini-PC tenta pivotar para a recepção | R6 | `docker compose exec edge-captura nc -zv -w 3 172.28.10.10 22` | falha |

#### Resultado obtido

**4 aprovados, 0 reprovados** — e, em todos os quatro, com o contador da regra
de `DROP` acima de zero, satisfazendo o critério duplo da seção 4.3.

| # | Regra | Obtido | Contador da regra | Resultado |
|---|---|---|---|---|
| 4 | R3 | `5432/tcp filtered postgresql` | 2 pacotes | **APROVADO — bloqueado pelo firewall** |
| 5 | R2 | `nc: connect to 172.28.20.20 port 554 (tcp) timed out` | 5 pacotes | **APROVADO — bloqueado pelo firewall** |
| 6 | R7 | `nc: connect to 172.28.30.10 port 443 (tcp) timed out` | 5 pacotes | **APROVADO — bloqueado pelo firewall** |
| 7 | R6 | `nc: connect to 172.28.10.10 port 22 (tcp) timed out` | 5 pacotes | **APROVADO — bloqueado pelo firewall** |

Dois detalhes que valem leitura atenta:

**O `nmap` reporta `filtered`, não `closed`.** A distinção importa. `closed`
significa que o pacote chegou ao destino e o host respondeu `RST` — ou seja, a
porta foi alcançada. `filtered` significa que nada voltou: o pacote foi
descartado silenciosamente no caminho. É exatamente a assinatura de um `DROP`
(e não de um `REJECT`, que devolveria erro ICMP). O `DROP` foi a escolha
deliberada da matriz: não confirmar ao atacante que o host existe.

**Os 5 pacotes nos testes 5, 6 e 7 são retransmissões de `SYN`.** O `nc` não
recebe resposta alguma, então o TCP retransmite o `SYN` até desistir. Cada
retransmissão é um pacote novo que bate na regra e incrementa o contador. O
teste 4 marca 2 porque o `nmap` tem política própria de retransmissão, mais
econômica.

### 4.7 Evidência final — a chain FORWARD

```sh
docker compose exec fw-kovenza iptables -L FORWARD -v -n --line-numbers
```

Saída real, capturada após as quatro tentativas negativas executadas em
sequência sem zerar os contadores entre elas — é assim que o
[scripts/testes-negativos.sh](../scripts/testes-negativos.sh) produz a
evidência final, para que as quatro regras de `DROP` apareçam povoadas na mesma
listagem:

```
Chain FORWARD (policy DROP 0 packets, 0 bytes)
num   pkts bytes target  prot  source           destination
1        0     0 ACCEPT  all   0.0.0.0/0        0.0.0.0/0      ctstate RELATED,ESTABLISHED /* CONNTRACK: retorno de conexoes autorizadas */
2        0     0 ACCEPT  tcp   172.28.10.0/24   172.28.20.10   tcp dpt:8080  /* R1: arena -> painel da quadra 8080 */
3        0     0 ACCEPT  tcp   172.28.20.10     172.28.30.10   tcp dpt:443   /* R4: edge -> supabase 443 */
4        0     0 ACCEPT  tcp   172.28.20.10     172.28.30.20   tcp dpt:1935  /* R5: edge -> ingest rtmp 1935 */
5        0     0 ACCEPT  tcp   172.28.20.20     172.28.20.10   tcp dpt:554   /* R8: camera -> edge 554 (intra-DMZ) */
6        5   300 DROP    tcp   172.28.10.0/24   172.28.20.20   tcp dpt:554   /* R2: arena -X camera 554 */
7        2    88 DROP    tcp   172.28.10.0/24   172.28.20.30   tcp dpt:5432  /* R3: arena -X banco 5432 */
8        5   300 DROP    all   172.28.20.10     172.28.10.0/24               /* R6: edge -X arena (anti-pivot) */
9        5   300 DROP    all   172.28.20.20     172.28.30.0/24               /* R7: camera -X nuvem (anti phone-home) */
10       0     0 DROP    all   172.28.20.0/24   172.28.10.0/24               /* R6b: DMZ -X arena (generalizacao de R6) */
11       0     0 LOG     all   0.0.0.0/0        0.0.0.0/0      limit: avg 10/min burst 5 /* R9: log do descarte padrao */ LOG level 4 prefix "KOVENZA-FW-DROP: "
12       0     0 DROP    all   0.0.0.0/0        0.0.0.0/0                    /* R9: politica padrao, descarte explicito */
```

Como ler esta listagem:

- **`policy DROP`** no cabeçalho é a regra 9 da matriz em vigor.
- **Regras 6, 7, 8 e 9 com contador acima de zero** são as regras R2, R3, R6 e
  R7. Cada uma registrou o tráfego que deveria barrar. É a prova pedida na
  seção 4.3.
- **Regra 10 (R6b) em zero** é o comportamento correto: ela generaliza o R6 para
  toda a DMZ, mas a regra 8 é mais específica e vem antes, então captura o
  tráfego do `edge-captura` primeiro. A regra 10 só agiria se a câmera ou o
  banco tentassem alcançar a arena.
- **Regra 5 (R8) em zero** é a limitação documentada na
  [seção 4.4](#44-limitação-conhecida-a-regra-r8-não-é-aplicável-nesta-topologia):
  câmera e mini-PC estão na mesma *bridge*, e esse tráfego nunca atravessa a
  chain.
- **Regras 1 a 4 em zero** aqui apenas porque os contadores foram zerados antes
  desta captura, que só executou tráfego negativo. Os valores dos `ACCEPT`
  estão na [seção 4.5](#45-testes-positivos--o-negócio-precisa-que-funcionem).
- **Regra 12 em zero** merece explicação: o descarte final não foi exercido
  porque todo o tráfego negativo testado casou com uma regra `DROP` específica
  antes de chegar lá. Ela permanece como rede de segurança para qualquer fluxo
  não previsto na matriz.

### 4.8 Sobre o LOG

A penúltima regra da chain é um `LOG` com prefixo `KOVENZA-FW-DROP:`, limitado a
10 entradas por minuto para não inundar o kernel.

**No Docker Desktop para Windows essas linhas podem não ser visíveis**: o log do
kernel não chega ao `dmesg` do contêiner. A regra continua válida como
demonstração do recurso, e o que serve de prova neste ambiente é o **contador de
pacotes** de cada regra.

Este relatório não promete ao avaliador que ele verá linhas de log.

### 4.9 Encerramento

```sh
docker compose down -v
```

---

## Conclusão

A segmentação implementada reduz quatro riscos a um escopo contido:

- a imagem ao vivo da quadra deixa de depender de um literal no código para não
  vazar na rede da arena — a regra 2 a bloqueia na camada de rede;
- a chave `service_role`, se vazar, não dá acesso à rede administrativa da arena
  — a regra 6 impede o pivô;
- a câmera não consegue enviar vídeo ao fabricante — a regra 7 bloqueia a saída;
- e nenhum dos três incidentes atravessa a fronteira entre a Kovenza e o
  cliente, porque a política padrão é `DROP`.

O que a segmentação **não** faz: eliminar a credencial privilegiada em campo,
corrigir a senha padrão da câmera ou criptografar o disco do mini-PC. Esses
seguem como pendências do projeto. Um firewall contém consequências; não
substitui a correção das causas.
