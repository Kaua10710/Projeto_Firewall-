# Diagrama da topologia

Kovenza Sports — segmentação da rede de uma arena parceira.
Os diagramas abaixo renderizam diretamente no GitHub.

---

## 1. Topologia das três zonas

```mermaid
graph TB
    subgraph ARENA["Rede Arena — 172.28.10.0/24"]
        EST["estacao-recepcao<br/>172.28.10.10<br/><i>recepção / caixa</i>"]
    end

    subgraph DMZ["DMZ Kovenza — 172.28.20.0/24"]
        EDGE["edge-captura<br/>172.28.20.10:8080<br/><i>mini-PC de captura</i>"]
        CAM["camera-rtsp<br/>172.28.20.20:554<br/><i>câmera IP do cliente</i>"]
        DB["db-local<br/>172.28.20.30:5432<br/><i>banco local</i>"]
    end

    subgraph NUVEM["Rede Nuvem — 172.28.30.0/24"]
        SUPA["nuvem-supabase<br/>172.28.30.10:443<br/><i>API e storage</i>"]
        RTMP["nuvem-rtmp<br/>172.28.30.20:1935<br/><i>ingestão YouTube</i>"]
    end

    FW["<b>fw-kovenza</b><br/>172.28.10.254 · 172.28.20.254 · 172.28.30.254<br/>FORWARD policy = DROP"]

    EST  <--> FW
    EDGE <--> FW
    CAM  <--> FW
    DB   <--> FW
    SUPA <--> FW
    RTMP <--> FW

    CAM -.->|"R8: RTSP 554<br/>intra-DMZ, não passa pelo FW"| EDGE

    classDef fw fill:#b91c1c,stroke:#7f1d1d,color:#fff,stroke-width:2px
    classDef arena fill:#1e40af,stroke:#1e3a8a,color:#fff
    classDef dmz fill:#b45309,stroke:#92400e,color:#fff
    classDef nuvem fill:#047857,stroke:#065f46,color:#fff

    class FW fw
    class EST arena
    class EDGE,CAM,DB dmz
    class SUPA,RTMP nuvem
```

O `fw-kovenza` é o **único** contêiner presente em mais de uma rede. Toda
comunicação entre zonas atravessa obrigatoriamente a chain `FORWARD` dele.

A seta pontilhada (R8) registra a única exceção: `camera-rtsp` e `edge-captura`
estão na mesma bridge, logo esse tráfego é entregue direto pelo Docker e não é
filtrado. Ver [RELATORIO.md, seção 4.4](RELATORIO.md#44-limitação-conhecida-a-regra-r8-não-é-aplicável-nesta-topologia).

---

## 2. Fluxos autorizados e bloqueados

```mermaid
graph LR
    EST["estacao-recepcao<br/>172.28.10.10"]
    EDGE["edge-captura<br/>172.28.20.10"]
    CAM["camera-rtsp<br/>172.28.20.20"]
    DB["db-local<br/>172.28.20.30"]
    SUPA["nuvem-supabase<br/>172.28.30.10"]
    RTMP["nuvem-rtmp<br/>172.28.30.20"]

    EST  -->|"R1 ACCEPT · TCP 8080"| EDGE
    EDGE -->|"R4 ACCEPT · TCP 443"| SUPA
    EDGE -->|"R5 ACCEPT · TCP 1935"| RTMP

    EST  x-.-x|"R2 DROP · TCP 554"| CAM
    EST  x-.-x|"R3 DROP · TCP 5432"| DB
    EDGE x-.-x|"R6 DROP · anti-pivot"| EST
    CAM  x-.-x|"R7 DROP · anti phone-home"| SUPA

    classDef ok fill:#047857,stroke:#065f46,color:#fff
    classDef bad fill:#b91c1c,stroke:#7f1d1d,color:#fff
    classDef neutro fill:#374151,stroke:#1f2937,color:#fff

    class EST,EDGE neutro
    class SUPA,RTMP ok
    class CAM,DB bad
```

Linha cheia = `ACCEPT`. Linha pontilhada com `x` = `DROP`.

---

## 3. Caminho de um pacote na chain FORWARD

A ordem é o que faz a política funcionar: o Netfilter avalia de cima para baixo
e para no primeiro alvo terminal.

```mermaid
flowchart TD
    P["Pacote entra na chain FORWARD"] --> CT{"conntrack:<br/>ESTABLISHED<br/>ou RELATED?"}

    CT -->|sim| OK1["ACCEPT<br/><i>retorno de conexão já autorizada</i>"]
    CT -->|não| ACC{"casa com algum<br/>ACCEPT explícito?<br/>R1, R4, R5, R8"}

    ACC -->|sim| OK2["ACCEPT"]
    ACC -->|não| DRP{"casa com algum<br/>DROP explícito?<br/>R2, R3, R6, R7"}

    DRP -->|sim| BAD1["DROP<br/><i>contador incrementa:<br/>é a prova do bloqueio</i>"]
    DRP -->|não| LOG["LOG<br/>prefixo KOVENZA-FW-DROP:<br/><i>não é alvo terminal,<br/>o pacote segue</i>"]

    LOG --> BAD2["DROP final + policy DROP<br/><i>R9: o que não foi liberado morre aqui</i>"]

    classDef ok fill:#047857,stroke:#065f46,color:#fff
    classDef bad fill:#b91c1c,stroke:#7f1d1d,color:#fff
    classDef dec fill:#1e40af,stroke:#1e3a8a,color:#fff
    classDef log fill:#b45309,stroke:#92400e,color:#fff

    class OK1,OK2 ok
    class BAD1,BAD2 bad
    class CT,ACC,DRP dec
    class LOG log
```

Se um `ACCEPT` amplo estivesse antes de um `DROP` específico, o `DROP` nunca
seria alcançado. É por isso que a ordem no
[firewall/entrypoint.sh](../firewall/entrypoint.sh) é fixa:
**conntrack → ACCEPTs → DROPs → LOG**.

---

## 4. Por que existem rotas estáticas

```mermaid
flowchart TD
    subgraph SEM["Sem rota estática (padrão do Docker)"]
        A1["estacao-recepcao<br/>destino 172.28.20.10"] --> A2{"tabela de<br/>roteamento"}
        A2 -->|"única opção:<br/>default via 172.28.10.1"| A3["gateway da bridge<br/>no host Docker"]
        A3 --> A4["DOCKER-ISOLATION<br/>descarta"]
        A4 --> A5["falha — e o firewall<br/>nunca viu o pacote"]
    end

    subgraph COM["Com rota estática (este projeto)"]
        B1["estacao-recepcao<br/>destino 172.28.20.10"] --> B2{"tabela de<br/>roteamento"}
        B2 -->|"172.28.20.0/24 via 172.28.10.254<br/><b>mais específica que a default</b>"| B3["fw-kovenza"]
        B3 --> B4["chain FORWARD<br/>avalia a matriz"]
        B4 --> B5["decisão por regra,<br/>com contador"]
    end

    classDef bad fill:#b91c1c,stroke:#7f1d1d,color:#fff
    classDef ok fill:#047857,stroke:#065f46,color:#fff
    classDef dec fill:#1e40af,stroke:#1e3a8a,color:#fff

    class A4,A5 bad
    class B3,B4,B5 ok
    class A2,B2 dec
```

Os dois caminhos **falham igual no terminal** para um teste negativo — e só um
deles é segurança de verdade. É exatamente essa diferença que o
[scripts/testes-negativos.sh](../scripts/testes-negativos.sh) mede, zerando os
contadores antes de cada teste e exigindo que a regra de `DROP` registre o
pacote.
