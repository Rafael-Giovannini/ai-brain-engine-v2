# Product Requirements Document: AI-Brain Engine v2

**Date:** 2026-03-05
**Author:** rafael.giovannini
**Version:** 1.0
**Project Type:** Developer Tooling / Autonomous Execution Engine
**Project Level:** 3 (Large/Complex)
**Status:** Draft

---

## Document Overview

This Product Requirements Document (PRD) defines the functional and non-functional requirements for AI-Brain Engine v2. It serves as the source of truth for what will be built and provides traceability from requirements through implementation.

**Related Documents:**
- Product Brief: docs/product-brief-ai-brain-engine-v2-2026-03-05.md

---

## Executive Summary

O AI-Brain Engine v2 e um motor de execucao autonomo que transforma especificacoes em codigo funcional atraves de agentes AI coordenados. Evolui o v1 (BMAD + Spec-Kit + Ralph + Skinner) adicionando robustez operacional — observabilidade, memoria comportamental, review automatico, rastreio de autoria e enforcement de arquitetura — para que o motor aprenda com seus erros e produza codigo de qualidade crescente ao longo do tempo. Secundariamente, habilita escala via paralelismo e branch exploratorio.

---

## Product Goals

### Business Objectives

1. Reduzir loops redundantes do Ralph em >= 30% via memoria comportamental (VIGIL)
2. Atingir 100% de rastreabilidade de chamadas LLM (Langfuse)
3. Garantir mutation score minimo de 60% em testes gerados pelo Ralph
4. Eliminar merges sem review automatico (zero PRs sem gate de qualidade)
5. Ter autoria AI vs humano rastreavel por linha de codigo
6. Tornar cada camada opcional via flag/config, mantendo retrocompatibilidade com v1
7. Produzir metricas suficientes para demonstrar ROI a stakeholders corporativos

### Success Metrics

- Numero de loops por story (antes vs depois da memoria VIGIL)
- Custo em tokens/USD por story completada
- Mutation score medio dos testes gerados
- % de PRs com review automatico aprovado vs rejeitado
- Tempo medio de resolucao de story (end-to-end)
- Taxa de circuit breaker trips (deve diminuir ao longo do tempo)

---

## Functional Requirements

Functional Requirements (FRs) define **what** the system does - specific features and behaviors.

Each requirement includes:
- **ID**: Unique identifier (FR-001, FR-002, etc.)
- **Priority**: Must Have / Should Have / Could Have (MoSCoW)
- **Description**: What the system should do
- **Acceptance Criteria**: How to verify it's complete

---

### FR-001: Bloquear Write/Edit sem teste correspondente

**Priority:** Must Have

**Description:**
Via PreToolUse hook, o sistema deve bloquear qualquer operacao de Write ou Edit que nao tenha um teste correspondente associado.

**Acceptance Criteria:**
- [ ] Hook PreToolUse intercepta chamadas Write/Edit
- [ ] Verifica existencia de teste para o arquivo sendo modificado
- [ ] Bloqueia a operacao com mensagem clara se teste nao existir
- [ ] Permite bypass configuravel para arquivos de config/docs

**Dependencies:** Nenhuma

---

### FR-002: Proteger arquivos criticos contra edicao

**Priority:** Must Have

**Description:**
Via PreToolUse hook, proteger arquivos criticos (spec.md, CLAUDE.md, configs de producao) contra edicao acidental ou nao autorizada.

**Acceptance Criteria:**
- [ ] Lista de arquivos protegidos configuravel via YAML
- [ ] Hook bloqueia edicao com mensagem explicativa
- [ ] Permite override explicito quando necessario (flag)
- [ ] Log de tentativas de edicao bloqueadas

**Dependencies:** Nenhuma

---

### FR-003: Auto-lint/format apos cada Edit

**Priority:** Should Have

**Description:**
Via PostToolUse hook, executar linter e formatter automaticamente apos cada operacao de Edit.

**Acceptance Criteria:**
- [ ] PostToolUse detecta Edit e executa lint/format
- [ ] Ferramenta de lint/format configuravel por linguagem
- [ ] Execucao em < 2s (NFR-001)
- [ ] Log de correcoes aplicadas

**Dependencies:** FR-001

---

### FR-004: Carregar contexto do workspace no SessionStart

**Priority:** Must Have

**Description:**
No inicio de cada sessao do Claude Code, carregar automaticamente o contexto do workspace: estado do worktree, configuracoes ativas, ultimo estado do Skinner.

**Acceptance Criteria:**
- [ ] SessionStart hook carrega config do workspace
- [ ] Verifica estado do worktree (limpo, dirty, conflitos)
- [ ] Carrega ultimo estado do Skinner (circuit breaker, contadores)
- [ ] Exibe resumo ao usuario

**Dependencies:** Nenhuma

---

### FR-005: Integrar plugin de code review com subagentes

**Priority:** Should Have

**Description:**
Integrar o plugin oficial de code review da Anthropic que lanca 4-5 subagentes em paralelo para auditar o diff (compliance, bugs, git history, comments).

**Acceptance Criteria:**
- [ ] Plugin configurado e funcional
- [ ] 4-5 subagentes executam em paralelo
- [ ] Resultado consolidado com findings por categoria
- [ ] Integracao com pipeline do Skinner

**Dependencies:** FR-004

---

### FR-006: Score de review com threshold configuravel

**Priority:** Should Have

**Description:**
O code review deve gerar um score 0-100. Se abaixo do threshold configuravel, o merge e bloqueado.

**Acceptance Criteria:**
- [ ] Score calculado automaticamente (0-100)
- [ ] Threshold configuravel via YAML (default: 70)
- [ ] Score abaixo do threshold bloqueia merge
- [ ] Log do score e motivos de desconto

**Dependencies:** FR-005

---

### FR-007: Rastrear autoria AI vs humano por linha

**Priority:** Should Have

**Description:**
Integrar Git AI para rastrear qual agente/modelo escreveu cada linha de codigo, armazenando em `.git/ai/`.

**Acceptance Criteria:**
- [ ] Git AI instalado e configurado
- [ ] Cada Write/Edit registra autoria (modelo, agente, timestamp)
- [ ] Dados consultaveis via CLI (git ai blame)
- [ ] Armazenamento em `.git/ai/`

**Dependencies:** Nenhuma

---

### FR-008: Authorship logs em Git Notes

**Priority:** Should Have

**Description:**
Logs de autoria devem ser armazenados em Git Notes para sobreviver operacoes destrutivas (rebase, merge, squash).

**Acceptance Criteria:**
- [ ] Authorship registrado em Git Notes
- [ ] Sobrevive rebase sem perda
- [ ] Sobrevive merge sem perda
- [ ] Sobrevive squash sem perda

**Dependencies:** FR-007

---

### FR-009: Testes de arquitetura como JUnit

**Priority:** Must Have

**Description:**
Adicionar testes de arquitetura executaveis que verificam regras como: "domain nao importa infrastructure", "classes < 300 linhas", "use cases em domain/".

**Acceptance Criteria:**
- [ ] Testes de arquitetura criados e executaveis
- [ ] Regra: domain nao importa infrastructure
- [ ] Regra: nenhuma classe > 300 linhas
- [ ] Regra: use cases devem estar em domain/
- [ ] Regras configuraveis/extensiveis via arquivo de config
- [ ] Ferramenta escolhida por linguagem (ArchUnit, dependency-cruiser)

**Dependencies:** Nenhuma

---

### FR-010: Testes de arquitetura como gate no Skinner

**Priority:** Must Have

**Description:**
O Skinner deve executar testes de arquitetura como gate obrigatorio. Se Ralph violar uma regra de arquitetura, o teste falha e o commit e bloqueado.

**Acceptance Criteria:**
- [ ] Skinner executa testes de arquitetura antes de permitir commit
- [ ] Violacao = falha = commit bloqueado
- [ ] Mensagem de erro clara indicando qual regra foi violada
- [ ] Log da violacao para memoria VIGIL

**Dependencies:** FR-009

---

### FR-011: Instrumentar chamadas LLM com tracing

**Priority:** Must Have

**Description:**
Cada chamada LLM do Ralph deve ser instrumentada com tracing via Langfuse, registrando custo, latencia e tokens.

**Acceptance Criteria:**
- [ ] Toda chamada LLM registrada no Langfuse
- [ ] Custo (USD) calculado por chamada
- [ ] Latencia (ms) registrada por chamada
- [ ] Tokens (input/output) registrados por chamada
- [ ] Zero gaps — 100% de cobertura (NFR-011)

**Dependencies:** FR-013

---

### FR-012: Dashboard de metricas por loop/story/workspace

**Priority:** Must Have

**Description:**
Langfuse deve prover dashboard com metricas agregadas por loop, por story e por workspace para analise historica.

**Acceptance Criteria:**
- [ ] Metricas agregadas por loop individual
- [ ] Metricas agregadas por story completa
- [ ] Metricas agregadas por workspace
- [ ] Visualizacao temporal (tendencias)
- [ ] Exportacao de dados para analise externa

**Dependencies:** FR-011

---

### FR-013: Setup Langfuse self-hosted via Docker

**Priority:** Must Have

**Description:**
Prover docker-compose.yml para rodar Langfuse self-hosted localmente com PostgreSQL e Redis.

**Acceptance Criteria:**
- [ ] docker-compose.yml funcional com Langfuse + PostgreSQL + Redis
- [ ] `docker compose up` inicia tudo sem configuracao manual
- [ ] Dados persistidos em volumes Docker
- [ ] Acessivel em localhost (sem exposicao externa - NFR-010)

**Dependencies:** Nenhuma

---

### FR-014: Executar mutation testing nos testes do Ralph

**Priority:** Should Have

**Description:**
Apos Ralph gerar testes, executar MutaHunter para injetar mutacoes no codigo e verificar se os testes detectam as mutacoes.

**Acceptance Criteria:**
- [ ] MutaHunter instalado e configurado
- [ ] Executa automaticamente apos Ralph completar testes
- [ ] Gera relatorio com mutation score
- [ ] Suporta linguagens do portfolio (Kotlin, C#, TypeScript)

**Dependencies:** Nenhuma

---

### FR-015: Rejeitar testes com mutation score abaixo do threshold

**Priority:** Should Have

**Description:**
Se o mutation score dos testes gerados pelo Ralph ficar abaixo do threshold configuravel, o Skinner rejeita e reenvia para Ralph reescrever os testes.

**Acceptance Criteria:**
- [ ] Threshold configuravel via YAML (default: 60%)
- [ ] Score abaixo do threshold = rejeicao automatica
- [ ] Skinner reenvia para Ralph com feedback especifico (quais mutantes sobreviveram)
- [ ] Log da rejeicao e motivo

**Dependencies:** FR-014

---

### FR-016: Log estruturado de erros com decay temporal

**Priority:** Must Have

**Description:**
Implementar log estruturado de erros por tipo/categoria no Skinner, com decay temporal (erros recentes pesam mais que antigos).

**Acceptance Criteria:**
- [ ] Erros categorizados por tipo (compilacao, teste, lint, arquitetura, etc.)
- [ ] Cada erro registrado com timestamp, contexto e frequencia
- [ ] Decay temporal configuravel (default: meia-vida de 7 dias)
- [ ] Dados persistidos em `.skinner/memory/`

**Dependencies:** Nenhuma

---

### FR-017: Diagnostico Roses/Buds/Thorns automatico

**Priority:** Should Have

**Description:**
Gerar diagnostico automatico no formato Roses (o que funciona bem), Buds (oportunidades), Thorns (problemas recorrentes) baseado na memoria comportamental.

**Acceptance Criteria:**
- [ ] Diagnostico gerado automaticamente por sessao ou por story
- [ ] Roses: identifica padroes de sucesso
- [ ] Buds: identifica areas de melhoria potencial
- [ ] Thorns: identifica erros recorrentes e anti-patterns
- [ ] Output em formato legivel (markdown)

**Dependencies:** FR-016

---

### FR-018: Adaptar prompts do Ralph baseado em padroes de erro

**Priority:** Must Have

**Description:**
Usar a memoria comportamental para adaptar os prompts enviados ao Ralph, injetando contexto sobre erros historicos relevantes para evitar repeticao.

**Acceptance Criteria:**
- [ ] Antes de cada loop, consulta memoria de erros relevantes
- [ ] Injeta contexto no prompt do Ralph (top 3-5 erros mais relevantes)
- [ ] Relevancia calculada por tipo de tarefa + decay temporal
- [ ] Reducao mensuravel de loops redundantes (meta: >= 30%)

**Dependencies:** FR-016

---

### FR-019: Criar branch exploratorio temporario

**Priority:** Could Have

**Description:**
Quando a qualidade e incerta (testes passam mas algo parece errado), criar branch exploratorio temporario para testar alternativa sem arriscar o branch principal.

**Acceptance Criteria:**
- [ ] Comando/trigger para criar branch exploratorio
- [ ] Branch isolado do principal (worktree separado)
- [ ] Testes executados no branch exploratorio
- [ ] Timeout configuravel para auto-abandon

**Dependencies:** FR-004

---

### FR-020: Comparar e decidir entre branches com log

**Priority:** Could Have

**Description:**
Comparar resultados entre branch exploratorio e branch principal, decidir merge ou abandon com log completo da decisao.

**Acceptance Criteria:**
- [ ] Comparacao automatica (metricas de teste, cobertura, lint)
- [ ] Decisao merge/abandon baseada em criterios configuraveis
- [ ] Log completo da decisao (motivo, metricas comparadas)
- [ ] Cleanup automatico do branch abandonado

**Dependencies:** FR-019

---

### FR-021: Review automatico em cada PR do Ralph

**Priority:** Should Have

**Description:**
Executar review automatico com 40+ analyzers (seguranca, performance, style, bugs) em cada PR gerada pelo Ralph.

**Acceptance Criteria:**
- [ ] Review executado automaticamente em cada PR
- [ ] 40+ analyzers cobrindo seguranca, performance, style, bugs
- [ ] Resultado em formato parseavel (JSON/markdown)
- [ ] Integracao com CodeRabbit ou plugin oficial

**Dependencies:** Nenhuma

---

### FR-022: Parsear resultado do review como gate no Skinner

**Priority:** Should Have

**Description:**
O Skinner deve parsear o resultado do review automatico e usa-lo como gate — findings criticos bloqueiam o merge.

**Acceptance Criteria:**
- [ ] Skinner parseia output do review
- [ ] Findings classificados por severidade (critical, high, medium, low)
- [ ] Critical/High bloqueiam merge
- [ ] Medium/Low geram warnings no log
- [ ] Threshold de severidade configuravel

**Dependencies:** FR-021

---

### FR-023: Portar skills custom para v2

**Priority:** Must Have

**Description:**
Portar os skills custom do v1 (ralph-loop, validate, skinner-status) para a estrutura do v2, adaptando para usar hooks nativos e novas camadas.

**Acceptance Criteria:**
- [ ] `/ralph-loop` portado e funcional no v2
- [ ] `/validate` portado com 8+ passes de validacao
- [ ] `/skinner-status` portado com info das novas camadas
- [ ] Skills registrados em `.claude/commands/`

**Dependencies:** Nenhuma

---

### FR-024: Portar configs do v1 para estrutura v2

**Priority:** Must Have

**Description:**
Portar todas as configuracoes do v1 (BMAD, Spec-Kit, Ralph, Skinner) para a nova estrutura de pastas do v2.

**Acceptance Criteria:**
- [ ] BMAD configs portados (personas, templates)
- [ ] Spec-Kit configs portados (.specify/)
- [ ] Ralph configs portados (.ralph/, .ralphrc)
- [ ] Skinner configs portados (.skinner/)
- [ ] CLAUDE.md atualizado com governanca v2

**Dependencies:** Nenhuma

---

### FR-025: Cada camada ativavel/desativavel via config

**Priority:** Must Have

**Description:**
Cada uma das 9 camadas deve ser ativavel ou desativavel independentemente via arquivo de configuracao, sem afetar as demais.

**Acceptance Criteria:**
- [ ] Arquivo de config central com flags por camada
- [ ] Ativar/desativar qualquer camada sem reiniciar
- [ ] Camada desativada = zero overhead (nao carrega, nao executa)
- [ ] Default: apenas camadas Must Have ativas
- [ ] Retrocompatibilidade: config vazio = comportamento v1

**Dependencies:** Nenhuma

---

## Non-Functional Requirements

Non-Functional Requirements (NFRs) define **how** the system performs - quality attributes and constraints.

---

### NFR-001: Performance - Hooks < 2s

**Priority:** Must Have

**Description:**
Hooks (PreToolUse/PostToolUse) devem executar em menos de 2 segundos para nao impactar o fluxo interativo do Claude Code.

**Acceptance Criteria:**
- [ ] Tempo de execucao de cada hook < 2s (p95)
- [ ] Medido via benchmark em operacoes tipicas

**Rationale:**
Hooks lentos degradam a experiencia do usuario e atrasam o loop do Ralph.

---

### NFR-002: Performance - Langfuse overhead < 5%

**Priority:** Must Have

**Description:**
O tracing via Langfuse deve adicionar menos de 5% de overhead ao tempo total de execucao do loop.

**Acceptance Criteria:**
- [ ] Overhead medido: tempo com tracing vs sem tracing < 5%
- [ ] Tracing assincrono (nao bloqueia execucao principal)

**Rationale:**
Observabilidade nao pode comprometer a velocidade do motor.

---

### NFR-003: Confiabilidade - Degradacao graciosa

**Priority:** Must Have

**Description:**
Falha em qualquer camada opcional nao deve interromper o motor. O sistema deve degradar graciosamente com log do problema.

**Acceptance Criteria:**
- [ ] Falha em Langfuse = motor continua sem tracing + log warning
- [ ] Falha em Git AI = motor continua sem autoria + log warning
- [ ] Falha em MutaHunter = motor continua sem mutation testing + log warning
- [ ] Nenhuma camada opcional causa crash do motor

**Rationale:**
Disponibilidade do motor e mais importante que qualquer camada individual.

---

### NFR-004: Confiabilidade - Circuit breaker persistente

**Priority:** Must Have

**Description:**
O circuit breaker do Skinner deve persistir estado entre sessoes, sem perda de contagem de erros ou trips.

**Acceptance Criteria:**
- [ ] Estado do circuit breaker salvo em disco (`.skinner/memory/`)
- [ ] Restaurado automaticamente no SessionStart
- [ ] Sem perda de dados entre sessoes

**Rationale:**
Perder estado do circuit breaker pode causar loops infinitos em sessoes subsequentes.

---

### NFR-005: Modularidade - Zero acoplamento entre camadas

**Priority:** Must Have

**Description:**
Cada camada deve ser ativavel/desativavel sem afetar as demais. Zero acoplamento direto entre camadas.

**Acceptance Criteria:**
- [ ] Remover qualquer camada nao quebra as demais
- [ ] Nenhuma camada importa/referencia outra diretamente
- [ ] Comunicacao entre camadas via eventos/log (se necessario)

**Rationale:**
Modularidade permite adocao incremental e manutencao independente.

---

### NFR-006: Modularidade - Configuracao centralizada sem hardcode

**Priority:** Must Have

**Description:**
Toda configuracao deve estar em arquivos YAML/JSON por camada, sem valores hardcoded no codigo.

**Acceptance Criteria:**
- [ ] Zero valores hardcoded (thresholds, paths, flags)
- [ ] Cada camada tem seu arquivo de config
- [ ] Config central agrega flags de ativacao
- [ ] Defaults sensatos para toda configuracao

**Rationale:**
Facilita customizacao e evita erros por valores escondidos no codigo.

---

### NFR-007: Portabilidade - Language-agnostic

**Priority:** Must Have

**Description:**
O motor deve funcionar com qualquer linguagem/framework no projeto alvo, sem ser acoplado a stack especifica.

**Acceptance Criteria:**
- [ ] Testado com Kotlin, C#, TypeScript (portfolio atual)
- [ ] Testes de arquitetura escolhem ferramenta por linguagem automaticamente
- [ ] Nenhuma logica do motor assume linguagem especifica

**Rationale:**
O motor deve ser reutilizavel em qualquer projeto.

---

### NFR-008: Portabilidade - Retrocompatibilidade v1

**Priority:** Must Have

**Description:**
Projetos v1 (GhostFit, Motor Financeiro) devem continuar funcionando no motor v2 sem quebra.

**Acceptance Criteria:**
- [ ] GhostFit roda no v2 sem modificacoes
- [ ] Motor Financeiro roda no v2 sem modificacoes
- [ ] Skills v1 funcionam no v2 (com ou sem novas camadas ativas)

**Rationale:**
Nao podemos quebrar projetos existentes ao evoluir o motor.

---

### NFR-009: Seguranca - Protecao de arquivos criticos

**Priority:** Must Have

**Description:**
Arquivos criticos (spec.md, CLAUDE.md, configs de producao) devem ser protegidos contra edicao acidental.

**Acceptance Criteria:**
- [ ] Lista de arquivos protegidos configuravel
- [ ] Tentativa de edicao bloqueada com mensagem clara
- [ ] Log de tentativas bloqueadas

**Rationale:**
Edicao acidental de specs ou governance pode corromper todo o pipeline.

---

### NFR-010: Seguranca - Langfuse apenas localhost

**Priority:** Should Have

**Description:**
Langfuse self-hosted nao deve expor portas externamente, apenas acessivel via localhost.

**Acceptance Criteria:**
- [ ] docker-compose.yml configura bind apenas em 127.0.0.1
- [ ] Nenhuma porta exposta em 0.0.0.0

**Rationale:**
Dados de tracing podem conter informacoes sensiveis.

---

### NFR-011: Observabilidade - 100% cobertura de tracing

**Priority:** Must Have

**Description:**
100% das chamadas LLM devem ser rastreadas com custo, latencia e tokens. Zero gaps.

**Acceptance Criteria:**
- [ ] Auditoria periodica: chamadas LLM vs traces no Langfuse = 100%
- [ ] Alerta se gap detectado

**Rationale:**
Gaps no tracing invalidam analises de custo e performance.

---

### NFR-012: Observabilidade - Retencao de logs 30 dias

**Priority:** Should Have

**Description:**
Logs de auditoria do Skinner devem ser retidos por no minimo 30 dias.

**Acceptance Criteria:**
- [ ] Logs armazenados em `.skinner/logs/`
- [ ] Retencao minima de 30 dias
- [ ] Rotacao automatica de logs antigos

**Rationale:**
Permite analise historica e debugging de problemas passados.

---

### NFR-013: Custo - Zero SaaS pagos

**Priority:** Must Have

**Description:**
Todas as ferramentas e dependencias devem ser gratuitas ou self-hosted. Zero custos com SaaS pagos.

**Acceptance Criteria:**
- [ ] Nenhuma dependencia requer assinatura paga
- [ ] Alternativas self-hosted para todo servico externo
- [ ] Custo operacional = apenas recursos locais (CPU, memoria, disco)

**Rationale:**
Projeto pessoal sem orcamento para SaaS. Self-hosted garante controle total.

---

## Epics

Epics are logical groupings of related functionality that will be broken down into user stories during sprint planning (Phase 4).

Each epic maps to multiple functional requirements and will generate 2-10 stories.

---

### EPIC-001: Estrutura Base e Portabilidade v1

**Description:**
Criar repositorio v2, portar toda a configuracao e skills do v1, estabelecer a estrutura de pastas e governanca (CLAUDE.md).

**Functional Requirements:**
- FR-023
- FR-024
- FR-025

**Story Count Estimate:** 4-6

**Priority:** Must Have

**Business Value:**
Fundacao sobre a qual todas as camadas serao construidas. Sem isso, nada funciona.

---

### EPIC-002: Hooks Nativos Claude Code

**Description:**
Migrar logica do Skinner para hooks nativos (PreToolUse, PostToolUse, SessionStart), integrando enforcement diretamente no runtime do Claude Code.

**Functional Requirements:**
- FR-001
- FR-002
- FR-003
- FR-004

**Story Count Estimate:** 4-6

**Priority:** Must Have

**Business Value:**
Elimina a dependencia do Skinner como script externo. Enforcement nativo = mais confiavel e rapido.

---

### EPIC-003: Observabilidade (Langfuse)

**Description:**
Instrumentar o motor com tracing completo via Langfuse self-hosted. Dashboard de custo, latencia e tokens por loop/story/workspace.

**Functional Requirements:**
- FR-011
- FR-012
- FR-013

**Story Count Estimate:** 3-5

**Priority:** Must Have

**Business Value:**
Impossivel otimizar o que nao se mede. Base para demonstrar ROI corporativo.

---

### EPIC-004: Memoria Comportamental (VIGIL)

**Description:**
Implementar memoria persistente no Skinner com log estruturado de erros, decay temporal, diagnostico Roses/Buds/Thorns e adaptacao de prompts.

**Functional Requirements:**
- FR-016
- FR-017
- FR-018

**Story Count Estimate:** 4-6

**Priority:** Must Have

**Business Value:**
Reducao de >= 30% nos loops redundantes. O motor aprende com seus erros.

---

### EPIC-005: Enforcement de Arquitetura (ArchUnit)

**Description:**
Adicionar testes de arquitetura executaveis que rodam como gate no Skinner. Garante que Ralph nao viola camadas.

**Functional Requirements:**
- FR-009
- FR-010

**Story Count Estimate:** 3-4

**Priority:** Must Have

**Business Value:**
Clean architecture verificada automaticamente, nao manualmente.

---

### EPIC-006: Rastreio de Autoria (Git AI)

**Description:**
Integrar Git AI para rastrear autoria AI vs humano por linha, com logs em Git Notes que sobrevivem operacoes Git.

**Functional Requirements:**
- FR-007
- FR-008

**Story Count Estimate:** 2-3

**Priority:** Should Have

**Business Value:**
Transparencia total sobre o que foi escrito por AI vs humano.

---

### EPIC-007: Qualidade de Testes (MutaHunter)

**Description:**
Integrar mutation testing para verificar efetividade dos testes gerados pelo Ralph. Rejeitar testes fracos automaticamente.

**Functional Requirements:**
- FR-014
- FR-015

**Story Count Estimate:** 3-4

**Priority:** Should Have

**Business Value:**
Mutation score >= 60% garante que testes realmente detectam bugs.

---

### EPIC-008: Review Automatico (Code Review + PR)

**Description:**
Integrar plugin de code review e review automatico de PR com 40+ analyzers como gate no pipeline.

**Functional Requirements:**
- FR-005
- FR-006
- FR-021
- FR-022

**Story Count Estimate:** 3-5

**Priority:** Should Have

**Business Value:**
Zero merge sem review. Qualidade como gate obrigatorio.

---

### EPIC-009: Branch Exploratorio

**Description:**
Alternativa ao binario commita/reverte. Criar branch temporario, testar alternativa, comparar e decidir com log.

**Functional Requirements:**
- FR-019
- FR-020

**Story Count Estimate:** 2-3

**Priority:** Could Have

**Business Value:**
Flexibilidade para situacoes incertas sem arriscar o branch principal.

---

## User Stories (High-Level)

User stories follow the format: "As a [user type], I want [goal] so that [benefit]."

These are preliminary stories. Detailed stories will be created in Phase 4 (Implementation).

---

Detailed user stories will be created during sprint planning (Phase 4).

---

## User Personas

### Rafael Giovannini (Primary User)

- **Papel:** Desenvolvedor solo, criador e operador do motor
- **Uso:** Diario, para acelerar projetos pessoais e profissionais
- **Perfil tecnico:** Tech-savvy, confortavel com CLI, Git avancado e DevOps
- **Necessidades:** Confianca no output, visibilidade operacional, evolucao continua

### Equipe Empresa (Future User)

- **Papel:** Desenvolvedores com nivel tecnico variado
- **Uso:** Potencial adocao se o motor demonstrar resultados solidos
- **Perfil tecnico:** Variado (junior a senior)
- **Necessidades:** Documentacao clara, camadas opcionais, onboarding simples

---

## User Flows

### Flow 1: Ralph Loop Completo

Story recebida → Spec gerada → TDD loop (Ralph) → Testes passam → Review automatico → Skinner valida → Commit ou revert

### Flow 2: Skinner Enforcement

Hook detecta violacao → Bloqueia operacao → Log registrado → Feedback ao Ralph → Ralph corrige → Retry

### Flow 3: Analise de Metricas

Sessao completa → Langfuse dashboard → Custo/story visivel → Padroes identificados → Decisao de otimizacao

---

## Dependencies

### Internal Dependencies

- AI-Brain Engine v1 (BMAD, Spec-Kit, Ralph, Skinner) — base a ser portada
- Skills custom (ralph-loop, validate, skinner-status) — portabilidade obrigatoria
- CLAUDE.md — governanca atualizada para v2

### External Dependencies

- **Claude Code CLI** (@anthropic-ai/claude-code) — runtime principal
- **Langfuse** (langfuse/langfuse) — observabilidade, self-hosted via Docker
- **Git AI** (git-ai-project/git-ai) — rastreio de autoria
- **MutaHunter** (codeintegrity-ai/mutahunter) — mutation testing
- **ArchUnit** (TNG/ArchUnit) / dependency-cruiser (sverweij/dependency-cruiser) — testes de arquitetura
- **CodeRabbit** (coderabbit.ai) — review automatico de PR
- **Docker** — infraestrutura para Langfuse

---

## Assumptions

1. Claude Code hooks API (PreToolUse, PostToolUse, SessionStart) e estavel e mantida pela Anthropic
2. Ferramentas referenciadas (Git AI, MutaHunter, Langfuse, CodeRabbit) mantem compatibilidade
3. Docker esta disponivel e funcional na maquina de desenvolvimento
4. Git worktrees continuam sendo o mecanismo de isolamento adequado
5. O modelo Claude (Opus/Sonnet) continua disponivel e com qualidade suficiente
6. Projetos v1 podem ser migrados gradualmente sem quebra

---

## Out of Scope

- UI/dashboard proprio (usa Langfuse para observabilidade)
- Suporte multi-tenant ou multi-usuario simultaneo
- Cloud deployment / SaaS
- Integracao com outros LLM providers (apenas Claude via Claude Code CLI)
- Mobile app ou interface web propria
- Monetizacao ou modelo de negocio

---

## Open Questions

1. **Git AI estabilidade:** O projeto Git AI e estavel o suficiente para uso em producao? Avaliar antes de depender.
2. **MutaHunter linguagens:** MutaHunter suporta bem Kotlin + C# + TypeScript? Validar por linguagem.
3. **Langfuse recursos:** Qual o overhead real do Langfuse self-hosted (Docker + PostgreSQL + Redis) em recursos locais?

---

## Approval & Sign-off

### Stakeholders

- **Rafael Giovannini (Dev/Owner)** — Influencia Alta. Criador, operador e unico usuario atual.
- **Empresa futuro (Potencial Sponsor)** — Influencia Media. Potencial adocao corporativa.

### Approval Status

- [ ] Product Owner
- [ ] Engineering Lead
- [ ] Design Lead
- [ ] QA Lead

---

## Revision History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-03-05 | rafael.giovannini | Initial PRD |

---

## Next Steps

### Phase 3: Architecture

Run `/bmad:architecture` to create system architecture based on these requirements.

The architecture will address:
- All functional requirements (FRs)
- All non-functional requirements (NFRs)
- Technical stack decisions
- Data models and APIs
- System components

### Phase 4: Sprint Planning

After architecture is complete, run `/bmad:sprint-planning` to:
- Break epics into detailed user stories
- Estimate story complexity
- Plan sprint iterations
- Begin implementation

---

**This document was created using BMAD Method v6 - Phase 2 (Planning)**

*To continue: Run `/bmad:workflow-status` to see your progress and next recommended workflow.*

---

## Appendix A: Requirements Traceability Matrix

| Epic ID | Epic Name | Functional Requirements | Story Count (Est.) |
|---------|-----------|-------------------------|-------------------|
| EPIC-001 | Estrutura Base e Portabilidade v1 | FR-023, FR-024, FR-025 | 4-6 |
| EPIC-002 | Hooks Nativos Claude Code | FR-001, FR-002, FR-003, FR-004 | 4-6 |
| EPIC-003 | Observabilidade (Langfuse) | FR-011, FR-012, FR-013 | 3-5 |
| EPIC-004 | Memoria Comportamental (VIGIL) | FR-016, FR-017, FR-018 | 4-6 |
| EPIC-005 | Enforcement de Arquitetura (ArchUnit) | FR-009, FR-010 | 3-4 |
| EPIC-006 | Rastreio de Autoria (Git AI) | FR-007, FR-008 | 2-3 |
| EPIC-007 | Qualidade de Testes (MutaHunter) | FR-014, FR-015 | 3-4 |
| EPIC-008 | Review Automatico (Code Review + PR) | FR-005, FR-006, FR-021, FR-022 | 3-5 |
| EPIC-009 | Branch Exploratorio | FR-019, FR-020 | 2-3 |
| **TOTAL** | **9 Epics** | **25 FRs** | **28-42 stories** |

---

## Appendix B: Prioritization Details

### Functional Requirements

| Priority | Count | Percentage |
|----------|-------|------------|
| Must Have | 13 | 52% |
| Should Have | 9 | 36% |
| Could Have | 3 | 12% |
| **Total** | **25** | **100%** |

### Non-Functional Requirements

| Priority | Count | Percentage |
|----------|-------|------------|
| Must Have | 10 | 77% |
| Should Have | 3 | 23% |
| **Total** | **13** | **100%** |

### Epics

| Priority | Count | Est. Stories |
|----------|-------|-------------|
| Must Have | 5 | 18-27 |
| Should Have | 3 | 8-12 |
| Could Have | 1 | 2-3 |
| **Total** | **9** | **28-42** |

### MoSCoW Distribution Analysis

A distribuicao esta saudavel:
- **Must Have (52% FRs):** Dentro do recomendado (< 60%). Foco no core do motor.
- **Should Have (36% FRs):** Camadas de qualidade que agregam muito valor mas tem workaround.
- **Could Have (12% FRs):** Apenas branch exploratorio, corretamente priorizado como nice-to-have.
