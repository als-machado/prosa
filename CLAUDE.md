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

## Verificação ortográfica
Feature em `lib/features/spellcheck/`. Idioma vem de `spellcheckLanguage` nas
configurações e, na falta dele, do campo `language` do `.prosa`.

O dicionário é um **filtro de Bloom** por idioma em `assets/dictionaries/`
(pt_BR 6,4 MB, en_US 0,3 MB), gerado por `scripts/build_dictionaries.py` a
partir dos Hunspell do LibreOffice — o pt_BR expandido tem 10,5 milhões de
formas, que como lista não caberiam em memória. Palavra correta nunca é
sublinhada; 1 erro em 10.000 passa batido. Junto vai um modelo de 4-gramas
(~200 KB) que descarta sugestão inventada por falso positivo do filtro.

Para regerar (precisa de rede, ~50 s):
```
python3 scripts/build_dictionaries.py --force
```
O hash (MurmurHash3 x86_32) e a normalização de palavras estão duplicados
entre o script Python e `data/bloom_dictionary.dart`: mudar um lado sem o
outro transforma o dicionário em ruído.

A marcação **nunca** entra no delta do documento — o sublinhado é feito no
`textSpanDecorator` do `EditorStyle`, senão sujaria o Markdown salvo, o
desfazer e o autosave.

## Exportação de livros
Feature em `lib/features/export/`. O botão fica na barra do editor.

O caminho é sempre o mesmo, e é o que faz cada formato novo custar um arquivo:

```
arquivos .md → markdownToEditorDocument (o MESMO parser do editor)
             → BookBuilder  → Book (capítulos + apêndices + metadados + capa)
             → BookExporter → bytes
```

Reusar `markdownToEditorDocument` não é preguiça: o Prosa salva **uma linha por
bloco**, e um parser de Markdown comum juntaria parágrafos seguidos num só. Ler
por outro caminho daria um livro diferente do que está na tela.

Decisões editoriais, todas no `BookBuilder`:
- título de nível 1 que abre o arquivo vira o título da seção e sai do corpo;
  sem ele, o título é o nome da pasta e os títulos do corpo descem um nível;
- capítulo com cenas vira um capítulo só, com quebra de cena entre elas;
- linha em branco não vira parágrafo vazio (o espaçamento vem do CSS);
- arquivo de apoio que só tem o título não entra no sumário.

Seis formatos, um `BookExporter` cada, em `data/`:

| Formato | Como é feito |
|---|---|
| EPUB 3 | ZIP com `mimetype` sem compressão, um XHTML por seção, `nav.xhtml` + `toc.ncx` |
| DOCX   | ZIP OOXML; link e imagem passam por `rId` no `document.xml.rels` |
| ODT    | ZIP OpenDocument, também com `mimetype` primeiro e sem compressão |
| PDF    | pacote `pdf`, diagramado aqui (15×22 cm, marcadores por `pw.Outline`) |
| HTML   | uma página só, estilo embutido e imagem em `data:` |
| TXT    | texto puro, título sublinhado com `=`/`-` |

`.prosa_export.json` guarda no projeto o que foi escolhido da última vez,
inclusive o UUID do livro — reexportar tem de gerar o mesmo identificador,
senão a biblioteca do leitor mostra duas cópias.

O PDF **precisa** da fonte embutida: as fontes internas do formato PDF
(Times, Helvetica) só enxergam Latin-1, e travessão, aspas curvas e
reticências ficariam de fora — a pontuação de diálogo em português. Daí a
Liberation Serif em `assets/fonts` (SIL OFL, ver `LICENSES.md` de lá).

Lista numerada e com marcador saem com o marcador **escrito no texto** em
DOCX e ODT: numeração nativa exigiria uma definição de estilo por nível e por
tipo em cada formato, e o resultado na tela é o mesmo.

Para conferir uma exportação de verdade sem abrir o app:
```
soffice --headless --convert-to txt:Text livro.docx   # DOCX e ODT
pdftotext -layout livro.pdf -                          # PDF
python3 -c "import zipfile; print(zipfile.ZipFile('livro.epub').namelist())"
```

## Estrutura de projeto Prosa (no disco)
```
<projeto>/
├── .prosa          # YAML com metadados
├── .prosa_dictionary  # palavras aprendidas (versionado no Git)
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

Build Linux precisa de `clang`, `cmake`, `ninja-build`, `pkg-config`,
`libgtk-3-dev`, `libsecret-1-dev` e `libjsoncpp-dev` (os dois últimos são do
`flutter_secure_storage_linux`).

Cuidado com clang muito novo: o `json.hpp` embutido no
`flutter_secure_storage_linux` usa a forma antiga de operador literal
(`operator "" _json`), e a partir de alguma versão entre a 18 e a 22 o clang
passou a avisar (`-Wdeprecated-literal-operator`). Como o template Linux do
Flutter compila plugin com `-Werror`, o build morre em aviso que não é do nosso
código. Medido: clang 18 do apt compila; clang 22 do conda-forge não. Se cair
nisso, ponha no PATH um wrapper de `clang++` que acrescente
`-Wno-deprecated-literal-operator` — trocar por gcc via `CC`/`CXX` não
funciona, o Flutter sobrescreve as duas variáveis (`build_linux.dart`).

O `.deb` sai de `scripts/build_deb.sh` (precisa de `dpkg-deb` e do Pillow no
Python). Se o clang usado não for o do sistema (conda, por exemplo), confira se
não sobrou caminho dele no RPATH — o pacote tem de depender só de biblioteca de
sistema:
`readelf -d build/linux/x64/release/bundle/prosa | grep -i rpath`

## Pendente (próximos passos)
- Exportação: número de página no sumário do PDF; imagem no meio do texto em
  DOCX, ODT e PDF (hoje só a capa é embutida)
- Verificação ortográfica: painel de revisão do capítulo inteiro; pt_PT e
  es_ES; gramática
- Formatação Markdown no editor (negrito/itálico via toolbar)
- Listagem de repositórios remotos via API do GitHub/GitLab
- Clone de projetos remotos ao abrir pela tela Home
- Criação de branch via UI
- GitHub Actions para build iOS
- Diálogos para novo capítulo, nova cena, novo personagem
