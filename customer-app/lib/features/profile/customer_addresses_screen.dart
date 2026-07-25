import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/ebtl_colors.dart';
import '../../models/address_models.dart';
import '../../services/api_service.dart';
import '../../shared/widgets/app_state_widgets.dart';
import '../../shared/widgets/checkout_input_field.dart';
import '../../shared/widgets/detail_card.dart';
import 'widgets/profile_widgets.dart';

class CustomerAddressesScreen extends StatefulWidget {
  const CustomerAddressesScreen({super.key});

  @override
  State<CustomerAddressesScreen> createState() =>
      _CustomerAddressesScreenState();
}

class _CustomerAddressesScreenState extends State<CustomerAddressesScreen> {
  late Future<CustomerAddressesResponse> addressesFuture;
  List<CustomerAddress>? addresses;
  final Set<String> mutatingIds = <String>{};

  @override
  void initState() {
    super.initState();
    addressesFuture = loadAddresses();
  }

  Future<CustomerAddressesResponse> loadAddresses() async {
    final response = await ApiService.fetchCustomerAddresses();
    addresses = response.addresses;
    return response;
  }

  void reload() {
    setState(() {
      addressesFuture = loadAddresses();
    });
  }

  Future<void> refreshList() async {
    try {
      final response = await ApiService.fetchCustomerAddresses();
      if (!mounted) return;
      setState(() => addresses = response.addresses);
    } catch (_) {
      // Keep the current list; a subsequent pull/retry can refresh it.
    }
  }

  Future<void> openForm({CustomerAddress? existing}) async {
    final saved = await showAddressFormSheet(context: context, existing: existing);
    if (saved == true) {
      await refreshList();
      if (!mounted) return;
      showAppSnackBar(
        context,
        existing == null ? 'Address added.' : 'Address updated.',
      );
    }
  }

  Future<void> setAsDefault(CustomerAddress address) async {
    if (address.isDefault || mutatingIds.contains(address.id)) return;

    setState(() => mutatingIds.add(address.id));

    try {
      await ApiService.saveCustomerAddress(
        id: address.id,
        label: address.label,
        compoundName: address.compoundName,
        beachName: address.beachName,
        unitNumber: address.unitNumber,
        building: address.building,
        floor: address.floor,
        deliveryNotes: address.deliveryNotes,
        isDefault: true,
      );

      await refreshList();
      if (!mounted) return;
      setState(() => mutatingIds.remove(address.id));
      showAppSnackBar(context, 'Default address updated.');
    } catch (error) {
      if (!mounted) return;
      setState(() => mutatingIds.remove(address.id));
      showAppSnackBar(
        context,
        apiErrorMessage(error, fallback: 'Could not update the default address.'),
      );
    }
  }

  Future<void> deleteAddress(CustomerAddress address) async {
    if (mutatingIds.contains(address.id)) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: EbtlColors.white,
        title: Text(
          'Delete address?',
          style: GoogleFonts.playfairDisplay(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'This will remove "${address.title}" from your saved addresses.',
          style: GoogleFonts.manrope(fontWeight: FontWeight.w600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Delete',
              style: GoogleFonts.manrope(
                color: EbtlColors.coral,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => mutatingIds.add(address.id));

    try {
      await ApiService.deleteCustomerAddress(id: address.id);
      await refreshList();
      if (!mounted) return;
      setState(() => mutatingIds.remove(address.id));
      showAppSnackBar(context, 'Address deleted.');
    } catch (error) {
      if (!mounted) return;
      setState(() => mutatingIds.remove(address.id));
      showAppSnackBar(
        context,
        apiErrorMessage(error, fallback: 'Could not delete this address.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: EbtlColors.cream,
      body: SafeArea(
        child: Column(
          children: [
            ProfileSubScreenHeader(
              title: 'Delivery addresses',
              onBack: () => Navigator.of(context).pop(),
            ),
            Expanded(child: buildContent()),
            _AddAddressBar(onTap: () => openForm()),
          ],
        ),
      ),
    );
  }

  Widget buildContent() {
    return FutureBuilder<CustomerAddressesResponse>(
      future: addressesFuture,
      builder: (context, snapshot) {
        final items = addresses ?? snapshot.data?.addresses ?? <CustomerAddress>[];

        if (snapshot.connectionState == ConnectionState.waiting &&
            items.isEmpty) {
          return const EbtlLoadingSection(label: 'Loading addresses...');
        }

        if (snapshot.hasError && items.isEmpty) {
          return InlineErrorCard(
            message: apiErrorMessage(snapshot.error!),
            onRetry: reload,
          );
        }

        if (items.isEmpty) {
          return const _AddressesEmptyCard();
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 22),
          itemCount: items.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final address = items[index];
            return _AddressCard(
              address: address,
              isMutating: mutatingIds.contains(address.id),
              onEdit: () => openForm(existing: address),
              onDelete: () => deleteAddress(address),
              onSetDefault: () => setAsDefault(address),
            );
          },
        );
      },
    );
  }
}

class _AddAddressBar extends StatelessWidget {
  final VoidCallback onTap;

  const _AddAddressBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 12, 22, 12),
      decoration: const BoxDecoration(
        color: EbtlColors.white,
        border: Border(top: BorderSide(color: EbtlColors.border)),
      ),
      child: SizedBox(
        height: 54,
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: EbtlColors.coral,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.add_location_alt_outlined, size: 20),
          label: Text(
            'Add address',
            style: GoogleFonts.manrope(fontSize: 15, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  final CustomerAddress address;
  final bool isMutating;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onSetDefault;

  const _AddressCard({
    required this.address,
    required this.isMutating,
    required this.onEdit,
    required this.onDelete,
    required this.onSetDefault,
  });

  @override
  Widget build(BuildContext context) {
    final summary = address.summary;
    final notes = address.deliveryNotes?.trim() ?? '';

    return DetailCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  address.title,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: EbtlColors.navy,
                  ),
                ),
              ),
              if (address.isDefault) const _DefaultBadge(),
            ],
          ),
          if (summary.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              summary,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w600,
                color: EbtlColors.ink,
              ),
            ),
          ],
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              notes,
              style: GoogleFonts.manrope(
                fontSize: 13,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: EbtlColors.muted,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (!address.isDefault)
                _AddressAction(
                  icon: Icons.star_outline,
                  label: 'Set default',
                  onTap: isMutating ? null : onSetDefault,
                ),
              _AddressAction(
                icon: Icons.edit_outlined,
                label: 'Edit',
                onTap: isMutating ? null : onEdit,
              ),
              _AddressAction(
                icon: Icons.delete_outline,
                label: 'Delete',
                danger: true,
                onTap: isMutating ? null : onDelete,
              ),
              if (isMutating) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: EbtlColors.coral,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _DefaultBadge extends StatelessWidget {
  const _DefaultBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: EbtlColors.seafoam,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Default',
        style: GoogleFonts.manrope(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: EbtlColors.navy,
        ),
      ),
    );
  }
}

class _AddressAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool danger;
  final VoidCallback? onTap;

  const _AddressAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = danger ? EbtlColors.coral : EbtlColors.navy;

    return TextButton.icon(
      onPressed: onTap,
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(icon, size: 18, color: color),
      label: Text(
        label,
        style: GoogleFonts.manrope(fontSize: 13, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _AddressesEmptyCard extends StatelessWidget {
  const _AddressesEmptyCard();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: DetailCard(
        child: Column(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: EbtlColors.seafoam.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.location_on_outlined,
                color: EbtlColors.navy,
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No saved addresses yet.',
              textAlign: TextAlign.center,
              style: GoogleFonts.playfairDisplay(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: EbtlColors.navy,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a delivery address so checkout can bring your kit to your unit.',
              textAlign: TextAlign.center,
              style: GoogleFonts.manrope(
                fontSize: 14,
                height: 1.4,
                fontWeight: FontWeight.w600,
                color: EbtlColors.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the add/edit form. Returns `true` when an address was saved.
Future<bool?> showAddressFormSheet({
  required BuildContext context,
  CustomerAddress? existing,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddressFormSheet(existing: existing),
  );
}

class _AddressFormSheet extends StatefulWidget {
  final CustomerAddress? existing;

  const _AddressFormSheet({required this.existing});

  @override
  State<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends State<_AddressFormSheet> {
  late final TextEditingController labelController;
  late final TextEditingController compoundController;
  late final TextEditingController beachController;
  late final TextEditingController buildingController;
  late final TextEditingController floorController;
  late final TextEditingController unitController;
  late final TextEditingController notesController;

  late bool isDefault;
  bool isSaving = false;

  bool get isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    labelController = TextEditingController(text: existing?.label ?? '');
    compoundController =
        TextEditingController(text: existing?.compoundName ?? '');
    beachController = TextEditingController(text: existing?.beachName ?? '');
    buildingController = TextEditingController(text: existing?.building ?? '');
    floorController = TextEditingController(text: existing?.floor ?? '');
    unitController = TextEditingController(text: existing?.unitNumber ?? '');
    notesController = TextEditingController(text: existing?.deliveryNotes ?? '');
    isDefault = existing?.isDefault ?? false;
  }

  @override
  void dispose() {
    labelController.dispose();
    compoundController.dispose();
    beachController.dispose();
    buildingController.dispose();
    floorController.dispose();
    unitController.dispose();
    notesController.dispose();
    super.dispose();
  }

  bool get hasAnyLocationDetail {
    return [
      compoundController.text,
      beachController.text,
      buildingController.text,
      floorController.text,
      unitController.text,
    ].any((value) => value.trim().isNotEmpty);
  }

  Future<void> save() async {
    if (isSaving) return;

    if (!hasAnyLocationDetail) {
      showAppSnackBar(
        context,
        'Add at least a compound, beach, building, floor or unit.',
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      await ApiService.saveCustomerAddress(
        id: widget.existing?.id,
        label: labelController.text,
        compoundName: compoundController.text,
        beachName: beachController.text,
        building: buildingController.text,
        floor: floorController.text,
        unitNumber: unitController.text,
        deliveryNotes: notesController.text,
        isDefault: isDefault,
      );

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => isSaving = false);
      showAppSnackBar(
        context,
        apiErrorMessage(error, fallback: 'Could not save this address.'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: const BoxDecoration(
          color: EbtlColors.cream,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 18, 22, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      isEditing ? 'Edit address' : 'Add address',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: EbtlColors.navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    color: EbtlColors.navy,
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
                children: [
                  CheckoutInputField(
                    controller: labelController,
                    label: 'Label (optional)',
                    hintText: 'Home, Beach house…',
                    icon: Icons.bookmark_outline,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  CheckoutInputField(
                    controller: compoundController,
                    label: 'Compound',
                    hintText: 'Compound / resort name',
                    icon: Icons.holiday_village_outlined,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  CheckoutInputField(
                    controller: beachController,
                    label: 'Beach',
                    hintText: 'Beach name',
                    icon: Icons.beach_access_outlined,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  CheckoutInputField(
                    controller: buildingController,
                    label: 'Building',
                    hintText: 'Building / villa',
                    icon: Icons.apartment_outlined,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  CheckoutInputField(
                    controller: floorController,
                    label: 'Floor',
                    hintText: 'Floor',
                    icon: Icons.stairs_outlined,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  CheckoutInputField(
                    controller: unitController,
                    label: 'Unit',
                    hintText: 'Unit / apartment number',
                    icon: Icons.meeting_room_outlined,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 12),
                  CheckoutInputField(
                    controller: notesController,
                    label: 'Delivery notes (optional)',
                    hintText: 'Gate code, landmarks, instructions…',
                    icon: Icons.sticky_note_2_outlined,
                    maxLines: 3,
                    onChanged: (_) {},
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    activeThumbColor: EbtlColors.coral,
                    value: isDefault,
                    onChanged: (value) => setState(() => isDefault = value),
                    title: Text(
                      'Set as default address',
                      style: GoogleFonts.manrope(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: EbtlColors.navy,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 4, 22, 14),
                child: SizedBox(
                  height: 54,
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isSaving ? null : save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: EbtlColors.coral,
                      disabledBackgroundColor: EbtlColors.border,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: isSaving
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.4,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEditing ? 'Save changes' : 'Add address',
                            style: GoogleFonts.manrope(
                              fontSize: 15,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
