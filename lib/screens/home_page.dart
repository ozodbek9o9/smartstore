import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'theme_controller.dart';
import '../main.dart' show SmartStoreColors;
import '../utils/tenant_firestore.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _topProductsTabs;
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _debtSubscriptions = {};
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _paymentSubscriptions = {};

  List<_Document> _products = const [];
  List<_Document> _sales = const [];
  List<_Document> _customers = const [];
  List<_Document> _categories = const [];
  List<_Document> _entries = const [];
  final Map<String, List<_Document>> _customerDebts = {};
  final Map<String, List<_Document>> _customerPayments = {};
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onThemeChanged);
    _topProductsTabs = TabController(length: 3, vsync: this);
    _listenToDashboard();
  }

  void _onThemeChanged() {
    if (mounted) setState(() {});
  }

  void _listenToDashboard() {
    void listen(
      CollectionReference<Map<String, dynamic>> reference,
      void Function(List<_Document>) update,
    ) {
      _subscriptions.add(
        reference.snapshots().listen(
          (snapshot) {
            if (!mounted) return;
            setState(() {
              update(snapshot.docs.map(_Document.fromSnapshot).toList());
              _loading = false;
              _error = null;
            });
          },
          onError: (Object error) {
            if (mounted) {
              setState(() {
                _loading = false;
                _error = error;
              });
            }
          },
        ),
      );
    }

    listen(TenantFirestore.products, (value) => _products = value);
    listen(TenantFirestore.sales, (value) => _sales = value);
    listen(TenantFirestore.categories, (value) => _categories = value);
    listen(TenantFirestore.inventoryEntries, (value) => _entries = value);
    _subscriptions.add(
      TenantFirestore.customers.snapshots().listen(
        (snapshot) {
          if (!mounted) return;
          final customers = snapshot.docs.map(_Document.fromSnapshot).toList();
          _syncCustomerLedgerStreams(customers);
          setState(() {
            _customers = customers;
            _loading = false;
            _error = null;
          });
        },
        onError: (Object error) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = error;
            });
          }
        },
      ),
    );
  }

  void _syncCustomerLedgerStreams(List<_Document> customers) {
    final activeIds = customers.map((customer) => customer.id).toSet();
    for (final id in [..._debtSubscriptions.keys]) {
      if (!activeIds.contains(id)) {
        _debtSubscriptions.remove(id)?.cancel();
        _paymentSubscriptions.remove(id)?.cancel();
        _customerDebts.remove(id);
        _customerPayments.remove(id);
      }
    }
    for (final customer in customers) {
      if (_debtSubscriptions.containsKey(customer.id)) continue;
      _debtSubscriptions[customer.id] =
          TenantFirestore.customerDebts(customer.id).snapshots().listen((
            snapshot,
          ) {
            if (mounted) {
              setState(() {
                _customerDebts[customer.id] = snapshot.docs
                    .map(_Document.fromSnapshot)
                    .toList();
              });
            }
          });
      _paymentSubscriptions[customer.id] =
          TenantFirestore.customerPayments(customer.id).snapshots().listen((
            snapshot,
          ) {
            if (mounted) {
              setState(() {
                _customerPayments[customer.id] = snapshot.docs
                    .map(_Document.fromSnapshot)
                    .toList();
              });
            }
          });
    }
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onThemeChanged);
    _topProductsTabs.dispose();
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    for (final subscription in _debtSubscriptions.values) {
      subscription.cancel();
    }
    for (final subscription in _paymentSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overview = _DashboardOverview.fromData(
      context,
      products: _products,
      sales: _sales,
      customers: _customers,
      categories: _categories,
      entries: _entries,
      customerDebts: _customerDebts,
      customerPayments: _customerPayments,
    );

    final isDark = ThemeController.instance.isDarkMode;

    return ColoredBox(
      color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF3F6FE),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _products.isEmpty
          ? _DashboardError(error: _error!)
          : LayoutBuilder(
              builder: (context, constraints) {
                final veryWide = constraints.maxWidth >= 1500;
                final wide = constraints.maxWidth >= 1050;
                final medium = constraints.maxWidth >= 650;
                return ScrollConfiguration(
                  behavior: const MaterialScrollBehavior().copyWith(
                    scrollbars: true,
                    dragDevices: {
                      PointerDeviceKind.mouse,
                      PointerDeviceKind.touch,
                      PointerDeviceKind.stylus,
                      PointerDeviceKind.trackpad,
                    },
                    physics: const ClampingScrollPhysics(),
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(veryWide ? 24 : 16),
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _HeaderWidget(),
                        const SizedBox(height: 20),
                        _StatisticGrid(
                          overview: overview,
                          columns: medium ? 3 : 1,
                        ),
                        const SizedBox(height: 20),
                        _DebtSummary(
                          overview: overview,
                          columns: medium ? 3 : 1,
                        ),
                        const SizedBox(height: 20),
                        () {
                          final topProducts = _TopSellingProducts(
                            overview: overview,
                            controller: _topProductsTabs,
                          );
                          final bestProducts = _BestProducts(
                            overview: overview,
                          );
                          final warehouseRow = _WarehouseRow(
                            overview: overview,
                          );
                          if (veryWide || wide) {
                            return Column(
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 7, child: topProducts),
                                    const SizedBox(width: 14),
                                    Expanded(flex: 4, child: bestProducts),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                warehouseRow,
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                topProducts,
                                const SizedBox(height: 14),
                                bestProducts,
                                const SizedBox(height: 14),
                                warehouseRow,
                              ],
                            );
                          }
                        }(),
                        const SizedBox(height: 20),
                        () {
                          final unsold = _UnsoldProducts(overview: overview);
                          final lowest = _LowestSellingProducts(
                            overview: overview,
                          );
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 7, child: unsold),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 4, child: lowest),
                                  ],
                                )
                              : Column(
                                  children: [
                                    unsold,
                                    const SizedBox(height: 16),
                                    lowest,
                                  ],
                                );
                        }(),
                        const SizedBox(height: 20),
                        () {
                          final quick = _QuickStatistics(overview: overview);
                          final activities = _RecentActivities(
                            overview: overview,
                          );
                          return wide
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 4, child: quick),
                                    const SizedBox(width: 16),
                                    Expanded(flex: 7, child: activities),
                                  ],
                                )
                              : Column(
                                  children: [
                                    quick,
                                    const SizedBox(height: 16),
                                    activities,
                                  ],
                                );
                        }(),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _HeaderWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final localeCode = context.locale.languageCode == 'uz'
        ? 'uz'
        : context.locale.languageCode == 'ru'
        ? 'ru_RU'
        : 'en_US';
    final dateString = DateFormat("dd MMMM yyyy, EEEE", localeCode).format(now);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'home.greeting'.tr(),
                style: TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title(context),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'home.header_date'.tr(namedArgs: {'date': dateString}),
                style: TextStyle(fontSize: 13, color: AppTheme.muted(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatisticGrid extends StatelessWidget {
  const _StatisticGrid({required this.overview, this.columns = 3});
  final _DashboardOverview overview;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _StatisticCard(
        label: 'home.stat_products'.tr(),
        value: '${overview.products.length}',
        subLabel: 'home.stat_products_sub'.tr(
          args: ['${overview.todayProductsAdded}'],
        ),
        unit: 'home.stat_products_unit'.tr(),
        icon: Icons.inventory_2_rounded,
        gradient: const [Color(0xFF3B82F6), Color(0xFF2563EB)],
        showArrow: true,
      ),
      _StatisticCard(
        label: 'home.stat_inventory_value'.tr(),
        value: _money(overview.inventoryValue),
        subLabel: 'home.stat_inventory_value_sub'.tr(),
        unit: 'common.currency'.tr(),
        icon: Icons.attach_money_rounded,
        gradient: const [Color(0xFF22C55E), Color(0xFF16A34A)],
        showArrow: false,
      ),
      _StatisticCard(
        label: 'home.stat_customers'.tr(),
        value: '${overview.customers.length}',
        subLabel: 'home.stat_customers_sub'.tr(
          args: ['${overview.todayCustomers}'],
        ),
        unit: 'home.stat_customers_unit'.tr(),
        icon: Icons.people_alt_rounded,
        gradient: const [Color(0xFFA855F7), Color(0xFF9333EA)],
        showArrow: true,
      ),
    ];
    return GridView.count(
      crossAxisCount: columns,
      crossAxisSpacing: 20,
      mainAxisSpacing: 14,
      childAspectRatio: 2.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: cards,
    );
  }
}

class _StatisticCard extends StatelessWidget {
  const _StatisticCard({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.unit,
    required this.icon,
    required this.gradient,
    this.showArrow = false,
  });
  final String label, value, subLabel, unit;
  final IconData icon;
  final List<Color> gradient;
  final bool showArrow;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: gradient.last.withOpacity(.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppTheme.muted(context),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Flexible(
                        child: Text(
                          value,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: AppTheme.title(context),
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      if (unit.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            unit,
                            style: TextStyle(
                              color: AppTheme.muted(context),
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (showArrow) ...[
              Container(
                width: 14,
                height: 14,
                decoration: const BoxDecoration(
                  color: Color(0xFF16A34A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  color: Colors.white,
                  size: 9,
                ),
              ),
              const SizedBox(width: 6),
            ],
            Text(
              subLabel,
              style: TextStyle(
                color: showArrow
                    ? const Color(0xFF16A34A)
                    : AppTheme.muted(context),
                fontSize: 10,
                fontWeight: showArrow ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

class _DebtSummary extends StatelessWidget {
  const _DebtSummary({required this.overview, this.columns = 3});
  final _DashboardOverview overview;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final debtSalesCount =
        overview.sales.where((s) => s.boolean('isDebtSale')).length;
    final tiles = [
      _DebtTile(
        label: 'home.debt_total'.tr(),
        value: _money(overview.remainingDebt),
        subLabel: 'home.debt_total_sub'.tr(
          args: ['${overview.customersWithDebt}'],
        ),
        icon: Icons.account_balance_wallet_outlined,
        gradient: const [Color(0xFFF87171), Color(0xFFEF4444)],
      ),
      _DebtTile(
        label: 'home.debt_due'.tr(),
        value: _money(overview.debtSales),
        subLabel: 'home.debt_sales_sub'.tr(args: ['$debtSalesCount']),
        icon: Icons.access_time_rounded,
        gradient: const [Color(0xFFFBBF24), Color(0xFFF59E0B)],
      ),
      _DebtTile(
        label: 'home.debt_sales'.tr(),
        value: _money(overview.totalSales),
        subLabel: 'home.debt_sales_sub'.tr(args: ['${overview.sales.length}']),
        icon: Icons.shopping_bag_outlined,
        gradient: const [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
      ),
    ];

    return GridView.count(
      crossAxisCount: columns,
      crossAxisSpacing: 20,
      mainAxisSpacing: 14,
      childAspectRatio: 2.6,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      children: tiles,
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({
    required this.label,
    required this.value,
    required this.subLabel,
    required this.icon,
    required this.gradient,
  });
  final String label, value, subLabel;
  final IconData icon;
  final List<Color> gradient;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: gradient.last.withOpacity(.25),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.muted(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title(context),
                  letterSpacing: -0.2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.muted(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _TopSellingProducts extends StatelessWidget {
  const _TopSellingProducts({required this.overview, required this.controller});
  final _DashboardOverview overview;
  final TabController controller;

  @override
  Widget build(BuildContext context) => _Panel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFB923C), Color(0xFFEF4444)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.local_fire_department_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'home.top_selling_title'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title(context),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
          child: TabBar(
            controller: controller,
            labelColor: SmartStoreColors.primary,
            unselectedLabelColor: AppTheme.muted(context),
            labelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
            unselectedLabelStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            indicatorColor: SmartStoreColors.primary,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            dividerColor: AppTheme.cardBorder(context),
            tabs: [
              Tab(text: 'home.tab_today'.tr()),
              Tab(text: 'home.tab_week'.tr()),
              Tab(text: 'home.tab_month'.tr()),
            ],
          ),
        ),
        AnimatedBuilder(
          animation: controller,
          builder: (context, _) => _ProductSalesTable(
            rows: overview.topProducts(
              _TopPeriod.values[controller.index],
              context: context,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ProductSalesTable extends StatelessWidget {
  const _ProductSalesTable({required this.rows});
  final List<_ProductSales> rows;
  @override
  Widget build(BuildContext context) => rows.isEmpty
      ? const SizedBox(
          height: 220,
          child: _EmptyTable(labelKey: 'home.top_selling_empty'),
        )
      : SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: 700,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 10, 0),
                  child: _SalesHeader(),
                ),
                ...List.generate(rows.length, (index) {
                  final row = rows[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: _SalesRow(row: row, rank: index + 1),
                  );
                }),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
}

class _SalesHeader extends StatelessWidget {
  const _SalesHeader();
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    child: Row(
      children: [
        SizedBox(
          width: 40,
          child: Text('home.col_rank'.tr(), style: _tableHeaderStyle(context)),
        ),
        Expanded(
          child: Text(
            'home.col_product'.tr(),
            style: _tableHeaderStyle(context),
          ),
        ),
        SizedBox(
          width: 90,
          child: Text(
            'home.col_qty_sold'.tr(),
            textAlign: TextAlign.center,
            style: _tableHeaderStyle(context),
          ),
        ),
        SizedBox(
          width: 120,
          child: Text(
            'home.col_revenue'.tr(),
            textAlign: TextAlign.right,
            style: _tableHeaderStyle(context),
          ),
        ),
        SizedBox(
          width: 110,
          child: Text(
            'home.col_profit'.tr(),
            textAlign: TextAlign.right,
            style: _tableHeaderStyle(context),
          ),
        ),
      ],
    ),
  );
}

TextStyle _tableHeaderStyle(BuildContext context) => TextStyle(
  fontSize: 12,
  fontWeight: FontWeight.w600,
  color: AppTheme.title(context),
);

class _SalesRow extends StatelessWidget {
  const _SalesRow({required this.row, required this.rank});
  final _ProductSales row;
  final int rank;
  @override
  Widget build(BuildContext context) {
    const medalIcons = ['🥇', '🥈', '🥉'];
    final isMedal = rank <= 3;
    return Container(
      margin: EdgeInsets.only(bottom: 2),
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: isMedal ? AppTheme.medalBg(context, rank) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 40,
            child: Text(
              isMedal ? medalIcons[rank - 1] : '$rank',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          Expanded(
            child: Text(
              row.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.title(context),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _number(row.quantity),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppTheme.title(context),
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Text(
              _money(row.revenue),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppTheme.title(context),
              ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              _money(row.profit),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: row.profit >= 0
                    ? const Color(0xFF16A34A)
                    : const Color(0xFFEF4444),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BestProducts extends StatelessWidget {
  const _BestProducts({required this.overview});
  final _DashboardOverview overview;
  @override
  Widget build(BuildContext context) {
    final topToday = overview.topProducts(_TopPeriod.today, context: context);
    final topWeek = overview.topProducts(_TopPeriod.week, context: context);
    final topMonth = overview.topProducts(_TopPeriod.month, context: context);

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFBBF24), Color(0xFFF59E0B)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(
                  Icons.emoji_events_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'home.best_title'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title(context),
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _BestProductTile(
            'home.tab_today'.tr(),
            topToday.isNotEmpty ? topToday.first : null,
            '🥇',
            const Color(0xFFFEF3C7),
          ),
          const SizedBox(height: 14),
          _BestProductTile(
            'home.tab_week'.tr(),
            topWeek.isNotEmpty ? topWeek.first : null,
            '🥈',
            const Color(0xFFF1F5F9),
          ),
          const SizedBox(height: 14),
          _BestProductTile(
            'home.tab_month'.tr(),
            topMonth.isNotEmpty ? topMonth.first : null,
            '🥉',
            const Color(0xFFFFEBDD),
          ),
        ],
      ),
    );
  }
}

class _BestProductTile extends StatelessWidget {
  const _BestProductTile(this.period, this.product, this.medal, this.tileBg);
  final String period;
  final _ProductSales? product;
  final String medal;
  final Color tileBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tileBg.withOpacity(.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tileBg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            period,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.05),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(medal, style: const TextStyle(fontSize: 17)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: product == null
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'home.table_no_data'.tr(),
                          style: TextStyle(
                            color: Colors.black.withOpacity(.65),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            product!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'home.best_qty_sold'.tr(
                              args: [_number(product!.quantity)],
                            ),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.black.withOpacity(.65),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'home.best_revenue'.tr(
                              args: [_money(product!.revenue)],
                            ),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.black.withOpacity(.65),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WarehouseRow extends StatelessWidget {
  const _WarehouseRow({required this.overview});
  final _DashboardOverview overview;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(child: _WarehouseStatus(overview: overview)),
      const SizedBox(width: 12),
      Expanded(child: _LowStockProducts(overview: overview)),
    ],
  );
}

class _WarehouseStatus extends StatelessWidget {
  const _WarehouseStatus({required this.overview});
  final _DashboardOverview overview;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF64748B).withOpacity(.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.inventory_2_rounded,
                color: const Color(0xFF64748B),
                size: 18,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'home.warehouse_title'.tr(),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppTheme.title(context),
                letterSpacing: -0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        _WarehouseLine(
          'home.warehouse_total'.tr(),
          '${overview.products.length}',
          const Color(0xFF2563EB),
        ),
        _WarehouseLine(
          'home.warehouse_low'.tr(),
          '${overview.lowStock.length}',
          const Color(0xFFEF4444),
        ),
        _WarehouseLine(
          'home.warehouse_out'.tr(),
          '${overview.outOfStock.length}',
          const Color(0xFFEF4444),
        ),
        _WarehouseLine(
          'home.warehouse_categories'.tr(),
          '${overview.categoryCount}',
          const Color(0xFF3B82F6),
          last: true,
        ),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: overview.products.isEmpty
                ? 0
                : (overview.products.length -
                          overview.lowStock.length -
                          overview.outOfStock.length) /
                      overview.products.length,
            minHeight: 4,
            backgroundColor: AppTheme.cardBorder(context),
            valueColor: const AlwaysStoppedAnimation(Color(0xFF2563EB)),
          ),
        ),
      ],
    ),
  );
}

class _WarehouseLine extends StatelessWidget {
  const _WarehouseLine(this.label, this.value, this.color, {this.last = false});
  final String label, value;
  final Color color;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: last
          ? null
          : Border(bottom: BorderSide(color: AppTheme.cardBorder(context))),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              color: AppTheme.muted(context),
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _LowStockProducts extends StatelessWidget {
  const _LowStockProducts({required this.overview});
  final _DashboardOverview overview;
  @override
  Widget build(BuildContext context) => _Panel(
    padding: EdgeInsets.zero,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFEF4444).withOpacity(.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Color(0xFFEF4444),
                  size: 17,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'home.low_stock_title'.tr(),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.title(context),
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (overview.lowStock.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: _EmptyTable(labelKey: 'home.low_stock_empty'),
          )
        else
          ...overview.lowStock
              .take(4)
              .map(
                (product) => Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 11,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.title(context),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_number(product.number('quantity'))} ta',
                          style: const TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFB91C1C),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ],
    ),
  );
}

class _UnsoldProducts extends StatelessWidget {
  const _UnsoldProducts({required this.overview});
  final _DashboardOverview overview;
  @override
  Widget build(BuildContext context) => _SimpleTablePanel(
    icon: Icons.cancel,
    iconGradient: const [Color(0xFFF87171), Color(0xFFEF4444)],
    title: 'home.unsold_title'.tr(),
    headers: [
      'home.unsold_col_product'.tr(),
      'home.unsold_col_days'.tr(),
      'home.unsold_col_qty'.tr(),
    ],
    rows: overview.unsold
        .take(5)
        .map(
          (item) => [
            item.product.name,
            '${item.days} kun',
            '${_number(item.product.number('quantity'))} ta',
          ],
        )
        .toList(),
    warningColumn: 1,
    warningColor: const Color(0xFFEF4444),
  );
}

class _LowestSellingProducts extends StatelessWidget {
  const _LowestSellingProducts({required this.overview});
  final _DashboardOverview overview;
  @override
  Widget build(BuildContext context) => _SimpleTablePanel(
    icon: Icons.trending_down_rounded,
    iconGradient: const [Color(0xFF34D399), Color(0xFF10B981)],
    title: 'home.lowest_title'.tr(),
    headers: [
      'home.lowest_col_product'.tr(),
      'home.lowest_col_sales'.tr(),
      'home.lowest_col_revenue'.tr(),
    ],
    rows: overview.lowestMonthlySales
        .take(5)
        .map(
          (item) => [
            item.name,
            '${_number(item.quantity)} ta',
            _money(item.revenue),
          ],
        )
        .toList(),
  );
}

class _SimpleTablePanel extends StatelessWidget {
  const _SimpleTablePanel({
    required this.icon,
    required this.iconGradient,
    required this.title,
    required this.headers,
    required this.rows,
    this.warningColumn,
    this.warningColor,
  });

  final IconData icon;
  final List<Color> iconGradient;
  final String title;
  final List<String> headers;
  final List<List<String>> rows;
  final int? warningColumn;
  final Color? warningColor;

  int _flexFor(int cell, int total) {
    if (cell == 0) return 5;
    if (total >= 3 && cell == total - 1) return 3;
    return 2;
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: iconGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppTheme.title(context),
                    letterSpacing: -0.1,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SizedBox(
            height: 260,
            child: rows.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: _EmptyTable(labelKey: 'home.table_no_data'),
                  )
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            for (
                              var cell = 0;
                              cell < headers.length;
                              cell++
                            ) ...[
                              Expanded(
                                flex: _flexFor(cell, headers.length),
                                child: Align(
                                  alignment: cell == 0
                                      ? Alignment.centerLeft
                                      : Alignment.centerRight,
                                  child: Text(
                                    headers[cell],
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: AppTheme.muted(context),
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ),
                              ),
                              if (cell != headers.length - 1)
                                const SizedBox(width: 12),
                            ],
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          itemCount: rows.length,
                          itemBuilder: (context, index) {
                            final cells = rows[index];
                            return Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: index == rows.length - 1
                                        ? Colors.transparent
                                        : AppTheme.cardBorder(context),
                                    width: 0.5,
                                  ),
                                ),
                              ),
                              child: Row(
                                children: [
                                  for (
                                    var cell = 0;
                                    cell < cells.length;
                                    cell++
                                  ) ...[
                                    Expanded(
                                      flex: _flexFor(cell, cells.length),
                                      child: Align(
                                        alignment: cell == 0
                                            ? Alignment.centerLeft
                                            : Alignment.centerRight,
                                        child: Text(
                                          cells[cell],
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            color: cell == 0
                                                ? AppTheme.title(context)
                                                : warningColumn == cell
                                                ? (warningColor ??
                                                      const Color(0xFFEF4444))
                                                : AppTheme.muted(context),
                                            fontWeight: cell == 0
                                                ? FontWeight.w500
                                                : FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (cell != cells.length - 1)
                                      const SizedBox(width: 12),
                                  ],
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _QuickStatistics extends StatelessWidget {
  const _QuickStatistics({required this.overview});
  final _DashboardOverview overview;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF34D399), Color(0xFF10B981)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.bar_chart_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'home.quick_title'.tr(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.title(context),
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _QuickLine('home.quick_today_orders'.tr(), '${overview.todayOrders}'),
        _QuickLine(
          'home.quick_today_customers'.tr(),
          '${overview.todayCustomers}',
        ),
        _QuickLine('home.quick_avg_order'.tr(), _money(overview.averageOrder)),
        _QuickLine('home.quick_best_hour'.tr(), overview.bestSellingHour),
        _QuickLine(
          'home.quick_top_category'.tr(),
          overview.topCategory,
          last: true,
        ),
      ],
    ),
  );
}

class _QuickLine extends StatelessWidget {
  const _QuickLine(this.label, this.value, {this.last = false});
  final String label, value;
  final bool last;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 11),
    decoration: BoxDecoration(
      border: last
          ? null
          : Border(
              bottom: BorderSide(
                color: AppTheme.cardBorder(context),
                width: 0.5,
              ),
            ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              color: AppTheme.muted(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppTheme.pageBackground(context),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.title(context),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

class _RecentActivities extends StatelessWidget {
  const _RecentActivities({required this.overview});
  final _DashboardOverview overview;
  @override
  Widget build(BuildContext context) => _Panel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF94A3B8), Color(0xFF64748B)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.history_rounded,
                color: Colors.white,
                size: 17,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'home.activities_title'.tr(),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppTheme.title(context),
                letterSpacing: -0.1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (overview.activities.isEmpty)
          const SizedBox(
            height: 220,
            child: _EmptyTable(labelKey: 'home.activities_empty'),
          )
        else
          ...overview.activities
              .take(5)
              .map((activity) => _ActivityRow(activity: activity)),
      ],
    ),
  );
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.activity});
  final _Activity activity;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: activity.color.withOpacity(.12),
            shape: BoxShape.circle,
          ),
          child: Icon(activity.icon, size: 14, color: activity.color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                activity.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.title(context),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                activity.detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: AppTheme.muted(context),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _relativeTime(activity.time, context),
          style: TextStyle(
            color: AppTheme.muted(context),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: AppTheme.panel(context),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.cardBorder(context), width: 1),
      boxShadow: [
        BoxShadow(
          color: AppTheme.shadow(context),
          blurRadius: 20,
          spreadRadius: 0,
          offset: const Offset(0, 4),
        ),
      ],
    ),
    child: child,
  );
}

class _EmptyTable extends StatelessWidget {
  const _EmptyTable({required this.labelKey});
  final String labelKey;
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      labelKey.tr(),
      style: TextStyle(
        color: AppTheme.muted(context),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error});
  final Object error;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Text(
        'home.loading_error'.tr(args: ['$error']),
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFFB91C1C)),
      ),
    ),
  );
}

enum _TopPeriod { today, week, month }

class _DashboardOverview {
  _DashboardOverview({
    required this.products,
    required this.sales,
    required this.customers,
    required this.categories,
    required this.inventoryQuantity,
    required this.inventoryValue,
    required this.lowStock,
    required this.outOfStock,
    required this.todayOrders,
    required this.todayRevenue,
    required this.todayProfit,
    required this.todayCustomers,
    required this.todayProductsAdded,
    required this.debtSales,
    required this.debtPayments,
    required this.remainingDebt,
    required this.customersWithDebt,
    required this.todayDebtPayments,
    required this.todayDebtPaymentsCount,
    required this.productSales,
    required this.activities,
  });
  final List<_Document> products,
      sales,
      customers,
      categories,
      lowStock,
      outOfStock;
  final int inventoryQuantity,
      todayOrders,
      todayCustomers,
      customersWithDebt,
      todayProductsAdded,
      todayDebtPaymentsCount;
  final num inventoryValue,
      todayRevenue,
      todayProfit,
      debtSales,
      debtPayments,
      remainingDebt,
      todayDebtPayments;
  final Map<String, _ProductSales> productSales;
  final List<_Activity> activities;

  int get categoryCount => categories.isNotEmpty
      ? categories.length
      : products
            .map((p) => p.text('category'))
            .where((name) => name.isNotEmpty)
            .toSet()
            .length;

  num get averageOrder => todayOrders == 0 ? 0 : todayRevenue / todayOrders;

  num get totalSales => todayRevenue;

  String get bestSellingHour {
    final hours = <int, int>{};
    for (final sale in sales.where(
      (sale) => _isToday(sale.date('timestamp')),
    )) {
      hours.update(
        sale.date('timestamp').hour,
        (v) => v + 1,
        ifAbsent: () => 1,
      );
    }
    if (hours.isEmpty) return '—';
    final hour = hours.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
    return '${hour.toString().padLeft(2, '0')}:00 - ${((hour + 1) % 24).toString().padLeft(2, '0')}:00';
  }

  String get topCategory {
    final cats = <String, int>{};
    final prodToCat = <String, String>{};
    for (final p in products) {
      final c = p.text('category', p.text('type'));
      if (c.isNotEmpty) prodToCat[p.id] = c;
    }
    for (final sale in sales) {
      if (!_isToday(sale.date('timestamp'))) continue;
      for (final item in sale.list('items')) {
        final pid = item['productId']?.toString() ?? '';
        final cat =
            (item['category']?.toString().trim().isNotEmpty ?? false)
                ? item['category'].toString()
                : (prodToCat[pid] ?? 'Boshqa');
        cats.update(
          cat,
          (v) => v + _asInt(item['quantity']),
          ifAbsent: () => _asInt(item['quantity']),
        );
      }
    }
    if (cats.isEmpty) return '—';
    return cats.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  List<_UnsoldProduct> get unsold {
    final soldIds = productSales.keys.toSet();
    final today = _day(DateTime.now());
    final items = products
        .where((product) => !soldIds.contains(product.id))
        .map((product) {
          final since = product.date(
            'createdAt',
            fallback: product.date('lastUpdate', fallback: today),
          );
          return _UnsoldProduct(
            product,
            math.max(0, today.difference(_day(since)).inDays),
          );
        })
        .toList();
    items.sort((a, b) => b.days.compareTo(a.days));
    return items;
  }

  List<_ProductSales> get lowestMonthlySales {
    final start = DateTime(DateTime.now().year, DateTime.now().month, 1);
    final values =
        _aggregateSales(
          start,
          context: null,
        ).values.where((item) => item.quantity > 0).toList()..sort(
          (a, b) => a.quantity != b.quantity
              ? a.quantity.compareTo(b.quantity)
              : a.revenue.compareTo(b.revenue),
        );
    return values;
  }

  List<_ProductSales> topProducts(_TopPeriod period, {BuildContext? context}) {
    final now = DateTime.now();
    final start = switch (period) {
      _TopPeriod.today => _day(now),
      _TopPeriod.week => _day(now).subtract(Duration(days: now.weekday - 1)),
      _TopPeriod.month => DateTime(now.year, now.month, 1),
    };
    final items = _aggregateSales(start, context: context).values.toList()
      ..sort(
        (a, b) => b.quantity != a.quantity
            ? b.quantity.compareTo(a.quantity)
            : b.revenue.compareTo(a.revenue),
      );
    return items.take(10).toList();
  }

  Map<String, _ProductSales> _aggregateSales(
    DateTime start, {
    BuildContext? context,
  }) {
    final values = <String, _ProductSales>{};
    for (final sale in sales) {
      if (sale.date('timestamp').isBefore(start)) continue;
      for (final item in sale.list('items')) {
        final id =
            item['productId']?.toString() ??
            item['productName']?.toString() ??
            '';
        if (id.isEmpty) continue;
        final unnamed = context != null
            ? 'home.fallback_unnamed'.tr()
            : 'Nomsiz';
        final entry = values.putIfAbsent(
          id,
          () => _ProductSales(id, item['productName']?.toString() ?? unnamed),
        );
        entry.quantity += _asInt(item['quantity']);
        entry.revenue += _asNum(
          item['total'] ?? (_asNum(item['price']) * _asNum(item['quantity'])),
        );
        final sellingPrice = _asNum(item['price'] ?? item['sellingPrice']);
        final originalPrice = _asNum(
          item['originalPrice'] ?? item['costPrice'],
        );
        entry.profit +=
            (sellingPrice - originalPrice) * _asNum(item['quantity']);
      }
    }
    return values;
  }

  factory _DashboardOverview.fromData(
    BuildContext context, {
    required List<_Document> products,
    required List<_Document> sales,
    required List<_Document> customers,
    required List<_Document> categories,
    required List<_Document> entries,
    required Map<String, List<_Document>> customerDebts,
    required Map<String, List<_Document>> customerPayments,
  }) {
    final inventoryQuantity = products.fold<int>(
      0,
      (sum, product) => sum + math.max(0, product.number('quantity').toInt()),
    );
    final inventoryValue = products.fold<num>(
      0,
      (sum, product) =>
          sum +
          math.max(0, product.number('quantity')) *
              product.number(
                'originalPrice',
                fallback: product.number('costPrice'),
              ),
    );

    final lowStock =
        products
            .where(
              (product) =>
                  product.number('quantity') > 0 &&
                  product.number('quantity') <= 10,
            )
            .toList()
          ..sort(
            (a, b) => a.number('quantity').compareTo(b.number('quantity')),
          );
    final outOfStock = products
        .where((product) => product.number('quantity') <= 0)
        .toList();

    final todaySales = sales
        .where((sale) => _isToday(sale.date('timestamp')))
        .toList();

    num debtSales = 0;

    for (final sale in sales) {
      final amount = sale.number(
        'totalAmount',
        fallback: sale
            .list('items')
            .fold<num>(
              0,
              (sum, item) =>
                  sum +
                  _asNum(
                    item['total'] ??
                        (_asNum(item['price']) * _asNum(item['quantity'])),
                  ),
            ),
      );
      if (sale.boolean('isDebtSale')) {
        debtSales += amount;
      }
    }

    num debtPayments = 0;
    num todayDebtPayments = 0;
    int todayDebtPaymentsCount = 0;

    for (final payments in customerPayments.values) {
      for (final p in payments) {
        final amt = p.number('amount');
        debtPayments += amt;
        if (_isToday(p.date('paymentDate', fallback: p.date('timestamp')))) {
          todayDebtPayments += amt;
          todayDebtPaymentsCount++;
        }
      }
    }

    // Customer documents are the authoritative debt balance for the whole
    // application (selling, customer payments and manually added debts).
    num customerBalance(_Document customer) {
      if (customer.data.containsKey('remainingDebt')) {
        return customer.number('remainingDebt');
      }
      final debts =
          customerDebts[customer.id]?.fold<num>(
            0,
            (sum, debt) => sum + debt.number('amount'),
          ) ??
          0;
      final payments =
          customerPayments[customer.id]?.fold<num>(
            0,
            (sum, payment) => sum + payment.number('amount'),
          ) ??
          0;
      return debts - payments;
    }

    final remainingDebt = customers.fold<num>(
      0,
      (sum, customer) => sum + customerBalance(customer),
    );

    num todayRevenue = 0;
    num todayProfit = 0;
    for (final sale in todaySales) {
      final amount = sale.number(
        'totalAmount',
        fallback: sale
            .list('items')
            .fold<num>(
              0,
              (sum, item) =>
                  sum +
                  _asNum(
                    item['total'] ??
                        (_asNum(item['price']) * _asNum(item['quantity'])),
                  ),
            ),
      );

      todayRevenue += amount;

      final cost = sale
          .list('items')
          .fold<num>(
            0,
            (sum, item) =>
                sum +
                _asNum(item['originalPrice'] ?? item['costPrice']) *
                    _asNum(item['quantity']),
          );
      todayProfit += amount - cost;
    }
    final customersWithDebt = customers
        .where((customer) => customerBalance(customer) > 0)
        .length;

    final todayCustomers = customers
        .where(
          (c) =>
              _isToday(c.date('createdAt', fallback: c.date('lastActivity'))),
        )
        .length;

    final Set<String> todayAddedProductIds = {};
    for (final entry in entries) {
      if (entry.text('type') == 'incoming' &&
          _isToday(entry.date('timestamp'))) {
        final productId = entry.text('productId');
        if (productId.isNotEmpty) {
          todayAddedProductIds.add(productId);
        }
      }
    }
    final int todayProductsAdded = todayAddedProductIds.length;
    final activities = _buildActivities(
      context,
      products,
      sales,
      customers,
      entries,
      customerPayments,
    );

    final productSales = <String, _ProductSales>{};
    for (final sale in sales) {
      for (final item in sale.list('items')) {
        final id =
            item['productId']?.toString() ??
            item['productName']?.toString() ??
            '';
        if (id.isEmpty) continue;
        final entry = productSales.putIfAbsent(
          id,
          () => _ProductSales(
            id,
            item['productName']?.toString() ?? 'home.fallback_unnamed'.tr(),
          ),
        );
        entry.quantity += _asInt(item['quantity']);
        entry.revenue += _asNum(
          item['total'] ?? _asNum(item['price']) * _asNum(item['quantity']),
        ); // absolute for metrics
        final sellingPrice = _asNum(item['price'] ?? item['sellingPrice']);
        final originalPrice = _asNum(
          item['originalPrice'] ?? item['costPrice'],
        );
        entry.profit +=
            (sellingPrice - originalPrice) * _asNum(item['quantity']);
      }
    }

    return _DashboardOverview(
      products: products,
      sales: sales,
      customers: customers,
      categories: categories,
      inventoryQuantity: inventoryQuantity,
      inventoryValue: inventoryValue,
      lowStock: lowStock,
      outOfStock: outOfStock,
      todayOrders: todaySales.length,
      todayRevenue: todayRevenue,
      todayProfit: todayProfit,
      todayCustomers: todayCustomers,
      todayProductsAdded: todayProductsAdded,
      debtSales: debtSales,
      debtPayments: debtPayments,
      remainingDebt: remainingDebt,
      customersWithDebt: customersWithDebt,
      todayDebtPayments: todayDebtPayments,
      todayDebtPaymentsCount: todayDebtPaymentsCount,
      productSales: productSales,
      activities: activities,
    );
  }
}

List<_Activity> _buildActivities(
  BuildContext context,
  List<_Document> products,
  List<_Document> sales,
  List<_Document> customers,
  List<_Document> entries,
  Map<String, List<_Document>> payments,
) {
  final values = <_Activity>[];
  for (final sale in sales) {
    final debt = sale.boolean('isDebtSale');
    final itemsLen = sale.list('items').length;
    values.add(
      _Activity(
        'sale-${sale.id}',
        debt
            ? 'home.activity_new_debt'.tr()
            : 'home.activity_product_sold'.tr(),
        sale.text(
          'customerName',
          debt
              ? 'home.activity_debt_sale'.tr()
              : 'home.activity_items_count'.tr(args: ['$itemsLen']),
        ),
        sale.date('timestamp'),
        Icons.shopping_bag_rounded,
        const Color(0xFF16A34A),
      ),
    );
  }
  for (final product in products) {
    final created = product.date(
      'createdAt',
      fallback: product.date('lastUpdate'),
    );
    values.add(
      _Activity(
        'product-${product.id}',
        'home.activity_new_product'.tr(),
        product.nameWithContext(context),
        created,
        Icons.inventory_2_rounded,
        const Color(0xFF2563EB),
      ),
    );
  }
  for (final customer in customers) {
    values.add(
      _Activity(
        'customer-${customer.id}',
        'home.activity_new_customer'.tr(),
        customer.nameWithContext(context),
        customer.date('createdAt', fallback: customer.date('lastActivity')),
        Icons.person_add_rounded,
        const Color(0xFF16A34A),
      ),
    );
  }
  for (final payment in payments.values.expand((items) => items)) {
    values.add(
      _Activity(
        'payment-${payment.id}',
        'home.activity_debt_paid'.tr(),
        _money(payment.number('amount'), context: context),
        payment.date('paymentDate', fallback: payment.date('timestamp')),
        Icons.payments_rounded,
        const Color(0xFFF59E0B),
      ),
    );
  }
  values.sort((a, b) => b.time.compareTo(a.time));
  final seen = <String>{};
  return values.where((activity) => seen.add(activity.id)).toList();
}

class _Document {
  const _Document(this.id, this.data);
  final String id;
  final Map<String, dynamic> data;
  factory _Document.fromSnapshot(
    QueryDocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => _Document(snapshot.id, snapshot.data());

  String text(String key, [String fallback = '']) {
    final value = data[key];
    return value == null
        ? fallback
        : value.toString().trim().isEmpty
        ? fallback
        : value.toString().trim();
  }

  String get name =>
      text('productName', text('name', text('fullName', 'Nomsiz')));

  String nameWithContext(BuildContext context) => text(
    'productName',
    text('name', text('fullName', 'home.fallback_unnamed'.tr())),
  );

  num number(String key, {num fallback = 0}) =>
      data.containsKey(key) ? _asNum(data[key]) : fallback;

  bool boolean(String key) {
    final value = data[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    return [
      'true',
      '1',
      'yes',
      'debt',
      'credit',
      'qarz',
    ].contains(value?.toString().toLowerCase().trim());
  }

  DateTime date(String key, {DateTime? fallback}) {
    final value = data[key];
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is String) {
      return DateTime.tryParse(value) ??
          fallback ??
          DateTime.fromMillisecondsSinceEpoch(0);
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<Map<String, dynamic>> list(String key) {
    final value = data[key];
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }
}

class _ProductSales {
  _ProductSales(this.id, this.name);
  final String id, name;
  int quantity = 0;
  num revenue = 0;
  num profit = 0;
}

class _UnsoldProduct {
  const _UnsoldProduct(this.product, this.days);
  final _Document product;
  final int days;
}

class _Activity {
  const _Activity(
    this.id,
    this.title,
    this.detail,
    this.time,
    this.icon,
    this.color,
  );
  final String id, title, detail;
  final DateTime time;
  final IconData icon;
  final Color color;
}

num _asNum(dynamic value) {
  if (value is num) return value.isFinite ? value : 0;
  return num.tryParse(value?.toString() ?? '') ?? 0;
}

int _asInt(dynamic value) => _asNum(value).toInt();
DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
bool _isToday(DateTime value) {
  final now = DateTime.now();
  return value.year == now.year &&
      value.month == now.month &&
      value.day == now.day;
}

String _number(num value) {
  final raw = value.toStringAsFixed(0);
  final chars = <String>[];
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) chars.add(',');
    chars.add(raw[i]);
  }
  return chars.join();
}

String _money(num value, {BuildContext? context}) {
  final currency = context != null ? 'common.currency'.tr() : "so'm";
  if (value == 0) return "0 $currency";
  final raw = value.abs().toStringAsFixed(0);
  final chars = <String>[];
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && (raw.length - i) % 3 == 0) chars.add(',');
    chars.add(raw[i]);
  }
  return "${value < 0 ? '-' : ''}${chars.join()} $currency";
}

String _relativeTime(DateTime time, BuildContext context) {
  final diff = DateTime.now().difference(time);
  if (diff.isNegative) return 'home.time_just_now'.tr();
  if (diff.inMinutes < 1) return 'home.time_just_now'.tr();
  if (diff.inMinutes < 60) {
    return 'home.time_minutes_ago'.tr(args: ['${diff.inMinutes}']);
  }
  if (diff.inHours < 24) {
    return 'home.time_hours_ago'.tr(args: ['${diff.inHours}']);
  }
  if (diff.inDays < 7) {
    return 'home.time_days_ago'.tr(args: ['${diff.inDays}']);
  }
  return '${time.day.toString().padLeft(2, '0')}.${time.month.toString().padLeft(2, '0')}.${time.year}';
}

class AppTheme {
  static bool isDark([BuildContext? context]) =>
      ThemeController.instance.isDarkMode;
  static Color pageBackground([BuildContext? context]) =>
      isDark() ? const Color(0xFF0F172A) : const Color(0xFFF3F6FE);
  static Color cardBorder([BuildContext? context]) =>
      isDark() ? const Color(0xFF334155) : const Color(0xFFE6EBF3);
  static Color title([BuildContext? context]) =>
      isDark() ? const Color(0xFFF1F5F9) : const Color(0xFF172033);
  static Color muted([BuildContext? context]) =>
      isDark() ? const Color(0xFF94A3B8) : const Color(0xFF718096);
  static Color panel([BuildContext? context]) =>
      isDark() ? const Color(0xFF1E293B) : Colors.white;
  static Color shadow([BuildContext? context]) => isDark()
      ? Colors.black.withOpacity(0.4)
      : const Color(0xFF334155).withOpacity(.03);

  static Color goldBg([BuildContext? context]) =>
      isDark() ? const Color(0xFF42381A) : const Color(0xFFFFF7D6);
  static Color silverBg([BuildContext? context]) =>
      isDark() ? const Color(0xFF2A2E35) : const Color(0xFFF1F3F6);
  static Color bronzeBg([BuildContext? context]) =>
      isDark() ? const Color(0xFF3D2A1C) : const Color(0xFFFFEBDD);

  static Color medalBg(BuildContext context, int rank) {
    if (rank == 1) return goldBg(context);
    if (rank == 2) return silverBg(context);
    if (rank == 3) return bronzeBg(context);
    return Colors.transparent;
  }
}
