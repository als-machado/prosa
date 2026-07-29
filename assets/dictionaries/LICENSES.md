# Dicionários de verificação ortográfica

Os arquivos `.bloom` deste diretório são obra derivada dos dicionários
Hunspell distribuídos pelo LibreOffice
(<https://github.com/LibreOffice/dictionaries>). Eles não contêm o texto das
palavras: são filtros de Bloom, isto é, vetores de bits que só respondem
"esta palavra existe?".

São gerados por `scripts/build_dictionaries.py`, que baixa os arquivos
`.aff`/`.dic` originais e expande as formas geradas pelos afixos. Para
reconstruir ou auditar qualquer um deles:

```
python3 scripts/build_dictionaries.py --lang pt_BR --force
```

## pt_BR.bloom

Derivado do dicionário do **Projeto VERO**.

    Copyright (C) 2006-2013 Raimundo Santos Moura <raimundo.smoura@gmail.com>

Licenciado sob os termos da GNU Lesser General Public License versão 3
(LGPLv3), como publicada pela Free Software Foundation, e da Mozilla Public
License, como publicada pela Mozilla Foundation. A relação completa de
colaboradores está em <https://pt-br.libreoffice.org/projetos/vero/>.

## en_US.bloom

Derivado dos dicionários Hunspell em inglês gerados a partir do **SCOWL**
(Spell Checker Oriented Word Lists).

    Copyright 2000-2018 by Kevin Atkinson

    Permission to use, copy, modify, distribute and sell these word lists,
    the associated scripts, the output created from the scripts, and its
    documentation for any purpose is hereby granted without fee, provided
    that the above copyright notice appears in all copies and that both that
    copyright notice and this permission notice appear in supporting
    documentation. Kevin Atkinson makes no representations about the
    suitability of this array for any purpose. It is provided "as is"
    without express or implied warranty.

O SCOWL incorpora material do WordNet (Princeton University), do Ispell
(licença BSD) e de listas em domínio público. Os avisos completos estão em
`README_en_US.txt` no repositório de dicionários do LibreOffice.
