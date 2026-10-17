/// Tender suggestions use the existing USD accounting unit.
/// Riel conversion requires an explicitly configured business exchange rate.
List<double> cashQuickAmounts(double total) {
  if (!total.isFinite || total < 0) return const [];
  final cents = (total * 100).round();
  const banknotes = [500, 1000, 2000, 5000, 10000];
  final candidates = <int>{cents};
  for (final note in banknotes) {
    if (note >= cents) candidates.add(note);
  }
  if (cents > banknotes.last) {
    candidates.add(((cents + banknotes.last - 1) ~/ banknotes.last) * banknotes.last);
  }
  final ordered = candidates.toList()..sort();
  return ordered.take(4).map((value) => value / 100).toList();
}
