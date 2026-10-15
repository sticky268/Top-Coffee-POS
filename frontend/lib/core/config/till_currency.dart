/// Shop-approved display/shortcut rate; payment accounting remains in USD.
/// Changing this rate never rewrites historical orders or rounds change.
class TillCurrency {
  static const int rielPerDollar = 4000;

  static int rielForUsd(double usd) => ((usd * 100).round() * rielPerDollar ~/ 100);

  /// Only banknotes exactly representable in USD cents are offered.
  static List<int> rielQuickAmounts(double totalUsd) {
    if (!totalUsd.isFinite || totalUsd < 0) return const [];
    final cents = (totalUsd * 100).round();
    const notes = [1000, 2000, 5000, 10000, 20000, 50000, 100000];
    return notes.where((note) =>
      note * 100 % rielPerDollar == 0 &&
      note * 100 ~/ rielPerDollar >= cents).take(4).toList();
  }

  static double usdForRielNote(int riel) {
    if (riel < 0 || riel * 100 % rielPerDollar != 0) {
      throw ArgumentError('This riel amount cannot be represented exactly in USD cents.');
    }
    return (riel * 100 ~/ rielPerDollar) / 100;
  }
}
