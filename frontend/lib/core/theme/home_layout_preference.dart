/// Internal dashboard presentations. Home uses Coffee Counter only;
/// these values no longer represent a saved or user-selectable preference.
enum HomeLayout {
  classic('Classic', 'A familiar dashboard with organized shortcuts.'),
  modern('Modern', 'A spacious dashboard with sales in focus.'),
  coffeeCounter(
      'Coffee Counter', 'Colorful shortcuts for everyday coffee shop tasks.');

  const HomeLayout(this.label, this.description);
  final String label;
  final String description;
}
