# PROMPT: AI-Brain Engine v2 — Motor de Execucao Autonomo

## Contexto

Tenho um motor de execucao autonomo chamado AI-Brain Engine que transforma especificacoes em codigo funcional atraves de agentes AI coordenados. A v1 ja esta funcional com 4 camadas:

1. **BMAD Method** (estrategia) — personas AI (Analyst, PM, Architect, Scrum Master) que decompem tarefas. Instalado via `npx bmad-method init`. Repo: `bmad-code-org/BMAD-METHOD`
2. **Spec-Kit** (especificacao) — toolkit spec-driven do GitHub. Gera spec.md, plan.md, data-model.md, tasks.md. Instalado via `uvx --from git+https://github.com/github/spec-kit.git specify init`. Repo: `github/spec-kit`
3. **Ralph** (execucao TDD) — loop autonomo que pega tasks e implementa com TDD. Base do `frankbria/ralph-claude-code`, mas customizamos bastante (.ralph/PROMPT.md, AGENT.md, fix_plan.md, .ralphrc com config por workspace)
4. **Skinner** (supervisor/enforcement) — 100% custom, ~800 linhas de shell. Inspirado em `automateyournetwork/PrincipalSkinner` mas muito mais robusto. Faz: worktree isolado, auto-commit apos testes passarem, auto-revert em erro circular, circuit breaker (sem progresso N loops / mesmo erro N vezes), logs de auditoria por sessao

### Skills Custom (v1)
- `/ralph-loop` — orquestra TDD + Skinner + worktree + merge + re-validate
- `/validate` — 8 passes de validacao (doc consistency, entities, API contracts, FR traceability, scenario coverage, code quality/OWASP, BMAD docs, Ralph config)
- `/skinner-status` — status de worktrees, branches, logs

### Problemas da v1
- Skinner roda como script externo, nao integrado com hooks nativos do Claude Code
- Sem observabilidade (nao sabemos custo, latencia, taxa de erro por loop)
- Sem rastreio de autoria AI vs humano
- Sem enforcement de arquitetura por testes (clean architecture so checado manualmente)
- Sem mutation testing (testes do Ralph podem ser fracos)
- Sem review automatico de PR antes do merge
- Sem branch exploratorio para situacoes incertas (hoje e binario: commita ou reverte)
- Sem memoria comportamental (Skinner nao aprende com erros passados)
- Roda um Ralph por vez (sem paralelismo)

---

## Objetivo

Criar o **AI-Brain Engine v2** — um novo projeto que incorpora todo o v1 e adiciona as seguintes camadas/ferramentas:

### Camada 1: Hooks Nativos do Claude Code
Migrar parte da logica do Skinner para hooks nativos:
- **PreToolUse**: bloquear Write/Edit sem teste correspondente, proteger arquivos criticos (spec.md, CLAUDE.md)
- **PostToolUse**: auto-lint/format apos cada Edit, validacao rapida
- **SessionStart**: carregar contexto do workspace, verificar estado do worktree
- **WorktreeCreate/WorktreeRemove**: integrar com Skinner
Ref: https://docs.anthropic.com/en/docs/claude-code/hooks

### Camada 2: Code Review Plugin (Anthropic oficial)
Integrar o plugin oficial de code review que lanca 4-5 subagentes em paralelo auditando o diff:
- Compliance com CLAUDE.md
- Bug detection
- Git history analysis
- Code comment verification
- Score 0-100, threshold configuravel
Ref: `anthropics/claude-code` → plugins/code-review

### Camada 3: Git AI — Rastreio de Autoria
Instalar e integrar Git AI para rastrear qual agente/model escreveu cada linha:
- Armazena em `.git/ai/`
- Authorship logs em Git Notes
- Sobrevive rebases, merges, squashes
- Integracao nativa com Claude Code
Ref: `git-ai-project/git-ai` | https://usegitai.com/

### Camada 4: ArchUnit — Testes de Arquitetura
Adicionar testes de arquitetura que rodam como JUnit:
- "domain nao pode importar infrastructure"
- "nenhuma classe > 300 linhas"
- "use cases devem estar em domain/"
- Skinner roda como gate — se Ralph violar, teste falha
Ref: `TNG/ArchUnit` (Java/Kotlin) | `TNG/ArchUnitNET` (C#) | `sverweij/dependency-cruiser` (JS/TS)

### Camada 5: Langfuse — Observabilidade
Instrumentar cada chamada LLM do Ralph com tracing:
- Custo por loop, por story, por workspace
- Latencia e tokens por chamada
- Taxa de erro e circuit breaker trips
- Dashboard para analise historica
- Self-hostable via Docker
Ref: `langfuse/langfuse`

### Camada 6: MutaHunter — Mutation Testing
Apos Ralph escrever testes, verificar se sao efetivos:
- Injetar mutacoes no codigo e checar se testes falham
- Se mutation score < threshold, Skinner rejeita e manda Ralph reescrever testes
- Language-agnostic
Ref: `codeintegrity-ai/mutahunter`

### Camada 7: VIGIL Pattern — Skinner com Memoria
Implementar memoria comportamental persistente no Skinner:
- Log estruturado de erros por tipo/categoria
- Decay temporal (erros recentes pesam mais)
- Diagnostico Roses/Buds/Thorns
- Adaptar prompts do Ralph baseado em padroes de erro historicos
- Reduzir loops redundantes ao longo do tempo
Ref: Paper VIGIL (arxiv.org/abs/2512.07094)

### Camada 8: Branch Exploratorio
Quando qualidade e incerta (testes passam mas algo parece errado):
- Criar branch exploratorio temporario
- Testar alternativa
- Comparar resultados
- Merge ou abandon com log
Similar ao PrincipalSkinner original mas integrado ao nosso fluxo

### Camada 9: Review Automatico de PR
Integrar CodeRabbit ou usar o plugin oficial de review:
- Rodar automaticamente em cada PR que Ralph gera
- 40+ analyzers (seguranca, performance, style, bugs)
- Parsear resultado como gate no Skinner
Ref: coderabbit.ai (gratis open-source) ou `anthropics/claude-code-security-review`

---

## Estrutura Esperada

```
ai-brain-engine-v2/
  CLAUDE.md                    # Governanca do motor v2
  .claude/
    settings.json
    hooks/                     # Hooks nativos (PreToolUse, PostToolUse, etc)
    commands/                  # Skills custom
      ralph-loop.md
      validate.md
      skinner-status.md
    skills/bmad/               # Personas BMAD
  .specify/                    # Templates Spec-Kit
  .ralph/                      # Config Ralph (PROMPT, AGENT, fix_plan)
  .ralphrc                     # Config por workspace
  .skinner/
    skinner.sh                 # Enforcement engine (atualizado com VIGIL)
    memory/                    # Memoria comportamental persistente
    logs/                      # Logs de auditoria
  .gitai/                      # Config Git AI
  ralph-loop.sh                # Orquestrador
  validate.sh                  # Validacao 8+ passes
  docker-compose.yml           # Langfuse self-hosted
  docs/                        # BMAD docs
  specs/                       # Fonte da verdade
  src/                         # Codigo
  tests/
    unit/                      # Testes unitarios
    architecture/              # Testes ArchUnit
    mutation/                  # Config MutaHunter
```

## Regras

1. **No Spec, No Code** — nenhuma linha sem spec
2. **Atomicidade** — commits pequenos, descritivos, funcionais
3. **Modularidade** — reutilizar antes de criar
4. **Verificabilidade** — todo codigo acompanha teste
5. **Observabilidade** — toda acao rastreada
6. **Aprendizado** — Skinner evolui com o tempo

## Como Comecar

1. Criar o repo/estrutura base
2. Portar o CLAUDE.md atualizado com as novas regras
3. Configurar hooks nativos do Claude Code
4. Portar e evoluir o Skinner com memoria VIGIL
5. Integrar Git AI
6. Configurar Langfuse (docker-compose)
7. Adicionar ArchUnit ao pipeline de testes
8. Integrar MutaHunter
9. Configurar code review plugin
10. Documentar tudo em specs/

## Stack Tecnologico

- **Runtime**: Claude Code CLI (@anthropic-ai/claude-code)
- **Linguagem do motor**: Bash + Claude Code hooks (JSON config)
- **Observabilidade**: Langfuse (Docker) + OpenTelemetry
- **Rastreio**: Git AI
- **Review**: Claude Code Review Plugin + CodeRabbit
- **Testes de arquitetura**: ArchUnit (Kotlin/Java) / dependency-cruiser (JS/TS)
- **Mutation testing**: MutaHunter
- **Versionamento**: Git com worktrees isolados

## Importante

- Manter retrocompatibilidade com projetos existentes (GhostFit, etc)
- O motor deve ser generico — funcionar pra qualquer linguagem/framework
- Cada camada deve ser opcional (flag ou config) — nao obrigar tudo de uma vez
- Priorizar o que funciona localmente sem dependencias externas pagas
- Tudo em PT-BR nos docs e reports
