import 'package:flutter_test/flutter_test.dart';
import 'package:chatme/core/utils/link_utils.dart';

void main() {
  String? find(String text) => LinkUtils.extractFirstUrl(text);

  test('finds https and http links anywhere in the text', () {
    expect(find('https://example.com/a'), 'https://example.com/a');
    expect(find('cek https://example.com/a bagus'), 'https://example.com/a');
    expect(find('di akhir http://example.com'), 'http://example.com');
  });

  test('turns www links into https', () {
    expect(find('buka www.contoh.com sekarang'), 'https://www.contoh.com');
    expect(find('www.contoh.com/halaman?x=1'), 'https://www.contoh.com/halaman?x=1');
  });

  test('ignores domains without http, https or www', () {
    expect(find('kunjungi github.com/elregann'), isNull);
    expect(find('file.txt dan halo.apa'), isNull);
    expect(find('tidak ada link di sini'), isNull);
  });

  test('ignores www glued to other text', () {
    expect(find('kirim ke me@www.contoh.com'), isNull);
    expect(find('xwww.contoh.com'), isNull);
    expect(find('a.www.contoh.com'), isNull);
  });

  test('needs a host with a dot', () {
    expect(find('http://localhost:3000'), isNull);
    expect(find('https://'), isNull);
    expect(find('www.halo'), isNull);
  });

  test('drops trailing punctuation and brackets', () {
    expect(find('lihat https://example.com.'), 'https://example.com');
    expect(find('lihat https://example.com/a, ya'), 'https://example.com/a');
    expect(find('lihat (https://example.com/x) ya'), 'https://example.com/x');
  });

  test('skips an invalid candidate and returns the next real link', () {
    expect(find('http://localhost lalu https://a.com'), 'https://a.com');
  });
}
