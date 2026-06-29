# Prosa

**Prosa** é um editor de texto para escritores, com foco na criação de livros. Combina uma interface limpa e focada com integração nativa ao Git, permitindo controle de versão completo da sua obra diretamente pelo editor.

## Funcionalidades

### Escrita
- Editor de texto com suporte a Markdown (negrito, itálico, etc.)
- Modo foco: oculta elementos da interface para maximizar a concentração
- Escolha de fonte e tamanho (visual apenas — arquivos salvos em texto puro)
- Modo noturno

### Organização do livro
- Estrutura de capítulos e cenas
- Gerenciamento de personagens com características e evolução
- Sinopse e estrutura narrativa
- Locais e cenários
- Pesquisa e referências
- Linha do tempo
- Mapas mentais
- Regras do mundo
- Glossário
- Notas gerais

### Integração com Git
- Integração via chave SSH (GitHub, GitLab, servidores pessoais)
- Listagem automática de projetos Prosa da sua conta Git
- Criação de commits ao salvar
- Push e pull direto pelo editor
- Gerenciamento de branches
- Visualização da árvore de commits com checkout por clique

## Estrutura de um projeto Prosa

```
meu-livro/
├── .prosa                  # Configurações e metadados do projeto
├── chapters/               # Capítulos do livro
│   ├── 1 - Início/
│   │   ├── scene 1.md
│   │   └── scene 2.md
│   └── 2 - Desenvolvimento/
│       └── chapter.md      # Capítulo sem divisão em cenas
├── characters/             # Personagens
│   └── João Silva/
│       ├── characteristics.md
│       └── evolution.md
└── misc/                   # Elementos auxiliares
    ├── synopsis.md         # Sinopse e logline
    ├── glossary.md         # Glossário de termos
    ├── notes/              # Notas gerais
    ├── locations/          # Locais e cenários
    ├── research/           # Pesquisa e referências
    ├── timeline/           # Linha do tempo
    ├── mind_maps/          # Mapas mentais
    └── world_rules/        # Regras do mundo
```

## Plataformas

- Linux (desktop)
- iOS (em breve — build via GitHub Actions)

## Instalação

### Pré-requisitos

- Flutter 3.x
- Git
- Dependências Linux: `clang`, `ninja-build`, `cmake`, `pkg-config`, `libgtk-3-dev`

### Build

```bash
git clone https://github.com/seu-usuario/prosa.git
cd prosa
flutter pub get
flutter run -d linux
```

## Desenvolvimento

O projeto utiliza:
- **Flutter** com arquitetura Feature-First (Clean Architecture)
- **Riverpod** para gerenciamento de estado
- **go_router** para navegação
- Markdown para formatação de texto

## Licença

Este projeto é distribuído sob a licença **GNU General Public License v3.0**.
Consulte o arquivo [LICENSE](LICENSE) para mais detalhes.

---

*"Escrever é a forma mais profunda de ler." — Francisco Umbral*
