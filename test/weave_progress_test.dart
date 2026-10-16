import 'package:flutter_test/flutter_test.dart';
import 'package:farash/features/weaving/woven_rug.dart';

void main() {
  test('completion boundaries roll into a collection and undo reverses it', () {
    expect(const WeaveProgress(0).rugs, 0);
    expect(const WeaveProgress(49).rows, 49);
    expect(const WeaveProgress(50).rugs, 1);
    expect(const WeaveProgress(50).rows, 0);
    expect(const WeaveProgress(51).rows, 1);
    expect(const WeaveProgress(49).rugs, 0);
    expect(const WeaveProgress(1000000).rugs, 20000);
  });
}
