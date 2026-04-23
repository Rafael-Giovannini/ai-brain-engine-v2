---
description: "Sobe a stack Docker do workspace (Mongo/Redis/API ou harness) e roda smoke + E2E via curl contra os endpoints definidos, validando respostas. Usage: /smoke-test <workspace> [--compose <file>] [--feature <dir>] [--no-publish] [--teardown] [--keep-up]"
---

## User Input

```text
$ARGUMENTS
```

## Goal

Transformar a feature em desenvolvimento num **smoke + E2E executavel contra Docker real**, como se estivesse publicado. Subir a stack, seed de dados, exercitar os endpoints via `curl`, validar respostas e produzir um relatorio objetivo. Tudo local, efemero, repetivel.

## Flags suportadas

- `<workspace>` (posicional, obrigatorio) — nome do projeto dentro de `workspace/<name>`.
- `--compose <file>` — arquivo docker-compose a usar. Default: `docker-compose.smoke.yml` se existir; senao `docker-compose.yml`.
- `--feature <dir>` — diretorio da feature em `specs/` de onde extrair cenarios (CA-xx) e exemplos. Default: ultima feature modificada.
- `--no-publish` — pula build/publish local (usa imagem existente).
- `--teardown` — apenas derruba a stack e sai (sem subir/testar).
- `--keep-up` (default) — mantem a stack de pe ao final; usuario encerra com `docker compose down` quando quiser.
- `--down-after` — derruba a stack ao final dos testes.

## Regras invariantes

1. **Nunca usar `ASPNETCORE_ENVIRONMENT=Development`** em projetos .NET deste motor — cai em configs PRD via SonarVault. Usar `Local` + `appsettings.Local.json`. (Memoria do usuario.)
2. **Nao imprimir tokens, senhas ou conexoes com secrets reais** no log. Redigir com `***`.
3. **Nao modificar codigo-fonte** para fazer o smoke passar. Se algo nao bate, reportar como finding.
4. **Nao commitar** nada durante a skill. Se criar arquivos auxiliares (ex.: `tmp/smoke.sh`), colocar em `/tmp/` ou dentro de `.gitignore`-ed paths.
5. **Timeout razoavel** para healthcheck (ate 90s) — se nao subir, coletar `docker compose logs` dos servicos unhealthy e abortar.

## Instructions

### 1. Resolver workspace e artefatos

- `WORKSPACE_DIR = workspace/<name>` — abortar se nao existir.
- `COMPOSE_FILE` — resolver ordem: `--compose` flag > `docker-compose.smoke.yml` > `docker-compose.yml`. Abortar se nenhum existir.
- `FEATURE_DIR` — resolver: `--feature` flag > detecta `specs/` e escolhe a entrada mais recentemente modificada.
- Detectar stack tech:
  - `*.csproj` → .NET
  - `package.json` → Node
  - `build.gradle` → JVM
  - Outros → generico
- Em projetos .NET, localizar o `TestHarness` em `test/Harness/*.TestHarness/*.csproj` (se existir) — e o alvo preferencial para smoke pois ja possui stubs para dependencias externas.

### 2. Validar Docker

```bash
docker version --format "{{.Server.Version}}"
```

- Se falhar, orientar a iniciar o Docker Desktop.
- Checar se `docker compose` esta disponivel (versao 2+).

### 3. Modo teardown (se `--teardown`)

```bash
docker compose -f <COMPOSE_FILE> down -v
```
- Remover volumes nomeados da stack se existirem.
- Terminar aqui.

### 4. Publish/Build local (se nao `--no-publish`)

- **.NET + TestHarness**:
  ```bash
  dotnet publish <test/Harness/*.TestHarness/*.csproj> \
    -c Release \
    -o <test/Harness/*.TestHarness/publish> \
    -p:UseAppHost=false \
    --nologo --verbosity quiet
  ```
  - Isso evita PAT de feeds privados (Azure DevOps) no build Docker, pois `Dockerfile.local` so copia o `publish/`.
  - Se o compose usa Dockerfile que depende de PAT (precisa restore no Docker), checar se existe `$PAT` env e avisar se ausente.

- **Node**: `npm ci && npm run build` (se aplicavel).
- **JVM**: `./gradlew assemble`.

### 5. Subir stack

```bash
docker compose -f <COMPOSE_FILE> up -d --build
```

- Aguardar healthchecks ficarem `healthy` (loop com `docker compose ps --format json` + `jq`/`node`).
- Timeout: 90s. Se ainda unhealthy:
  ```bash
  docker compose -f <COMPOSE_FILE> logs --tail 80 <servico>
  ```
  - Coletar logs do servico unhealthy, reportar, abortar.

### 6. Descobrir endpoints

Preferencia (em ordem):
1. **Index route** (`GET /`) do harness, se retornar uma lista (padrao dos harnesses deste motor).
2. **Swagger**: `GET /swagger/v1/swagger.json` ou `GET /swagger` para listar rotas.
3. **Contratos** em `specs/<feature>/contracts/*.md` — extrair `POST /path`, `GET /path` etc.

Registrar em memoria o BASE (`http://localhost:<port>`) — porta detectada do `COMPOSE_FILE`.

### 7. Gerar plano de smoke

Para cada CA em `spec.md` (secao "Criterios de Aceite") e cada cenario em `specs/<feature>/quickstart.md` (secao "Verificacoes rapidas" ou "Cenarios de teste"):

- Identificar:
  - **Setup** necessario (seed de dados, reset, configs dinamicas).
  - **Request** (metodo + path + body).
  - **Assertion** (codigo HTTP esperado; campos/valores-chave da response).
- Se o harness expoe rotas utilitarias (`/testharness/reset-*`, `/testharness/set-*`), usa-las para controlar estado determinista.
- Priorizar cenarios marcados como **P1** ou com `⭐` no spec.

Produzir o plano (JSON interno) e **exibir ao usuario** antes de executar:

```
Plano de smoke tests (5 cenarios):
  1. [Setup]   reset-mongo + set-cpp
  2. [CA-12]   POST /availability  sem regras -> 404
  3. [CA-01]   Seed Markup + POST /availability -> 200, SellingPrice=920
  ...
```

### 8. Executar

Para cada cenario:

```bash
RESP=$(curl -sS -X <METHOD> <BASE><PATH> \
  -H "Content-Type: application/json" \
  -d '<BODY>' \
  -w "\n%{http_code}|%{time_total}")
```

- Separar response body do status code (ultima linha com `|`).
- Validar:
  - Status code = esperado.
  - Campos-chave batem (comparacao numerica tolerante a `±0.01` para valores monetarios).
- Se falhar, **continuar rodando** os demais cenarios (nao abortar) e coletar todas as falhas.

### 9. Relatorio final

Apresentar tabela resumo:

```
| # | Cenario         | HTTP | Latencia | Resultado  |
|---|-----------------|------|----------|------------|
| 1 | CA-12 sem regras| 404  | 8 ms     | PASS       |
| 2 | CA-01 Markup    | 200  | 10 ms    | PASS       |
| 3 | CA-13 3 margens | 200  | 11 ms    | FAIL       |
```

- Para PASS: mostrar 1-2 campos chave do JSON (ex.: `SellingPrice=920`).
- Para FAIL: mostrar response body + diff do esperado.
- Incluir contagem: `N/M PASS (X%)`.

### 10. Teardown (condicional)

- Se `--down-after`: rodar `docker compose -f <COMPOSE_FILE> down` e sair.
- Default `--keep-up`: deixar a stack no ar, imprimir:
  ```
  Stack continua em http://localhost:<port> — para derrubar:
    docker compose -f <file> down
  ```

## Casos de borda

- **Workspace sem docker-compose**: reportar "projeto nao tem stack Docker configurada" e oferecer criar um template (nao gerar automaticamente).
- **Workspace sem `specs/<feature>/`**: cair para modo "smoke cru" — rodar so `GET /` + listar endpoints via swagger, sem assertions funcionais.
- **Portas conflitantes** (5080, 27017, 6379 em uso): detectar via `docker ps` e avisar. Nao tentar mapear pra porta alternativa automaticamente.
- **Imagem Docker precisa de PAT**: se `Dockerfile` faz NuGet restore de feed privado, conferir `$PAT` env. Se ausente, sugerir usar `Dockerfile.local` + `dotnet publish` local (padrao deste motor).
- **Healthcheck nunca fica healthy**: coletar logs dos containers nao-healthy (stdout + stderr), reportar em detalhe.
- **Endpoint utilitario ausente**: se o harness nao expoe `/testharness/reset-*`, seed direto via `docker exec mongo mongosh` ou via endpoint admin existente.
- **CPP/margens com valor inesperado**: reportar como divergencia (nao como falha da skill). Lembrar que CPP neste motor e multiplicador, nao taxa inversa (ver findings do `/validate`).

## Exemplo de uso

```
/smoke-test product-princing-services
# descobre docker-compose.smoke.yml, publish, sobe stack, roda CA-12 + CA-01 + CA-13, reporta

/smoke-test product-princing-services --teardown
# so derruba

/smoke-test product-princing-services --feature specs/001-margin-calc-engine --down-after
# roda os cenarios da feature especifica e derruba no final

/smoke-test product-princing-services --no-publish
# reaproveita imagem ja buildada
```

## Notas de uso

- A skill **nao modifica** codigo-fonte nem commita.
- **Nao sobrescrever** arquivos `.env` do workspace.
- Preferir chamar endpoints utilitarios (`/testharness/*`) do harness quando existirem — sao o jeito oficial de controlar estado local.
- Para projetos que precisam de servicos externos reais (PartnerHub, CPP real, Auth real), documentar no output que esses foram **stubados** no harness.
- Linguagem do output: PT-BR (default do motor). Se o projeto seguir outra convencao, inferir dos logs recentes do repo.
