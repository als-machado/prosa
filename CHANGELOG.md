# Changelog

## 0.2.0 — 2026-07-29

### Adicionado

- **Verificação ortográfica** enquanto se escreve, em português do Brasil e
  inglês. Palavra fora do dicionário ganha sublinhado ondulado; o botão direito
  oferece as correções, "ignorar nesta sessão" e "adicionar ao dicionário do
  projeto". O idioma vem das configurações e, na falta dele, do campo
  `language` do `.prosa`; pode ser desligada nas configurações.
  - As palavras aprendidas ficam em `.prosa_dictionary`, na raiz do projeto e
    versionado no Git: nome de personagem é do livro, não da instalação.
  - O dicionário é um filtro de Bloom por idioma (pt_BR com 2,8 milhões de
    formas em 6,4 MB). Palavra correta nunca é sublinhada; um erro em cada
    10.000 passa batido.
- **Bloco de código** no editor, com fonte monoespaçada e fundo destacado.
  Três crases em linha vazia criam o bloco; dentro dele, Enter quebra a linha
  em vez de criar bloco novo, e a formatação automática de Markdown fica
  desligada. Em linha vazia, Enter sai do bloco.

### Corrigido

- Bloco de código escrito no arquivo **desaparecia ao abrir**, e o primeiro
  salvamento depois disso apagava o conteúdo do arquivo.
- **Linhas em branco desapareciam** ao fechar e reabrir o arquivo.
- Clicar no corpo do texto **levava o cursor para o começo do documento** em
  arquivos com várias linhas seguidas.
- O **ícone da janela não aparecia no painel** (um quadrado vazio no lugar),
  ao rodar direto ou pelo `flutter run`.
- O sublinhado da verificação ortográfica era difícil de ver no **tema escuro**.
- Erro "Cannot use ref after the widget was disposed" ao fechar a janela, que
  interrompia o salvamento de emergência das alterações não salvas.

### Notas para quem compila

`CLAUDE.md` ganhou a lista de dependências do build Linux e as armadilhas
conhecidas (clang novo com `-Werror` no `flutter_secure_storage`, e caminho de
toolchain vazando no RPATH do executável).

## 0.1.0 — 2026-07-18

Primeira versão publicada: editor com modo foco, integração Git via SSH
(commit, push, pull, branches), estrutura de projeto versionada, busca no
arquivo (Ctrl+F/Ctrl+H), tamanho de texto e margens configuráveis, e
empacotamento em `.deb`.
