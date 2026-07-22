class CocktailAssets {
  static String forName(String name) {
    final clean = name.toLowerCase();

    if (clean.contains('paloma')) return 'assets/images/paloma.jpg';
    if (clean.contains('mojito')) return 'assets/images/mojito.jpg';
    if (clean.contains('espresso')) return 'assets/images/espresso_martini.jpg';
    if (clean.contains('aperol')) return 'assets/images/aperol_spritz.jpg';
    if (clean.contains('pina') || clean.contains('piña')) {
      return 'assets/images/pina_colada.jpg';
    }

    return 'assets/images/cocktail_placeholder.jpg';
  }
}
