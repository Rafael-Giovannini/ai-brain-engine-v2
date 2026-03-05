# AI-BRAIN ENGINE v2
## PROTOCOLO DE GOVERNANCA AGENTICA

Motor de execucao autonomo que transforma especificacoes em codigo funcional atraves de agentes AI coordenados.

---

## ARQUITETURA DO MOTOR

| Camada | Ferramenta | Funcao |
|--------|-----------|--------|
| Estrategia | BMAD Method | Decomposicao de tarefas por personas (Analyst/PM/Architect/Developer/Scrum) |
| Especificacao | Spec-Kit | Fonte da verdade. O codigo espelha a spec |
| Execucao | Ralph | Loop TDD autonomo. Um task por loop |
| Controle | Skinner | Worktree isolado, auto-commit, auto-revert, circuit breaker |
| Hooks | Claude Code Hooks | PreToolUse/PostToolUse/SessionStart nativos |
| Observabilidade | Langfuse | Tracing de custo, latencia e tokens por chamada LLM |
| Memoria | VIGIL Pattern | Skinner aprende com erros passados, adapta prompts |
| Arquitetura | ArchUnit | Testes de arquitetura como gate no pipeline |
| Mutacao | MutaHunter | Mutation testing para verificar efetividade dos testes |
| Autoria | Git AI | Rastreio AI vs humano por linha |
| Review | Code Review Plugin | Review automatico pre-merge com score |

---

## WORKFLOW DE EXECUCAO

### Ciclo de Vida Completo

| Fase | Responsavel | Comando | Funcao |
|------|-------------|---------|--------|
| 1. Analise | BMAD | `/bmad:product-brief` | Definir visao e escopo |
| 2. Planejamento | BMAD | `/bmad:prd` | Requisitos funcionais e nao-funcionais |
| 3. Arquitetura | BMAD | `/bmad:architecture` | Design de arquitetura (se aplicavel) |
| 4. Sprint | BMAD | `/bmad:sprint-planning` | Decompor epics em stories |
| 5. Especificacao | Spec-Kit | `/speckit.specify` | Gerar spec tecnica da feature/story |
| 6. Execucao | Ralph | `/ralph-loop` | Loop TDD ate 100% dos testes |
| 7. Controle | Skinner | (automatico) | Commit atomico + validacao |
| 8. Review | Code Review | (automatico) | Review pre-merge com gate |

### Ciclo de Vida da Task

1. **Especificacao:** Gere ou atualize `specs/` usando `/speckit.specify`. A spec e a fonte da verdade.
2. **Loop Ralph:** Inicie `/ralph-loop`. Criterio de parada: 100% dos testes passando.
3. **Skinner Enforcement:** Commits atomicos automaticos. Reversao se erro circular.
4. **Review Gate:** Code review automatico antes do merge. Score minimo configuravel.

---

## REGRAS DE OURO (SKINNER LAWS)

1. **No Spec, No Code** — Nenhuma linha sem spec ativa
2. **Atomicidade** — Commits pequenos, descritivos, funcionais
3. **Modularidade** — Reutilizar antes de criar (Grep/Glob primeiro)
4. **Verificabilidade** — Todo codigo acompanha teste
5. **Observabilidade** — Toda acao rastreada (Langfuse)
6. **Aprendizado** — Skinner evolui com o tempo (VIGIL)

---

## COMANDOS DO SISTEMA

### BMAD (Estrategia e Planejamento)
- `/bmad:product-brief` — Visao do produto (Phase 1)
- `/bmad:prd` — Requisitos (Phase 2)
- `/bmad:architecture` — Arquitetura (Phase 3)
- `/bmad:sprint-planning` — Sprint e stories (Phase 4)
- `/bmad:create-story` — Criar story detalhada
- `/bmad:dev-story` — Implementar story
- `/bmad:workflow-status` — Ver progresso
- `/bmad:brainstorm` — Brainstorming estruturado
- `/bmad:research` — Pesquisa
- `/bmad:tech-spec` — Spec tecnica

### Spec-Kit (Especificacao Tecnica)
- `/speckit.specify` — Gerar spec tecnica
- `/speckit.plan` — Planejar implementacao
- `/speckit.tasks` — Gerar tasks
- `/speckit.implement` — Executar tasks
- `/speckit.clarify` — Clarificar spec
- `/speckit.analyze` — Analise de consistencia

### Motor (Execucao e Controle)
- `/ralph-loop` — Loop TDD autonomo com Skinner enforcement
- `/validate` — Validacao 8+ passes (doc consistency, entities, API, FRs, code quality, BMAD, Ralph config)
- `/skinner-status` — Status de worktrees, branches, logs

---

## ESTRUTURA DE DIRETORIOS

```
ai-brain-engine-v2/
  CLAUDE.md                    # Este arquivo — governanca do motor
  engine.yaml                  # Config central — flags por camada
  ralph-loop.sh                # Orquestrador principal
  validate.sh                  # Validacao 8+ passes
  docker-compose.yml           # Langfuse self-hosted
  .claude/
    settings.json              # Permissoes Claude Code
    hooks/                     # Hooks nativos (PreToolUse, PostToolUse, SessionStart)
    commands/                  # Skills custom (ralph-loop, validate, skinner-status)
  .specify/                    # Spec-Kit templates e scripts
  .ralph/
    PROMPT.md                  # Template de prompt para Ralph (generico)
    AGENT.md                   # Template de agent config (generico)
    fix_plan.md                # Template de task tracker
  .skinner/
    skinner.sh                 # Enforcement engine
    memory/                    # Memoria comportamental (VIGIL)
    logs/                      # Logs de auditoria por sessao
  docs/                        # BMAD docs (briefs, PRDs, arquitetura)
  specs/                       # Fonte da verdade (specs, plans, data-models)
  src/                         # Codigo do projeto
  tests/
    unit/                      # Testes unitarios
    architecture/              # Testes ArchUnit / dependency-cruiser
    mutation/                  # Config MutaHunter
```

---

## CONFIGURACAO DE CAMADAS

Cada camada e ativavel/desativavel via `engine.yaml`. Ver arquivo para detalhes.

**Default (apenas essenciais):**
- BMAD, Spec-Kit, Ralph, Skinner: sempre ativos
- Hooks: ativo
- Langfuse: ativo (requer Docker)
- VIGIL: ativo
- ArchUnit, MutaHunter, Git AI, Code Review: desativados por default

---

## LINGUAGEM

- Docs e reports em PT-BR
- Termos tecnicos (nomes de arquivo, comandos, severity levels) em ingles
- Codigo e comentarios na linguagem do projeto
