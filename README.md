# Firewall Linux com Netfilter/Iptables — Segmentação de Rede da Kovenza Sports

Laboratório de segmentação de rede em contêineres Docker, construído para a
disciplina de **Segurança da Informação** do IF Goiano, Campus Ceres
(Prof. Roitier Campos Gonçalves).

O cenário simula a separação da rede de uma arena parceira da **Kovenza Sports**
em três zonas, com um firewall Linux no meio aplicando **política `DROP` por
padrão** e liberações explícitas.

> **Isolamento:** este é um ambiente de laboratório autocontido. Nenhum arquivo,
> endpoint ou credencial do sistema Kovenza Sports real é utilizado, importado ou
> referenciado aqui. O Kovenza entra apenas como tema do estudo de caso.

---

## Como executar

Pré-requisitos: **Docker** e **Docker Compose** (v2). Testado no Docker Desktop
para Windows.

```sh
docker compose up -d --build
```

É só isso. As regras do firewall são aplicadas automaticamente na subida, pelo
`ENTRYPOINT` do contêiner `fw-kovenza` ([firewall/entrypoint.sh](firewall/entrypoint.sh)) —
não existe passo manual.

Conferir que o ambiente subiu:

```sh
docker compose ps
docker compose logs fw-kovenza
```

O log do firewall imprime as seis etapas da aplicação da política e termina com
a chain `FORWARD` completa.

### Rodar os testes

```sh
sh scripts/testes-positivos.sh    # 3 testes: tráfego legítimo deve passar
sh scripts/testes-negativos.sh    # 4 testes: tráfego indevido deve ser barrado
```

No Windows, use **Git Bash** ou **WSL**. Os scripts rodam no host (chamam
`docker compose exec`), não dentro dos contêineres.

### Derrubar o ambiente

```sh
docker compose down -v
```

---

## Topologia

```
        rede_arena 172.28.10.0/24          rede_dmz 172.28.20.0/24
     ┌──────────────────────────┐       ┌──────────────────────────────┐
     │ estacao-recepcao         │       │ edge-captura   .20.10 :8080  │
     │            172.28.10.10  │       │ camera-rtsp    .20.20 :554   │
     └────────────┬─────────────┘       │ db-local       .20.30 :5432  │
                  │                     └───────────────┬──────────────┘
            .10.254│                                     │.20.254
                  └──────────┐             ┌─────────────┘
                             ▼             ▼
                      ┌────────────────────────────┐
                      │        fw-kovenza          │
                      │  política FORWARD = DROP   │
                      └─────────────┬──────────────┘
                                    │.30.254
                      ┌─────────────┴────────────────┐
                      │ rede_nuvem 172.28.30.0/24    │
                      │ nuvem-supabase .30.10 :443   │
                      │ nuvem-rtmp     .30.20 :1935  │
                      └──────────────────────────────┘
```

Diagrama em Mermaid: [docs/diagrama-rede.md](docs/diagrama-rede.md)

| Contêiner | Zona | IP | Papel |
|---|---|---|---|
| `fw-kovenza` | todas as três | `.10.254` / `.20.254` / `.30.254` | Firewall e roteador |
| `estacao-recepcao` | Arena | `172.28.10.10` | Computador da recepção/caixa |
| `edge-captura` | DMZ | `172.28.20.10` | Mini-PC de captura (painel em 8080) |
| `camera-rtsp` | DMZ | `172.28.20.20` | Câmera IP (listener em 554) |
| `db-local` | DMZ | `172.28.20.30` | Banco local (Postgres 5432) |
| `nuvem-supabase` | Nuvem | `172.28.30.10` | API do Supabase (HTTPS 443) |
| `nuvem-rtmp` | Nuvem | `172.28.30.20` | Ingestão do YouTube (1935) |

---

## Três coisas que parecem erro e não são

### 1. Os testes usam **IP**, não nome de contêiner

O DNS embutido do Docker só resolve nomes **dentro da mesma rede**. A
`estacao-recepcao` está em `rede_arena` e o `edge-captura` em `rede_dmz` — a
estação simplesmente **não resolve** `edge-captura`.

Isso não é defeito: é consequência direta da segmentação. Todo teste que cruza
zonas usa endereço IP. É também por isso que os IPs são fixos (`ipv4_address`
no Compose): as regras do `iptables` e as rotas estáticas referenciam
endereços, e com IP dinâmico o ambiente quebraria a cada `up`.

### 2. O `curl` para a nuvem usa `-k`

O `nuvem-supabase` serve HTTPS com **certificado autoassinado**, gerado no build
da imagem por [nuvem/gerar-cert.sh](nuvem/gerar-cert.sh). Nenhuma autoridade
certificadora conhecida o assinou, então o `curl` recusaria a conexão sem o `-k`.

O `-k` desliga a validação da cadeia, não o TLS: o tráfego continua cifrado. O
material de chave não é versionado (ver [.gitignore](.gitignore)) — cada build
gera o seu.

### 3. As linhas de `LOG` podem não aparecer

A última regra da chain `FORWARD` é um `LOG` com prefixo `KOVENZA-FW-DROP:`.
No Docker Desktop para Windows o log do kernel não chega ao `dmesg` do
contêiner, então **as linhas podem não ser visíveis**.

A regra continua valendo como demonstração, e o que serve de prova é o
**contador de pacotes**:

```sh
docker compose exec fw-kovenza iptables -L FORWARD -v -n --line-numbers
```

---

## Por que o tráfego realmente passa pelo firewall

Esta é a parte que decide se o laboratório funciona por desenho ou por acaso.

No Docker, contêineres da **mesma** bridge conversam direto, sem gateway nenhum.
Se estação e DMZ estivessem na mesma rede, o firewall seria decorativo: o
tráfego nunca o atravessaria e os testes "passariam" pelo motivo errado.

Aqui cada zona é uma bridge separada e **só o `fw-kovenza` participa das três**.
Isso resolve o problema, mas cria o próximo: por padrão as zonas não se enxergam,
porque não há rota entre elas. A solução é uma **rota estática em cada contêiner
não-firewall**, instalada por [scripts/rotas.sh](scripts/rotas.sh) na subida:

```sh
# dentro de estacao-recepcao
ip route add 172.28.20.0/24 via 172.28.10.254
ip route add 172.28.30.0/24 via 172.28.10.254
```

Uma rota `/24` é mais específica que a rota default, portanto vence na tabela de
roteamento e o pacote sobe para o firewall. Por isso **todos** os contêineres
têm `cap_add: [NET_ADMIN]`, não só o firewall.

### E como se prova isso?

Um teste negativo pode falhar por dois motivos opostos e visualmente idênticos:
o firewall bloqueou, ou **não havia rota** e o pacote nunca saiu.

O [scripts/testes-negativos.sh](scripts/testes-negativos.sh) distingue os dois:
antes de cada teste ele zera os contadores (`iptables -Z FORWARD`), roda o
teste, e confere se a regra de `DROP` correspondente contabilizou pacote.

- Conexão falhou **e** contador > 0 → bloqueio **pelo firewall**. Aprovado.
- Conexão falhou **e** contador = 0 → o pacote não chegou ao firewall; a
  segmentação está funcionando por acidente. **Reprovado**, com aviso explícito.

---

## Matriz de regras

| # | Origem | Destino | Porta/Protocolo | Ação |
|---|---|---|---|---|
| 1 | Rede Arena | `edge-captura` | TCP 8080 | **ACCEPT** |
| 2 | Rede Arena | `camera-rtsp` | TCP 554 | **DROP** |
| 3 | Rede Arena | `db-local` | TCP 5432 | **DROP** |
| 4 | `edge-captura` | `nuvem-supabase` | TCP 443 | **ACCEPT** |
| 5 | `edge-captura` | `nuvem-rtmp` | TCP 1935 | **ACCEPT** |
| 6 | `edge-captura` | Rede Arena | qualquer | **DROP** |
| 7 | `camera-rtsp` | Nuvem | qualquer | **DROP** |
| 8 | `camera-rtsp` | `edge-captura` | TCP 554 | **ACCEPT** |
| 9 | Qualquer | Qualquer | qualquer | **DROP** |

As justificativas de negócio de cada regra estão em
[docs/RELATORIO.md](docs/RELATORIO.md#3-matriz-de-regras-de-segurança).

---

## Estrutura do repositório

```
.
├── README.md                     # este arquivo
├── docker-compose.yml            # redes, IPs fixos, capabilities, sysctls
├── .gitignore
├── .gitattributes                # força LF nos .sh (ver nota abaixo)
├── firewall/
│   ├── Dockerfile
│   └── entrypoint.sh             # política DROP + matriz de regras
├── estacao/
│   └── Dockerfile                # imagem de ferramentas Alpine
├── edge/
│   ├── Dockerfile
│   ├── entrypoint.sh             # rotas estáticas + nginx
│   ├── nginx.conf
│   └── html/health.json
├── db/
│   ├── Dockerfile                # postgres:16-alpine + iproute2
│   └── entrypoint.sh
├── nuvem/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   ├── nginx-tls.conf
│   └── gerar-cert.sh             # certificado autoassinado (no build)
├── scripts/
│   ├── rotas.sh                  # rotas estáticas das zonas
│   ├── testes-positivos.sh
│   └── testes-negativos.sh
└── docs/
    ├── RELATORIO.md              # documento descritivo entregue
    └── diagrama-rede.md          # topologia em Mermaid
```

**Nota sobre `.gitattributes`:** os scripts precisam de terminador de linha LF.
Sem essa configuração, um `git clone` no Windows gravaria CRLF e o shell do
Alpine falharia com `no such file or directory` na linha do shebang.

**Nota sobre a imagem de ferramentas:** `estacao-recepcao`, `camera-rtsp` e
`nuvem-rtmp` compartilham a mesma imagem Alpine ([estacao/Dockerfile](estacao/Dockerfile)),
porque os três são "um host Linux mínimo com ferramentas de rede". O papel de
cada um é definido pelo `command` no Compose.

---

## Senhas e credenciais

A senha do `db-local` está em claro no [docker-compose.yml](docker-compose.yml)
(`laboratorio_descartavel`). É **descartável e exclusiva deste laboratório** —
o `postgres:16-alpine` não sobe sem `POSTGRES_PASSWORD`, e deixá-la visível é
mais honesto, num trabalho acadêmico, que simular um gerenciamento de segredos
que não existe aqui.

Nenhuma credencial real do Kovenza Sports aparece em qualquer ponto deste
repositório.
