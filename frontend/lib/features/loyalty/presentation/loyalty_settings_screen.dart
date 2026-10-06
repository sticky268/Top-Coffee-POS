import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/branch/current_branch_provider.dart';
import '../../../core/widgets/app_buttons.dart' as pos_ui;
import '../data/loyalty_repository.dart';
import '../domain/loyalty_models.dart';

class LoyaltySettingsScreen extends ConsumerStatefulWidget {
  const LoyaltySettingsScreen({super.key});

  @override
  ConsumerState<LoyaltySettingsScreen> createState() =>
      _LoyaltySettingsScreenState();
}

class _LoyaltySettingsScreenState extends ConsumerState<LoyaltySettingsScreen> {
  final _formKey = GlobalKey<FormState>();

  final _pointsPerCurrencyController = TextEditingController();
  final _pointsPerRewardCurrencyController = TextEditingController();
  final _minimumRedeemPointsController = TextEditingController();
  final _expirationMonthsController = TextEditingController();

  LoyaltySettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEnabled = false;
  bool _redemptionEnabled = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  @override
  void dispose() {
    _pointsPerCurrencyController.dispose();
    _pointsPerRewardCurrencyController.dispose();
    _minimumRedeemPointsController.dispose();
    _expirationMonthsController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final branch = ref.read(currentBranchProvider);

    if (branch == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Select a specific branch before opening Loyalty Settings.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final settings = await ref
          .read(loyaltyRepositoryProvider)
          .getSettings(branchId: branch.id);

      if (!mounted) return;

      setState(() {
        _settings = settings;
        _isEnabled = settings.isEnabled;
        _redemptionEnabled = settings.redemptionEnabled;

        _pointsPerCurrencyController.text = settings.pointsPerCurrencyUnit
            .toString();
        _pointsPerRewardCurrencyController.text = settings
            .pointsPerRewardCurrencyUnit
            .toString();
        _minimumRedeemPointsController.text = settings.minimumRedeemPoints
            .toString();
        _expirationMonthsController.text =
            settings.expirationMonths?.toString() ?? '';
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final branch = ref.read(currentBranchProvider);

    if (branch == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Select a specific branch before saving.'),
        ),
      );
      return;
    }

    final pointsPerCurrency = double.tryParse(
      _pointsPerCurrencyController.text.trim(),
    );
    final pointsPerRewardCurrency = double.tryParse(
      _pointsPerRewardCurrencyController.text.trim(),
    );
    final minimumRedeemPoints = int.tryParse(
      _minimumRedeemPointsController.text.trim(),
    );

    final expirationText = _expirationMonthsController.text.trim();
    final expirationMonths = expirationText.isEmpty
        ? null
        : int.tryParse(expirationText);

    if (pointsPerCurrency == null ||
        pointsPerRewardCurrency == null ||
        minimumRedeemPoints == null ||
        (expirationText.isNotEmpty && expirationMonths == null)) {
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final settings = await ref
          .read(loyaltyRepositoryProvider)
          .updateSettings(
            isEnabled: _isEnabled,
            pointsPerCurrencyUnit: pointsPerCurrency,
            pointsPerRewardCurrencyUnit: pointsPerRewardCurrency,
            minimumRedeemPoints: minimumRedeemPoints,
            redemptionEnabled: _redemptionEnabled,
            expirationMonths: expirationMonths,
            branchId: branch.id,
          );

      if (!mounted) return;

      setState(() {
        _settings = settings;
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Loyalty settings saved successfully.')),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isSaving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to save loyalty settings: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentBranch = ref.watch(currentBranchProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Loyalty Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSettings,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (currentBranch != null) ...[
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.store_outlined),
                        title: Text(currentBranch.name),
                        subtitle: Text('Branch ${currentBranch.code}'),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_errorMessage != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(color: theme.colorScheme.error),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_settings != null)
                    Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Loyalty Program',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Card(
                            child: Column(
                              children: [
                                SwitchListTile(
                                  title: const Text('Enable Loyalty'),
                                  subtitle: const Text(
                                    'Allow customers to earn and use loyalty points.',
                                  ),
                                  value: _isEnabled,
                                  onChanged: _isSaving
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _isEnabled = value;
                                          });
                                        },
                                ),
                                const Divider(height: 1),
                                SwitchListTile(
                                  title: const Text('Enable Redemption'),
                                  subtitle: const Text(
                                    'Allow customers to redeem points for rewards.',
                                  ),
                                  value: _redemptionEnabled,
                                  onChanged: _isSaving
                                      ? null
                                      : (value) {
                                          setState(() {
                                            _redemptionEnabled = value;
                                          });
                                        },
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text('Points', style: theme.textTheme.titleMedium),
                          const SizedBox(height: 8),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                children: [
                                  TextFormField(
                                    controller: _pointsPerCurrencyController,
                                    enabled: !_isSaving,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Points per currency unit',
                                      helperText: 'Example: 1 point for every currency unit spent.',
                                    ),
                                    validator: (value) {
                                      final number = double.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      if (number == null || number < 0) {
                                        return 'Enter a valid number.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller:
                                        _pointsPerRewardCurrencyController,
                                    enabled: !_isSaving,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    decoration: const InputDecoration(
                                      labelText: 'Points required per reward currency unit',
                                      helperText: 'Example: 100 points = 1 reward currency unit.',
                                    ),
                                    validator: (value) {
                                      final number = double.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      if (number == null || number <= 0) {
                                        return 'Enter a number greater than 0.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _minimumRedeemPointsController,
                                    enabled: !_isSaving,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Minimum points to redeem',
                                    ),
                                    validator: (value) {
                                      final number = int.tryParse(
                                        value?.trim() ?? '',
                                      );
                                      if (number == null || number < 0) {
                                        return 'Enter a valid whole number.';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _expirationMonthsController,
                                    enabled: !_isSaving,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Point expiration (months)',
                                      helperText:
                                          'Leave empty if points never expire.',
                                    ),
                                    validator: (value) {
                                      final text = value?.trim() ?? '';
                                      if (text.isEmpty) return null;

                                      final number = int.tryParse(text);
                                      if (number == null || number < 1) {
                                        return 'Enter a whole number of at least 1.';
                                      }
                                      return null;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: pos_ui.PrimaryButton.icon(
                              onPressed: _isSaving ? null : _saveSettings,
                              isLoading: _isSaving,
                              icon: const Icon(Icons.save_outlined),
                              label: Text(
                                _isSaving ? 'Saving...' : 'Save Changes',
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          if (_settings != null)
                            Text(
                              'Current settings loaded for ${currentBranch?.name ?? 'the selected branch'}.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
