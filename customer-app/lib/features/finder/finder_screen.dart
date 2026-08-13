import 'package:flutter/material.dart';

import '../../models/app_data.dart';
import '../../models/cocktail_models.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/brand_widgets.dart';
import '../../shared/widgets/cocktail_card_widgets.dart';
import 'widgets/finder_filter_widgets.dart';
import 'widgets/finder_header.dart';

class FinderScreen extends StatefulWidget {
  final AppData data;
  final void Function(Cocktail cocktail, String? liquorTypeId) onOpenCocktail;
  final String? initialLiquorTypeId;

  /// Set when the Finder is pushed as a route (it no longer has a nav tab),
  /// which is when it needs a way back.
  final VoidCallback? onBack;

  const FinderScreen({
    super.key,
    required this.data,
    required this.initialLiquorTypeId,
    required this.onOpenCocktail,
    this.onBack,
  });

  @override
  State<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends State<FinderScreen> {
  final Set<String> selectedLiquorTypeIds = <String>{};
  final Set<String> selectedProductTagNames = <String>{};
  final TextEditingController searchController = TextEditingController();

  int sortIndex = 0;
  late Future<CocktailSearchResult> resultsFuture;

  @override
  void initState() {
    super.initState();
    AnalyticsService.logScreenView('cocktail_finder');

    final initialLiquorTypeId = widget.initialLiquorTypeId?.trim();
    if (initialLiquorTypeId != null && initialLiquorTypeId.isNotEmpty) {
      selectedLiquorTypeIds.add(initialLiquorTypeId);
    }

    resultsFuture = loadResults();
  }

  @override
  void didUpdateWidget(covariant FinderScreen oldWidget) {
    super.didUpdateWidget(oldWidget);

    var shouldReload = false;

    if (oldWidget.data.selectedLocationId != widget.data.selectedLocationId) {
      shouldReload = true;
    }

    if (oldWidget.initialLiquorTypeId != widget.initialLiquorTypeId) {
      final initialLiquorTypeId = widget.initialLiquorTypeId?.trim();

      if (initialLiquorTypeId != null && initialLiquorTypeId.isNotEmpty) {
        selectedLiquorTypeIds
          ..clear()
          ..add(initialLiquorTypeId);

        shouldReload = true;
      }
    }

    if (shouldReload) {
      resultsFuture = loadResults();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    super.dispose();
  }

  Future<CocktailSearchResult> loadResults() {
    final sortOptions = widget.data.finderOptions.sortOptions;
    final safeSortIndex = sortOptions.isEmpty
        ? 0
        : sortIndex.clamp(0, sortOptions.length - 1).toInt();
    final sort = sortOptions.isEmpty
        ? 'featured'
        : sortOptions[safeSortIndex].value;

    return ApiService.fetchCocktails(
      locationId: widget.data.selectedLocationId,
      liquorTypeIds: selectedLiquorTypeIds,
      tagNames: selectedProductTagNames,
      searchText: searchController.text,
      sort: sort,
    );
  }

  void reloadResults() {
    setState(() {
      resultsFuture = loadResults();
    });
  }

  /// Adds or removes a bottle and reports the choice — the Finder's first
  /// funnel step, and the one nothing else records. What follows it is
  /// ordinary product tracking: the cocktails opened from these results carry
  /// [AnalyticsSource.cocktailFinder], and so does anything added from them.
  ///
  /// The name, not the id, is what the report reads; an id no longer in the
  /// payload has no name to report, so the toggle still happens and only the
  /// event is skipped.
  void toggleLiquorType(String liquorTypeId) {
    final isSelected = !selectedLiquorTypeIds.contains(liquorTypeId);

    setState(() {
      if (isSelected) {
        selectedLiquorTypeIds.add(liquorTypeId);
      } else {
        selectedLiquorTypeIds.remove(liquorTypeId);
      }

      resultsFuture = loadResults();
    });

    final bottle = widget.data.liquorTypes
        .where((liquor) => liquor.id == liquorTypeId)
        .firstOrNull;
    if (bottle == null) return;

    AnalyticsService.logFinderBottleChanged(
      bottleName: bottle.name,
      isSelected: isSelected,
      selectionCount: selectedLiquorTypeIds.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    final onBack = widget.onBack;

    return SafeArea(
      child: Stack(
        children: [
          buildScroll(),
          // The way back stays put while the page scrolls, rather than leaving
          // with the header it used to sit in.
          if (onBack != null)
            Positioned(
              left: 22,
              top: 14,
              child: CircleIconButton(icon: Icons.arrow_back, onTap: onBack),
            ),
        ],
      ),
    );
  }

  Widget buildScroll() {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: FinderHeader(
            liquorTypes: widget.data.liquorTypes,
            onBack: widget.onBack,
            selectedLiquorTypeIds: selectedLiquorTypeIds,
            onToggle: toggleLiquorType,
            onClear: () {
              selectedLiquorTypeIds.clear();
              selectedProductTagNames.clear();
              reloadResults();
            },
          ),
        ),
        if (widget.data.finderOptions.productTags.isNotEmpty)
          SliverToBoxAdapter(
            child: ProductTagFilterSection(
              productTags: widget.data.finderOptions.productTags,
              selectedTagNames: selectedProductTagNames,
              onToggle: (tagName) {
                setState(() {
                  if (selectedProductTagNames.contains(tagName)) {
                    selectedProductTagNames.remove(tagName);
                  } else {
                    selectedProductTagNames.add(tagName);
                  }
                  resultsFuture = loadResults();
                });
              },
              onClear: () {
                selectedProductTagNames.clear();
                reloadResults();
              },
            ),
          ),
        SliverToBoxAdapter(
          child: SelectedChips(
            liquorTypes: widget.data.liquorTypes,
            productTags: widget.data.finderOptions.productTags,
            selectedLiquorTypeIds: selectedLiquorTypeIds,
            selectedProductTagNames: selectedProductTagNames,
            // The chip's X is the same choice as un-tapping the bottle, so it
            // goes through the same path and is reported the same way.
            onRemoveLiquor: toggleLiquorType,
            onRemoveTag: (name) {
              selectedProductTagNames.remove(name);
              reloadResults();
            },
          ),
        ),
        SliverToBoxAdapter(
          child: FinderSearchBox(
            controller: searchController,
            onSubmitted: (_) {
              AnalyticsService.logSearch(
                surface: 'cocktail_finder',
                hasQuery: searchController.text.trim().isNotEmpty,
              );
              reloadResults();
            },
            onClear: () {
              searchController.clear();
              reloadResults();
            },
          ),
        ),
        SliverToBoxAdapter(
          child: FutureBuilder<CocktailSearchResult>(
            future: resultsFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const EbtlLoadingSection(label: 'Finding cocktails...');
              }

              if (snapshot.hasError) {
                return InlineErrorCard(
                  message: apiErrorMessage(snapshot.error!),
                  onRetry: reloadResults,
                );
              }

              final result =
                  snapshot.data ??
                  const CocktailSearchResult(
                    results: [],
                    total: 0,
                    page: 1,
                    pageSize: 50,
                  );

              return Column(
                children: [
                  FinderResultsHeader(
                    count: result.total,
                    sortOptions: widget.data.finderOptions.sortOptions,
                    sortIndex: sortIndex,
                    onSortChanged: (index) {
                      setState(() {
                        sortIndex = index;
                        resultsFuture = loadResults();
                      });
                    },
                  ),
                  if (result.results.isEmpty)
                    const EmptyStateCard(
                      message: 'No cocktails match your current filters.',
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 10, 22, 28),
                      child: GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: result.results.length,
                        gridDelegate:
                            const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              mainAxisSpacing: 14,
                              crossAxisSpacing: 14,
                              childAspectRatio: 0.62,
                            ),
                        itemBuilder: (context, index) {
                          final cocktail = result.results[index];
                          final detailLiquorTypeId =
                              selectedLiquorTypeIds.length == 1
                              ? selectedLiquorTypeIds.first
                              : null;

                          return CocktailGridCard(
                            cocktail: cocktail,
                            onTap: () => widget.onOpenCocktail(
                              cocktail,
                              detailLiquorTypeId,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
