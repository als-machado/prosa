import 'dart:convert';
import 'dart:typed_data';

/// Leitor do dicionário em filtro de Bloom gerado por
/// `scripts/build_dictionaries.py`.
///
/// O filtro guarda apenas bits — nenhuma palavra. Consultar é ligar k
/// posições calculadas por hash e ver se todas estão em 1:
///
/// * algum bit em 0 → a palavra **com certeza** não está no dicionário;
/// * todos em 1 → está, com uma chance de erro de 1 em 10.000.
///
/// O erro é assimétrico e a favor de quem escreve: palavra correta jamais é
/// sublinhada; o que acontece, raramente, é um erro de digitação passar
/// batido. Foi o que permitiu caber 2,78 milhões de formas do português em
/// 6,4 MB (o mesmo conteúdo daria mais de 200 MB como `Set<String>`).
class BloomDictionary {
  static const _magic = 'PROSABLM';
  static const _headerSize = 64;
  static const _supportedVersion = 1;

  /// Sementes do MurmurHash3. Precisam ser idênticas às do script Python —
  /// mudar uma ponta sem a outra transforma o dicionário em ruído.
  static const _seedA = 0x00000000;
  static const _seedB = 0x9747B28C;

  final Uint8List _bits;
  final int _bitCount;
  final int _hashCount;

  /// Código do idioma gravado no arquivo (`pt_BR`).
  final String language;

  /// Quantas palavras foram inseridas no filtro.
  final int wordCount;

  // Posicional porque parâmetro nomeado não pode começar com underscore, e
  // estes três campos são privados. É construído num único lugar, logo abaixo.
  const BloomDictionary._(
    this._bits,
    this._bitCount,
    this._hashCount,
    this.language,
    this.wordCount,
  );

  /// Lê o cabeçalho de 64 bytes e aponta para o vetor de bits.
  ///
  /// Não copia nada: o vetor é uma vista sobre os mesmos bytes do asset.
  factory BloomDictionary.fromBytes(Uint8List bytes) {
    if (bytes.length < _headerSize) {
      throw const FormatException('Dicionário truncado');
    }
    final magic = String.fromCharCodes(bytes.sublist(0, 8));
    if (magic != _magic) {
      throw FormatException('Assinatura inesperada no dicionário: "$magic"');
    }

    final header = ByteData.sublistView(bytes, 0, _headerSize);
    final version = header.getUint16(8, Endian.little);
    if (version != _supportedVersion) {
      throw FormatException('Versão de dicionário não suportada: $version');
    }
    final hashCount = header.getUint16(10, Endian.little);
    final bitCount = header.getUint64(16, Endian.little);
    final wordCount = header.getUint64(24, Endian.little);

    final languageBytes = bytes.sublist(32, 48).takeWhile((b) => b != 0);
    final bits = Uint8List.sublistView(bytes, _headerSize);

    if (bits.length * 8 < bitCount) {
      throw const FormatException('Vetor de bits menor do que o cabeçalho diz');
    }
    if (hashCount < 1 || bitCount < 8) {
      throw const FormatException('Parâmetros inválidos no dicionário');
    }

    return BloomDictionary._(
      bits,
      bitCount,
      hashCount,
      String.fromCharCodes(languageBytes),
      wordCount,
    );
  }

  /// Consulta a palavra. Espera-se que já venha normalizada por
  /// `WordTokenizer.normalize` — o filtro só contém minúsculas.
  bool contains(String word) {
    if (word.isEmpty) return false;
    final bytes = const Utf8Encoder().convert(word);
    final h1 = _murmur3(bytes, _seedA);
    // Ímpar para que a progressão (h1 + i*h2) percorra o vetor inteiro:
    // com _bitCount par, um h2 par visitaria só metade das posições.
    final h2 = _murmur3(bytes, _seedB) | 1;
    for (var i = 0; i < _hashCount; i++) {
      final position = (h1 + i * h2) % _bitCount;
      if ((_bits[position >> 3] >> (position & 7)) & 1 == 0) return false;
    }
    return true;
  }

  /// MurmurHash3 x86_32. Espelho exato de `murmur3_32` em
  /// `scripts/build_dictionaries.py`.
  ///
  /// As multiplicações estouram 32 bits de propósito: em complemento de dois
  /// os bits baixos sobrevivem ao estouro, e a máscara descarta o resto —
  /// é assim que a versão de referência em C se comporta.
  static int _murmur3(Uint8List data, int seed) {
    const c1 = 0xCC9E2D51;
    const c2 = 0x1B873593;
    const mask = 0xFFFFFFFF;

    var h = seed & mask;
    final blocks = data.length >> 2;

    for (var i = 0; i < blocks; i++) {
      final j = i << 2;
      var k = data[j] | (data[j + 1] << 8) | (data[j + 2] << 16) | (data[j + 3] << 24);
      k = (k * c1) & mask;
      k = ((k << 15) | (k >>> 17)) & mask;
      k = (k * c2) & mask;
      h ^= k;
      h = ((h << 13) | (h >>> 19)) & mask;
      h = (h * 5 + 0xE6546B64) & mask;
    }

    final remaining = data.length & 3;
    if (remaining != 0) {
      final base = blocks << 2;
      var k = 0;
      for (var i = 0; i < remaining; i++) {
        k |= data[base + i] << (8 * i);
      }
      k = (k * c1) & mask;
      k = ((k << 15) | (k >>> 17)) & mask;
      k = (k * c2) & mask;
      h ^= k;
    }

    h ^= data.length;
    h ^= h >>> 16;
    h = (h * 0x85EBCA6B) & mask;
    h ^= h >>> 13;
    h = (h * 0xC2B2AE35) & mask;
    h ^= h >>> 16;
    return h;
  }
}
