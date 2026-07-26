import 'package:flutter/material.dart';

import '../../models/app_data.dart';
import '../../models/cocktail_models.dart';
import '../../services/analytics_service.dart';
import '../../services/api_service.dart';
import '../../core/network/api_exception.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/cocktail_card_widgets.dart';
import 'widgets/finder_filter_widgets.dart';
import 'widgets/finder_header.dart';

class FinderScreen extends StatefulWidget {
  final AppData data;
  final void Function(Cocktail cocktail, String? liquorTypeId) onOpenCocktail;
  final String? initialLiquorTypeId;

  const FinderScreen({
    super.key,
    required this.data,
    required this.initialLiquorTypeId,
    required this.onOpenCocktail,
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: FinderHeader(
              liquorTypes: widget.data.liquorTypes,
              selectedLiquorTypeIds: selectedLiquorTypeIds,
              onToggle: (liquorTypeId) {
                setState(() {
                  if (selectedLiquorTypeIds.contains(liquorTypeId)) {
                    selectedLiquorTypeIds.remove(liquorTypeId);
                  } else {
                    selectedLiquorTypeIds.add(liquorTypeId);
                  }
                  resultsFuture = loadResults();
                });
              },
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
              onRemoveLiquor: (id) {
                selectedLiquorTypeIds.remove(id);
                reloadResults();
              },
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
                  return const EbtlLoadingSection(
                    label: 'Finding cocktails...',
                  );
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
      ),
    );
  }
}
