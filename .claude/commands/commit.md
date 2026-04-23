---
description: "Cria commits atomicos com mensagens semanticas (feat/fix/chore/test/refactor/docs) a partir do estado atual do git. Por default exclui arquivos .md. Usage: /commit [--with-md] [--single] [--dry-run]"
---

## User Input

```text
$ARGUMENTS
```

## Goal

Transformar o estado atual do working tree (arquivos staged, modificados, novos) em uma sequencia de commits **atomicos** com mensagens **semanticas** seguindo a convencao do repositorio. Nunca referenciar IA na mensagem. Por default excluir arquivos `.md` do commit.

## Flags suportadas

- `--with-md` — inclui arquivos `.md` nos commits.
- `--single` — agrupa tudo em um unico commit em vez de multiplos atomicos.
- `--dry-run` — gera e mostra o plano, mas nao executa `git commit`.

## Regras invariantes

1. **Sem referencia a IA** — mensagens nunca mencionam Claude, AI, agente, LLM, etc. Sem `Co-Authored-By` de bots.
2. **Sem `.md` por default** — arquivos terminando em `.md` ficam untracked a menos que `--with-md` seja passado.
3. **Commits atomicos** — cada commit representa uma mudanca logica coesa; cada commit idealmente deixa o repo compilavel.
4. **Mensagens semanticas** — primeiro token: `feat|fix|chore|test|refactor|docs|perf|build|ci|style`. Escopo opcional entre parenteses: `feat(auth): ...`, `chore(infra): ...`.
5. **HEREDOC para mensagens multiline** — usar sempre `git commit -m "$(cat <<'EOF' ... EOF )"` para preservar formatacao e escapar caracteres.
6. **Sem `git add -A` e sem `git add .`** — sempre listar arquivos explicitamente (evita incluir segredos, .env, logs acidentais).
7. **Sem `--no-verify`** — respeitar hooks de commit.
8. **Nunca `git amend`** em commits ja publicados.
9. **Sem push automatico** — skill apenas commita localmente; push e decisao do usuario.

## Instructions

1. **Verificar estado**:
   ```bash
   git status --short
   git diff --stat
   git log --oneline -5
   ```
   - Se nao houver nenhuma mudanca, abortar com mensagem clara.
   - Observar a branch atual (`git branch --show-current`); se for `main`/`master`, avisar e pedir confirmacao.

2. **Inspecionar convencoes do repo**:
   - Rodar `git log --oneline -20` e identificar o padrao de mensagens predominante (com/sem escopo, prefixos usados, idioma).
   - Respeitar o padrao observado. Se o repo usa PT-BR nas mensagens, manter PT-BR; se usa EN, usar EN.

3. **Classificar arquivos por camada/intencao**:
   - Agrupar mudancas em "buckets" que se tornarao commits atomicos. Heuristica:
     - **Modelos de dominio / contratos / interfaces** → primeiro commit
     - **Implementacao de servicos puros** → seguinte
     - **Infra (repositorios, clientes HTTP, DI)** → seguinte
     - **Use cases / handlers / controllers / integracao** → seguinte
     - **Testes** → em commit separado, a menos que afetem o mesmo arquivo ja modificado em outro bucket
     - **Scripts de pipeline / migrations / config** → `chore(infra|config|...)`
     - **Documentacao `.md`** → ignorar por default; incluir em `docs(...)` apenas com `--with-md`.
   - Cada bucket vira um commit. Se um arquivo deveria logicamente ir em dois buckets mas so pode ficar em um (sem `git add -p`), escolher o bucket onde a mudanca "pesa" mais e mencionar brevemente na mensagem.

4. **Gerar plano de commits** (estrutura JSON interna):
   ```json
   [
     { "type": "feat", "scope": "auth", "subject": "adiciona ...", "files": [...], "body": "opcional" },
     { "type": "test", "scope": "auth", "subject": "cobre ...", "files": [...] }
   ]
   ```
   - Ordem: garantir que cada commit deixa o repo compilavel quando possivel (modelos antes de servicos, servicos antes de use cases, etc).
   - Mensagens: assunto <= 72 chars, imperativo, sem ponto final. Corpo opcional so quando o "porque" nao e obvio pelo diff.

5. **Apresentar plano ao usuario** (antes de qualquer commit):
   - Listar: numero de commits, bucket de cada um, mensagem do assunto, arquivos afetados.
   - Destacar arquivos `.md` que serao omitidos (ou incluidos com `--with-md`).
   - Se `--dry-run`, parar aqui e retornar o plano formatado.

6. **Executar commits** (se nao for `--dry-run`):
   - Para cada item do plano:
     1. `git add <arquivo1> <arquivo2> ...` (lista explicita, sem wildcards amplos).
     2. `git commit -m "$(cat <<'EOF'\n<type>(<scope>): <subject>\n\n<body opcional>\nEOF\n)"`.
     3. Checar `echo $?` — se falhar (ex.: pre-commit hook), parar e reportar.
   - Evitar `git add` de arquivos `.md` a menos que `--with-md`.
   - **Nunca** adicionar `.env`, `*.pem`, `*.key`, `credentials.*`, `secrets.*` — se aparecerem em `git status`, alertar e pular.

7. **Validar resultado**:
   - `git log --oneline -<N>` onde N e o numero de commits criados.
   - `git status --short` deve mostrar apenas o que foi intencionalmente deixado de fora (`.md` ou arquivos ignorados).

8. **Reportar**:
   - Lista de commits criados (hash + subject).
   - Arquivos deixados untracked (se houver).
   - Nao fazer push — apenas sugerir `git push` como proximo passo se a branch tiver upstream.

## Exemplo de mensagem de commit (referencia)

```text
feat(margin-motor): implementa MarginCalculationService

Calcula Markup, Apropriacao e Desconto suportando os 5 modos de
ApplicabilityType. Aplica clamp anti-negativo e expoe
DominantMarginPercentage para manter retrocompatibilidade do campo
MarginValue no DTO. Registra o servico como Scoped no DI.
```

## Casos de borda

- **Repo sem commits anteriores**: usar mensagens sem escopo predefinido; primeiro commit pode ser `chore: initial commit` ou `feat: scaffolding inicial`.
- **Conflito entre buckets logicos no mesmo arquivo**: colocar o arquivo inteiro no bucket onde a mudanca predomina e anotar no corpo do commit.
- **Mais de 10 commits no plano**: considerar agrupar buckets adjacentes ou recomendar `--single` se fizer sentido.
- **Arquivo `.md` que e changelog/release-notes vital**: mesmo com default sem `.md`, perguntar antes de deixar de fora.
- **Hook de pre-commit falha**: reportar erro integral, **nao** retentar com `--no-verify`, oferecer diagnostico.
- **Detencao de segredos**: se `git diff` mostra strings que parecem API keys, tokens ou senhas, abortar e reportar antes de commitar.

## Notas de uso

- A skill **nao empurra** (`git push`). Push e sempre decisao manual.
- A skill **nao cria branches**. Opera na branch atual.
- Se a branch atual for `main`/`master`, avisar o usuario e pedir confirmacao explicita antes de prosseguir.
- Mensagens em PT-BR por default quando o projeto seguir essa convencao; seguir o idioma observado nos commits recentes.
