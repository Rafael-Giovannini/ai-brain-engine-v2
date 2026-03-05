# Product Brief: AI-Brain Engine v2

**Date:** 2026-03-05
**Author:** Rafael Giovannini
**Version:** 1.0
**Project Type:** Developer Tooling / Autonomous Execution Engine
**Project Level:** 3 (Large/Complex)

---

## Executive Summary

O AI-Brain Engine v2 e um motor de execucao autonomo que transforma especificacoes em codigo funcional atraves de agentes AI coordenados. Evolui o v1 (BMAD + Spec-Kit + Ralph + Skinner) adicionando robustez operacional — observabilidade, memoria comportamental, review automatico, rastreio de autoria e enforcement de arquitetura — para que o motor aprenda com seus erros e produza codigo de qualidade crescente ao longo do tempo. Secundariamente, habilita escala via paralelismo e branch exploratorio.

---

## Problem Statement

### The Problem

O AI-Brain Engine v1 funciona, mas opera "as cegas". Os problemas concretos:

1. **Sem observabilidade**: Nao sabemos o custo, latencia ou taxa de erro dos loops do Ralph. Impossivel otimizar o que nao se mede.
2. **Sem memoria**: O Skinner nao aprende com erros passados. O mesmo tipo de erro pode repetir indefinidamente, consumindo tokens e tempo.
3. **Testes nao verificados**: Ralph gera testes, mas nao ha garantia de que sao efetivos. Testes fracos passam sem cobrir o codigo real (false confidence).
4. **Sem review pre-merge**: Codigo entra no branch principal sem nenhuma revisao automatizada. Bugs e code smells passam direto.
5. **Sem rastreabilidade de autoria**: Impossivel saber quem (humano vs AI, e qual modelo) escreveu cada linha.
6. **Skinner desintegrado**: Roda como script externo, nao aproveita hooks nativos do Claude Code.
7. **Binario commita/reverte**: Sem opcao intermediaria (branch exploratorio) para situacoes incertas.
8. **Sem enforcement de arquitetura**: Clean architecture so e verificada manualmente — Ralph pode violar camadas sem que ninguem perceba.
9. **Sem paralelismo**: Apenas um Ralph por vez, limitando throughput.

### Why Now?

- Claude Code agora suporta hooks nativos (PreToolUse, PostToolUse, SessionStart), permitindo integrar o Skinner de forma nativa
- Ferramentas como Langfuse, Git AI e MutaHunter amadureceram o suficiente para uso em producao
- O v1 ja esta validado com 2 projetos reais (GhostFit, Motor Financeiro), provando o conceito
- O custo acumulado de loops redundantes e testes fracos justifica o investimento em robustez

### Impact if Unsolved

- Loops redundantes continuam queimando tokens e tempo sem aprendizado
- Testes fracos geram falsa confianca, bugs escapam para producao
- Impossivel demonstrar ROI do motor para a empresa sem metricas
- O motor permanece uma ferramenta pessoal fragil em vez de um produto apresentavel

---

## Target Audience

### Primary Users

- **Rafael Giovannini** — Desenvolvedor solo, criador e operador do motor. Usa diariamente para acelerar projetos pessoais e profissionais. Tech-savvy, confortavel com CLI, Git avancado e DevOps.

### Secondary Users

- **Equipe da empresa (futuro)** — Se o motor demonstrar resultados solidos, sera apresentado como ferramenta de produtividade. Desenvolvedores com nivel tecnico variado que precisariam de documentacao clara e camadas opcionais.
- **Comunidade open-source (potencial)** — Desenvolvedores que queiram adotar ou contribuir com o motor.

### User Needs

1. **Confianca no output**: Saber que o codigo gerado foi revisado, testado efetivamente e rastreado
2. **Visibilidade operacional**: Entender custo, performance e padroes de erro do motor
3. **Evolucao continua**: O motor deve ficar melhor com o tempo, nao apenas repetir os mesmos erros

---

## Solution Overview

### Proposed Solution

Evolucao do AI-Brain Engine v1 com 9 camadas adicionais, cada uma opcional e independente, sobre a base existente (BMAD + Spec-Kit + Ralph + Skinner). O foco e robustez operacional: o motor deve se auto-monitorar, aprender com erros, verificar a qualidade do proprio output e rastrear toda acao.

### Key Features

- **Camada 1: Hooks Nativos Claude Code** — Migrar logica do Skinner para PreToolUse/PostToolUse/SessionStart. Bloquear writes sem teste, auto-lint, proteger arquivos criticos.
- **Camada 2: Code Review Plugin** — Plugin oficial Anthropic que lanca 4-5 subagentes auditando o diff (compliance, bugs, git history, comments). Score 0-100.
- **Camada 3: Git AI** — Rastreio de autoria AI vs humano por linha. Armazena em `.git/ai/`, sobrevive rebases/merges.
- **Camada 4: ArchUnit** — Testes de arquitetura como JUnit. "Domain nao importa infrastructure", "classes < 300 linhas", "use cases em domain/".
- **Camada 5: Langfuse** — Observabilidade de cada chamada LLM. Custo/latencia/tokens por loop, story, workspace. Self-hosted via Docker.
- **Camada 6: MutaHunter** — Mutation testing. Injeta mutacoes no codigo e verifica se testes do Ralph realmente detectam. Language-agnostic.
- **Camada 7: VIGIL Pattern** — Memoria comportamental persistente no Skinner. Log estruturado de erros com decay temporal, diagnostico Roses/Buds/Thorns, adaptacao de prompts.
- **Camada 8: Branch Exploratorio** — Alternativa ao binario commita/reverte. Cria branch temporario, testa alternativa, compara resultados, merge ou abandon com log.
- **Camada 9: Review Automatico de PR** — CodeRabbit ou plugin oficial rodando em cada PR. 40+ analyzers como gate no Skinner.

### Value Proposition

Um motor que nao apenas executa, mas **aprende, se monitora e se auto-corrige** — transformando a geracao de codigo por AI de um processo ad-hoc em um pipeline de engenharia com qualidade mensuravel e crescente.

---

## Business Objectives

### Goals

- Reduzir loops redundantes do Ralph em >= 30% via memoria comportamental (VIGIL)
- Atingir 100% de rastreabilidade de chamadas LLM (Langfuse)
- Garantir mutation score minimo de 60% em testes gerados pelo Ralph
- Eliminar merges sem review automatico (zero PRs sem gate de qualidade)
- Ter autoria AI vs humano rastreavel por linha de codigo
- Tornar cada camada opcional via flag/config, mantendo retrocompatibilidade com v1
- Produzir metricas suficientes para demonstrar ROI a stakeholders corporativos

### Success Metrics

- Numero de loops por story (antes vs depois da memoria VIGIL)
- Custo em tokens/USD por story completada
- Mutation score medio dos testes gerados
- % de PRs com review automatico aprovado vs rejeitado
- Tempo medio de resolucao de story (end-to-end)
- Taxa de circuit breaker trips (deve diminuir ao longo do tempo)

### Business Value

- **Produtividade**: Motor mais eficiente = mais stories entregues por unidade de tempo/custo
- **Qualidade**: Testes verificados + review automatico = menos bugs em producao
- **Apresentabilidade**: Metricas e dashboards para convencer stakeholders corporativos
- **Escalabilidade**: Motor generico reutilizavel para qualquer projeto/linguagem

---

## Scope

### In Scope

- Repositorio separado com estrutura propria
- 9 camadas novas (cada uma opcional e independente)
- Retrocompatibilidade com projetos v1 (GhostFit, Motor Financeiro)
- Motor generico — funciona para qualquer linguagem/framework
- Documentacao completa em PT-BR
- Self-hosted (sem dependencias externas pagas obrigatorias)
- Portabilidade dos skills custom (ralph-loop, validate, skinner-status)
- Portabilidade das configs (BMAD, Spec-Kit, Ralph, Skinner)

### Out of Scope

- UI/dashboard proprio (usa Langfuse para observabilidade)
- Suporte multi-tenant ou multi-usuario simultaneo
- Cloud deployment / SaaS
- Integracao com outros LLM providers (apenas Claude via Claude Code CLI)
- Mobile app ou interface web propria
- Monetizacao ou modelo de negocio

### Future Considerations

- Paralelismo de multiplos Ralphs em workspaces diferentes
- Plugin marketplace para camadas da comunidade
- Integracao com CI/CD pipelines (GitHub Actions, etc.)
- Suporte a outros LLM providers como fallback
- Dashboard web customizado sobre Langfuse

---

## Key Stakeholders

- **Rafael Giovannini (Dev/Owner)** - Influencia Alta. Criador, operador e unico usuario atual. Tomador de todas as decisoes tecnicas e de produto.
- **Empresa — futuro (Potencial Sponsor)** - Influencia Media. Potencial adocao corporativa se o motor demonstrar resultados concretos com metricas. Interesse em produtividade de desenvolvimento.

---

## Constraints and Assumptions

### Constraints

- **Orcamento**: Zero para SaaS pagos. Todas as ferramentas devem ser gratis ou self-hosted
- **Infraestrutura**: Roda local em maquina Windows 11 (pode usar Docker para servicos como Langfuse)
- **Runtime**: Dependente do Claude Code CLI (@anthropic-ai/claude-code) como runtime principal
- **Tempo**: Projeto pessoal, sem deadline fixo, mas entrega incremental camada por camada
- **Retrocompatibilidade**: Projetos v1 (GhostFit, Motor Financeiro) devem continuar funcionando

### Assumptions

- Claude Code hooks API (PreToolUse, PostToolUse, SessionStart) e estavel e mantida pela Anthropic
- Ferramentas referenciadas (Git AI, MutaHunter, Langfuse, CodeRabbit) mantem compatibilidade
- Docker esta disponivel e funcional na maquina de desenvolvimento
- Git worktrees continuam sendo o mecanismo de isolamento adequado
- O modelo Claude (Opus/Sonnet) continua disponivel e com qualidade suficiente
- Projetos v1 podem ser migrados gradualmente sem quebra

---

## Success Criteria

- Ralph reduz loops redundantes em >= 30% (medido via Langfuse, antes vs depois do VIGIL)
- 100% das chamadas LLM rastreadas com custo e latencia (Langfuse operacional)
- Mutation score >= 60% nos testes gerados pelo Ralph (MutaHunter integrado)
- Zero merge sem review automatico (gate de qualidade obrigatorio)
- Autoria AI vs humano rastreavel por linha (Git AI operacional)
- Cada camada funciona de forma independente (flag on/off sem quebrar o motor)
- Projetos v1 (GhostFit, Motor Financeiro) continuam funcionando no novo motor
- Metricas e dashboards suficientes para apresentacao corporativa convincente

---

## Timeline and Milestones

### Target Launch

Entrega incremental, sem deadline fixo. Cada camada e um milestone independente.

### Key Milestones

- **M1: Estrutura base + CLAUDE.md v2** — Repo criado, configs portadas, governance atualizado
- **M2: Hooks nativos (Camada 1)** — PreToolUse/PostToolUse/SessionStart funcionais
- **M3: Skinner v2 com VIGIL (Camada 7)** — Memoria comportamental persistente
- **M4: Langfuse (Camada 5)** — Docker rodando, tracing operacional
- **M5: Git AI (Camada 3)** — Autoria rastreavel
- **M6: ArchUnit (Camada 4)** — Testes de arquitetura no pipeline
- **M7: MutaHunter (Camada 6)** — Mutation testing integrado
- **M8: Code Review (Camadas 2+9)** — Review automatico pre-merge
- **M9: Branch Exploratorio (Camada 8)** — Alternativa ao binario commita/reverte
- **M10: Validacao end-to-end** — Rodar um projeto completo no motor v2 e comparar metricas com v1

---

## Risks and Mitigation

- **Risk:** Git AI pode nao ser estavel (projeto relativamente novo)
  - **Likelihood:** Media
  - **Mitigation:** Camada opcional, fallback para git notes manual. Avaliar estabilidade antes de depender.

- **Risk:** Langfuse self-hosted consome recursos significativos (Docker + PostgreSQL + Redis)
  - **Likelihood:** Media
  - **Mitigation:** Docker com limites de memoria/CPU. Desligar quando nao estiver em uso ativo.

- **Risk:** Hooks do Claude Code podem mudar ou ser deprecados
  - **Likelihood:** Baixa-Media
  - **Mitigation:** Isolar logica de hooks em scripts separados. Manter fallback para Skinner v1 puro.

- **Risk:** Complexidade acumulada — 9 camadas novas podem criar overhead de manutencao
  - **Likelihood:** Media-Alta
  - **Mitigation:** Cada camada e opcional via flag/config. Entrega incremental. Nao ativar tudo de uma vez.

- **Risk:** MutaHunter pode nao suportar bem todas as linguagens do portfolio (Kotlin, C#, TypeScript)
  - **Likelihood:** Media
  - **Mitigation:** Validar suporte por linguagem antes de integrar. Alternativas: PIT (Java/Kotlin), Stryker (.NET/JS).

- **Risk:** Custo de tokens com observabilidade e review pode aumentar significativamente
  - **Likelihood:** Media
  - **Mitigation:** Monitorar custo via Langfuse. Ajustar frequencia de review e profundidade de analise.

---

## Next Steps

1. Criar Product Requirements Document (PRD) — `/bmad:prd`
2. Design de arquitetura do sistema — `/bmad:architecture`
3. Sprint planning com decomposicao por camada — `/bmad:sprint-planning`

---

**This document was created using BMAD Method v6 - Phase 1 (Analysis)**

*To continue: Run `/bmad:prd` to create comprehensive requirements (Level 3 project).*
