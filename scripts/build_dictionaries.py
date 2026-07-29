#!/usr/bin/env python3
"""Gera os dicionários de verificação ortográfica do Prosa.

Pega os dicionários Hunspell do LibreOffice (.aff + .dic), expande todas as
formas que os afixos geram e grava, por idioma:

* `assets/dictionaries/<lang>.bloom` — o dicionário em filtro de Bloom;
* `assets/dictionaries/<lang>.ngram.bloom` — os 4-gramas que existem no
  idioma, usados para descartar sugestões impossíveis (ver abaixo).

Por que um filtro de Bloom: o pt_BR expandido tem 10,5 milhões de formas
(158 MB de texto, e mais de 200 MB de RAM como Set<String> em Dart). O
filtro guarda só bits — nenhuma palavra — e responde "está no dicionário?"
em ~7 MB. O erro é assimétrico e a favor de quem escreve: palavra correta é
SEMPRE reconhecida (nunca sublinha à toa), e uma fração configurável dos
erros passa batido (padrão: 1 em 10.000).

Uso:
    python3 scripts/build_dictionaries.py                 # todos os idiomas
    python3 scripts/build_dictionaries.py --lang pt_BR    # só um
    python3 scripts/build_dictionaries.py --error 0.001   # filtro menor
    python3 scripts/build_dictionaries.py --force         # regera existentes

Sobre o modelo de 4-gramas: o gerador de sugestões faz milhares de consultas
ao filtro por palavra corrigida, então mesmo uma taxa de erro de 1 em 10.000
faz aparecer, de vez em quando, uma sugestão inventada — e às vezes no topo da
lista ("çázáverde" para "casaverde"). O modelo guarda todos os 4-gramas que
ocorrem no idioma; palavra real sempre passa por ele (foi de onde os 4-gramas
saíram), enquanto a sequência aleatória de um falso positivo quase nunca
passa. Custa ~200 KB e, na medição com 35 erros de digitação reais, derrubou
as 3 sugestões inventadas para 0.

O formato binário gerado aqui é lido por
lib/features/spellcheck/data/bloom_dictionary.dart — as duas pontas têm que
concordar no hash (MurmurHash3 x86_32) e na normalização das palavras.
Qualquer mudança aqui exige a mudança espelhada lá.
"""

from __future__ import annotations

import argparse
import math
import os
import re
import struct
import sys
import urllib.request
from collections import defaultdict

REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS_DIR = os.path.join(REPO_ROOT, 'assets', 'dictionaries')
CACHE_DIR = os.path.join(REPO_ROOT, 'build', 'dictionary_src')

BASE_URL = 'https://raw.githubusercontent.com/LibreOffice/dictionaries/master'

# Idioma -> pasta do repositório de dicionários do LibreOffice.
LANGUAGES = {
    'pt_BR': 'pt_BR',
    'en_US': 'en',
}

MAGIC = b'PROSABLM'
VERSION = 1
HEADER_SIZE = 64

# Tamanho dos n-gramas do modelo de plausibilidade. 3 seria permissivo demais
# (0,70% das sequências aleatórias passam) e 5 encheria de detalhe sem ganho:
# com 4, só 0,08% passa, e o modelo cabe em 88 mil entradas.
NGRAM_SIZE = 4

# Segmentos que aparecem entre hífens no português e não são palavras
# soltas: pronomes oblíquos da ênclise (chamá-lo, dar-se) e as terminações
# de futuro/condicional da mesóclise (dar-te-ei, dar-te-íamos). Ficam de
# fora do filtro porque só valem colados por hífen — a mesma lista existe em
# word_tokenizer.dart, que aceita esses pedaços ao validar palavra composta.
HYPHEN_GLUE = {
    'lo', 'la', 'los', 'las', 'no', 'na', 'nos', 'nas',
    'me', 'te', 'se', 'vos', 'lhe', 'lhes', 'o', 'a', 'os', 'as',
    'ei', 'ás', 'á', 'emos', 'eis', 'ão',
    'ia', 'ias', 'iam', 'íamos', 'íeis',
}

# Uma "palavra" verificável é feita só de letras e apóstrofo. Isso descarta
# dígitos, pontuação e as formas hifenizadas (tratadas por divisão, ver
# HYPHEN_GLUE). Espelhado em word_tokenizer.dart.
WORD_RE = re.compile(r"^[^\W\d_]+(?:'[^\W\d_]+)*$", re.UNICODE)


# ---------------------------------------------------------------- Hunspell

class AffixTable:
    """Regras de afixo de um .aff, indexadas por flag."""

    def __init__(self) -> None:
        self.sfx: dict[str, list[tuple]] = defaultdict(list)
        self.pfx: dict[str, list[tuple]] = defaultdict(list)
        self.forbidden_flag: str | None = None
        self.only_in_compound_flag: str | None = None
        self.need_affix_flag: str | None = None
        self.flag_mode = 'single'  # single | long | num
        self.iconv: list[tuple[str, str]] = []


def parse_aff(path: str) -> AffixTable:
    table = AffixTable()
    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = fh.read().splitlines()

    i = 0
    while i < len(lines):
        line = lines[i]
        parts = line.split()
        if not parts:
            i += 1
            continue

        key = parts[0]
        if key == 'FLAG' and len(parts) > 1:
            if parts[1] == 'long':
                table.flag_mode = 'long'
            elif parts[1] == 'num':
                table.flag_mode = 'num'
        elif key == 'FORBIDDENWORD' and len(parts) > 1:
            table.forbidden_flag = parts[1]
        elif key == 'ONLYINCOMPOUND' and len(parts) > 1:
            table.only_in_compound_flag = parts[1]
        elif key in ('NEEDAFFIX', 'PSEUDOROOT') and len(parts) > 1:
            table.need_affix_flag = parts[1]
        elif key == 'ICONV' and len(parts) == 3:
            table.iconv.append((parts[1], parts[2]))
        elif key == 'AF':
            # Aliases numéricos de flags: nenhum dos dicionários que usamos
            # tem isso, e ignorar em silêncio geraria um dicionário com
            # metade das formas faltando.
            raise SystemExit(f'{path}: diretiva AF (alias de flags) não suportada')
        elif key in ('SFX', 'PFX') and len(parts) >= 4 \
                and parts[2] in ('Y', 'N') and parts[3].isdigit():
            # Cabeçalho: "SFX <flag> <Y|N cross-product> <n regras>"
            flag, cross, count = parts[1], parts[2] == 'Y', int(parts[3])
            target = table.sfx if key == 'SFX' else table.pfx
            for j in range(i + 1, min(i + 1 + count, len(lines))):
                rule = lines[j].split()
                if len(rule) < 4 or rule[0] != key:
                    continue
                strip = '' if rule[2] == '0' else rule[2]
                # O campo de adição pode trazer flags próprias ("ado/XY"):
                # são afixos encadeáveis, que ignoramos (só o texto importa).
                add = '' if rule[3] == '0' else rule[3].split('/')[0]
                cond = rule[4] if len(rule) > 4 else '.'
                if cond == '.':
                    condition = None
                elif key == 'SFX':
                    condition = re.compile(cond + '$')
                else:
                    condition = re.compile('^' + cond)
                target[flag].append((strip, add, condition, cross))
            i += count + 1
            continue

        i += 1

    return table


def split_flags(raw: str, mode: str) -> list[str]:
    if not raw:
        return []
    if mode == 'num':
        return [f for f in raw.split(',') if f]
    if mode == 'long':
        return [raw[k:k + 2] for k in range(0, len(raw) - 1, 2)]
    return list(raw)


def apply_suffix(word: str, rule: tuple) -> str | None:
    strip, add, condition, _ = rule
    if strip and not word.endswith(strip):
        return None
    if condition and not condition.search(word):
        return None
    base = word[: len(word) - len(strip)] if strip else word
    return base + add


def apply_prefix(word: str, rule: tuple) -> str | None:
    strip, add, condition, _ = rule
    if strip and not word.startswith(strip):
        return None
    if condition and not condition.match(word):
        return None
    return add + word[len(strip):]


def expand(aff: AffixTable, dic_path: str) -> tuple[set[str], set[str]]:
    """Devolve (formas geradas, formas proibidas) já com ICONV aplicado."""
    forms: set[str] = set()
    forbidden: set[str] = set()

    def emit(target: set[str], word: str) -> None:
        for src, dst in aff.iconv:
            word = word.replace(src, dst)
        target.add(word)

    with open(dic_path, encoding='utf-8', errors='replace') as fh:
        fh.readline()  # primeira linha é a contagem de entradas
        for line in fh:
            line = line.strip().lstrip('﻿')
            if not line:
                continue
            # Campos morfológicos ("po:noun") vêm depois de tab/espaço.
            line = re.split(r'[\t ]', line, maxsplit=1)[0]
            word, _, raw_flags = line.partition('/')
            word = word.replace('\\', '')
            if not word:
                continue

            flags = split_flags(raw_flags, aff.flag_mode)
            flag_set = set(flags)
            target = forms
            if aff.forbidden_flag and aff.forbidden_flag in flag_set:
                target = forbidden

            # NEEDAFFIX/ONLYINCOMPOUND: o radical sozinho não é palavra, mas
            # as formas com afixo são.
            bare_is_word = not (
                (aff.need_affix_flag and aff.need_affix_flag in flag_set)
                or (aff.only_in_compound_flag
                    and aff.only_in_compound_flag in flag_set)
            )
            if bare_is_word:
                emit(target, word)

            # Sufixos primeiro; os que permitem cross-product viram base
            # para os prefixos (é assim que "desfazíamos" aparece).
            cross_bases = []
            for flag in flags:
                for rule in aff.sfx.get(flag, ()):
                    generated = apply_suffix(word, rule)
                    if generated is None:
                        continue
                    emit(target, generated)
                    if rule[3]:
                        cross_bases.append(generated)

            for flag in flags:
                for rule in aff.pfx.get(flag, ()):
                    bases = [word] + (cross_bases if rule[3] else [])
                    for base in bases:
                        generated = apply_prefix(base, rule)
                        if generated is not None:
                            emit(target, generated)

    return forms, forbidden


def normalize(word: str) -> str:
    """Mesma normalização do lado Dart: apóstrofo tipográfico e minúsculas."""
    return word.replace('’', "'").lower()


def collect_words(forms: set[str], forbidden: set[str]) -> set[str]:
    """Separa as formas simples e recupera os pedaços úteis das hifenizadas.

    As hifenizadas (7,8 milhões no pt_BR, quase todas topônimo+UF) ficam de
    fora: em runtime a palavra composta é validada pedaço por pedaço. Só que
    a ênclise cria pedaços que não existem soltos — "chamá-lo" parte em
    "chamá", "chamávamo-lo" em "chamávamo" — e esses precisam entrar, senão
    o editor sublinharia construção correta e comum em literatura.
    """
    banned = {normalize(w) for w in forbidden}
    simple: set[str] = set()
    hyphenated: list[str] = []

    for form in forms:
        word = normalize(form)
        if word in banned:
            continue
        if '-' in word:
            hyphenated.append(word)
        elif WORD_RE.match(word):
            simple.add(word)

    orphans: set[str] = set()
    for word in hyphenated:
        for segment in word.split('-'):
            if (segment and segment not in simple and segment not in HYPHEN_GLUE
                    and segment not in banned and WORD_RE.match(segment)):
                orphans.add(segment)

    return simple | orphans


# ------------------------------------------------------------ Bloom filter

def murmur3_32(data: bytes, seed: int) -> int:
    """MurmurHash3 x86_32 — espelhado em bloom_dictionary.dart."""
    c1, c2 = 0xCC9E2D51, 0x1B873593
    mask = 0xFFFFFFFF
    h = seed & mask
    length = len(data)
    nblocks = length // 4

    for i in range(nblocks):
        k = int.from_bytes(data[i * 4:i * 4 + 4], 'little')
        k = (k * c1) & mask
        k = ((k << 15) | (k >> 17)) & mask
        k = (k * c2) & mask
        h ^= k
        h = ((h << 13) | (h >> 19)) & mask
        h = (h * 5 + 0xE6546B64) & mask

    tail = data[nblocks * 4:]
    if tail:
        k = 0
        for i, byte in enumerate(tail):
            k |= byte << (8 * i)
        k = (k * c1) & mask
        k = ((k << 15) | (k >> 17)) & mask
        k = (k * c2) & mask
        h ^= k

    h ^= length
    h ^= h >> 16
    h = (h * 0x85EBCA6B) & mask
    h ^= h >> 13
    h = (h * 0xC2B2AE35) & mask
    h ^= h >> 16
    return h


SEED_A = 0x00000000
SEED_B = 0x9747B28C


def bloom_params(n: int, error: float) -> tuple[int, int]:
    m = math.ceil(-n * math.log(error) / (math.log(2) ** 2))
    m += (8 - m % 8) % 8  # múltiplo de 8 bits, para o arquivo fechar em bytes
    k = max(1, min(64, round(m / n * math.log(2))))
    return m, k


def build_bloom(words: set[str], error: float) -> tuple[bytearray, int, int]:
    n = len(words)
    m, k = bloom_params(n, error)
    bits = bytearray(m // 8)
    for word in words:
        data = word.encode('utf-8')
        h1 = murmur3_32(data, SEED_A)
        h2 = murmur3_32(data, SEED_B) | 1  # ímpar: percorre o vetor todo
        for i in range(k):
            position = (h1 + i * h2) % m
            bits[position >> 3] |= 1 << (position & 7)
    return bits, m, k


def contains(bits: bytes, m: int, k: int, word: str) -> bool:
    data = word.encode('utf-8')
    h1 = murmur3_32(data, SEED_A)
    h2 = murmur3_32(data, SEED_B) | 1
    for i in range(k):
        position = (h1 + i * h2) % m
        if not bits[position >> 3] >> (position & 7) & 1:
            return False
    return True


def write_asset(path: str, lang: str, bits: bytearray, m: int, k: int, n: int) -> None:
    header = bytearray(HEADER_SIZE)
    header[0:8] = MAGIC
    struct.pack_into('<HH I Q Q', header, 8, VERSION, k, 0, m, n)
    lang_bytes = lang.encode('ascii')
    header[32:32 + len(lang_bytes)] = lang_bytes
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, 'wb') as fh:
        fh.write(header)
        fh.write(bits)


# ---------------------------------------------------------------- pipeline

def fetch(lang: str, folder: str, extension: str) -> str:
    os.makedirs(CACHE_DIR, exist_ok=True)
    local = os.path.join(CACHE_DIR, f'{lang}.{extension}')
    if os.path.exists(local) and os.path.getsize(local) > 0:
        return local
    url = f'{BASE_URL}/{folder}/{lang}.{extension}'
    print(f'  baixando {url}')
    with urllib.request.urlopen(url, timeout=120) as response:
        payload = response.read()
    with open(local, 'wb') as fh:
        fh.write(payload)
    return local


SANITY = {
    'pt_BR': ['casa', 'livro', 'escrevêssemos', 'correríamos', 'chamá', 'guarda'],
    'en_US': ['house', 'book', 'running', 'wrote', 'quickly'],
}


def ngrams(word: str) -> set[str]:
    """4-gramas da palavra, com marcas de início e fim.

    As marcas são o que barra sequências impossíveis na borda: em português
    nenhuma palavra começa com "ç", e essa informação só existe se o início
    for parte do n-grama. Espelhado em plausibility_model.dart.
    """
    padded = f'^{word}$'
    if len(padded) < NGRAM_SIZE:
        return {padded}
    return {padded[i:i + NGRAM_SIZE] for i in range(len(padded) - NGRAM_SIZE + 1)}


def collect_ngrams(words: set[str]) -> set[str]:
    model: set[str] = set()
    for word in words:
        model |= ngrams(word)
    return model


def build_language(lang: str, error: float, force: bool) -> None:
    output = os.path.join(ASSETS_DIR, f'{lang}.bloom')
    ngram_output = os.path.join(ASSETS_DIR, f'{lang}.ngram.bloom')
    if os.path.exists(output) and os.path.exists(ngram_output) and not force:
        print(f'{lang}: já existe ({output}), use --force para regerar')
        return

    print(f'{lang}:')
    aff_path = fetch(lang, LANGUAGES[lang], 'aff')
    dic_path = fetch(lang, LANGUAGES[lang], 'dic')

    aff = parse_aff(aff_path)
    forms, forbidden = expand(aff, dic_path)
    print(f'  formas geradas: {len(forms):,} (proibidas: {len(forbidden):,})')

    words = collect_words(forms, forbidden)
    print(f'  palavras no filtro: {len(words):,}')

    bits, m, k = build_bloom(words, error)
    write_asset(output, lang, bits, m, k, len(words))
    size_mb = (HEADER_SIZE + len(bits)) / 1024 / 1024
    print(f'  {output}: {size_mb:.2f} MB (m={m:,} bits, k={k}, erro={error:g})')

    # Sem esta checagem um bug de parsing produz um arquivo do tamanho certo
    # e completamente vazio de conteúdo útil.
    missing = [w for w in SANITY.get(lang, []) if not contains(bits, m, k, w)]
    if missing:
        raise SystemExit(f'  ERRO: palavras que deveriam existir faltando: {missing}')
    print('  verificação de sanidade: ok')

    model = collect_ngrams(words)
    ngram_bits, ngram_m, ngram_k = build_bloom(model, error)
    write_asset(ngram_output, lang, ngram_bits, ngram_m, ngram_k, len(model))
    ngram_kb = (HEADER_SIZE + len(ngram_bits)) / 1024
    print(f'  {ngram_output}: {ngram_kb:.0f} KB '
          f'({len(model):,} {NGRAM_SIZE}-gramas, k={ngram_k})')

    # Palavra real tem de passar pelo modelo — ele foi construído a partir
    # delas. Se isto falhar, o modelo está inutilizável (barraria correções
    # legítimas).
    for word in SANITY.get(lang, []):
        for gram in ngrams(word):
            if not contains(ngram_bits, ngram_m, ngram_k, gram):
                raise SystemExit(f'  ERRO: 4-grama "{gram}" de "{word}" ausente do modelo')
    print('  modelo de n-gramas: ok')


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--lang', choices=sorted(LANGUAGES), action='append')
    parser.add_argument('--error', type=float, default=0.0001,
                        help='taxa de falso positivo alvo (padrão: 0.0001)')
    parser.add_argument('--force', action='store_true')
    args = parser.parse_args()

    for lang in (args.lang or sorted(LANGUAGES)):
        build_language(lang, args.error, args.force)
    return 0


if __name__ == '__main__':
    sys.exit(main())
