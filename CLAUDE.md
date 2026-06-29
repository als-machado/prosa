# Prosa — Contexto para Claude Code

## O que é
Editor de texto para escritores focado em livros. Flutter (Linux + iOS), integração Git via SSH, estrutura de projeto versionada.

## Stack
- Flutter 3.44+ / Dart 3.12+
- Riverpod 2.x para estado
- go_router para navegação
- Git via `Process.run('git', ...)` (sem biblioteca nativa)
- SSH via `ssh-keygen` e `Process.run('ssh', ...)`
- Markdown nos arquivos de texto (salvos como `.md`)

## Arquitetura
Feature-first clean architecture em `lib/`:
- `core/` — tema, router, constantes
- `features/<feature>/{data,domain,presentation}` — cada feature isolada
- `shared/` — widgets e modelos compartilhados

## Estrutura de projeto Prosa (no disco)
```
<projeto>/
├── .prosa          # YAML com metadados
├── chapters/
│   └── 1 - Título/ # ou só "1/"
│       ├── chapter.md      # sem cenas
│       └── scene 1.md      # com cenas
├── characters/
│   └── Nome/
│       ├── characteristics.md
│       └── evolution.md
└── misc/
    ├── synopsis.md
    ├── glossary.md
    ├── notes/
    ├── locations/
    ├── research/
    ├── timeline/
    ├── mind_maps/
    └── world_rules/
```

## Flutter no sistema
SDK instalado em `/home/andre/flutter`. PATH configurado em `~/.bashrc`.
Para rodar: `flutter run -d linux`

## Pendente (próximos passos)
- Formatação Markdown no editor (negrito/itálico via toolbar)
- Listagem de repositórios remotos via API do GitHub/GitLab
- Clone de projetos remotos ao abrir pela tela Home
- Criação de branch via UI
- GitHub Actions para build iOS
- Diálogos para novo capítulo, nova cena, novo personagem
