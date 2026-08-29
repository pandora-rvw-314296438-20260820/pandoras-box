import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/domain_registrar_api.dart';
import '../../core/data/pandora_repository.dart';
import '../../core/models/domain_registrar_models.dart';
import '../../core/models/pandora_models.dart';
import '../approvals/approvals_screen.dart';
import '../settings/settings_screen.dart';
import 'pandora_simple_ui.dart';

void _openDomainsSurface(BuildContext context, Widget screen) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
}

class DomainsScreen extends StatefulWidget {
  const DomainsScreen({super.key});

  @override
  State<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends State<DomainsScreen> {
  HomeSummary? _summary;
  String? _error;
  var _loading = true;
  var _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    unawaited(_load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final snapshot = await PandoraDependencies.of(context).repository.home();
      if (!mounted) return;
      setState(() {
        _summary = snapshot.data;
        _loading = false;
      });
    } on PandoraRepositoryException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pandora could not verify your domains right now.';
        _loading = false;
      });
    }
  }

  Future<void> _openAcquisition() async {
    final purchased = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const DomainAcquisitionScreen()),
    );
    if (purchased == true) await _load();
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
        onRefresh: _load,
        header: PandoraOwnerHeader(
          title: 'Domains',
          subtitle: 'Your business addresses in one place.',
          showBack: true,
          onBack: () => Navigator.of(context).maybePop(),
          onNotifications: () =>
              _openDomainsSurface(context, const ApprovalsScreen()),
          onAvatar: () => _openDomainsSurface(context, const SettingsScreen()),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DomainAcquisitionCard(onTap: () => unawaited(_openAcquisition())),
            const SizedBox(height: 22),
            const PandoraSectionTitle(title: 'Your domains'),
            if (_loading)
              const PandoraSimpleCard(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: CircularProgressIndicator(
                      color: PandoraSimpleColors.red,
                    ),
                  ),
                ),
              )
            else if (_error != null)
              PandoraEmptyTruth(
                title: 'Domains unavailable',
                message: _error!,
                actionLabel: 'Check again',
                onAction: _load,
              )
            else if ((_summary?.domains ?? const <DomainSummary>[]).isEmpty)
              PandoraEmptyTruth(
                title: 'No domains yet',
                message:
                    'Your connected and published domains will appear here.',
                actionLabel: 'Get a domain',
                onAction: () => unawaited(_openAcquisition()),
              )
            else
              for (final domain in _summary!.domains) ...[
                _DomainCard(domain: domain),
                const SizedBox(height: 12),
              ],
          ],
        ),
      );
}

class _DomainAcquisitionCard extends StatelessWidget {
  const _DomainAcquisitionCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PandoraSimpleCard(
        onTap: onTap,
        backgroundColor: const Color(0xFFFFF8F9),
        borderColor: const Color(0xFFF2D9DE),
        child: Row(
          children: [
            const PandoraIconBadge(icon: Icons.language_rounded, size: 52),
            const SizedBox(width: 15),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Get a domain',
                    style: TextStyle(
                      color: PandoraSimpleColors.ink,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Choose the address customers will use to find you.',
                    style: pandoraSimpleMutedText,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              color: PandoraSimpleColors.red,
              size: 18,
            ),
          ],
        ),
      );
}

class _DomainCard extends StatelessWidget {
  const _DomainCard({required this.domain});

  final DomainSummary domain;

  @override
  Widget build(BuildContext context) {
    final live = domain.isLive;
    return PandoraSimpleCard(
      shadow: false,
      child: Row(
        children: [
          PandoraIconBadge(
            icon: Icons.public_rounded,
            size: 48,
            foreground:
                live ? PandoraSimpleColors.green : PandoraSimpleColors.deepRed,
            background: live
                ? PandoraSimpleColors.greenWash
                : PandoraSimpleColors.blush,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  domain.domain,
                  style: const TextStyle(
                    color: PandoraSimpleColors.ink,
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(domain.projectName, style: pandoraSimpleMutedText),
                const SizedBox(height: 7),
                _DomainStatus(label: domain.statusLabel, live: live),
              ],
            ),
          ),
          if (domain.primaryDomain)
            const Padding(
              padding: EdgeInsets.only(left: 10),
              child: Text(
                'Primary',
                style: TextStyle(
                  color: PandoraSimpleColors.muted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _DomainStatus extends StatelessWidget {
  const _DomainStatus({required this.label, required this.live});

  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color:
              live ? PandoraSimpleColors.greenWash : PandoraSimpleColors.blush,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color:
                live ? PandoraSimpleColors.green : PandoraSimpleColors.deepRed,
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
}

class DomainAcquisitionScreen extends StatefulWidget {
  const DomainAcquisitionScreen({super.key});

  @override
  State<DomainAcquisitionScreen> createState() =>
      _DomainAcquisitionScreenState();
}

class _DomainAcquisitionScreenState extends State<DomainAcquisitionScreen>
    with WidgetsBindingObserver {
  final TextEditingController _domain = TextEditingController();
  final TextEditingController _firstName = TextEditingController();
  final TextEditingController _lastName = TextEditingController();
  final TextEditingController _email = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _address1 = TextEditingController();
  final TextEditingController _address2 = TextEditingController();
  final TextEditingController _city = TextEditingController();
  final TextEditingController _state = TextEditingController();
  final TextEditingController _zip = TextEditingController();
  final TextEditingController _country = TextEditingController(text: 'PH');
  final TextEditingController _companyName = TextEditingController();

  List<ProjectSummary> _projects = const <ProjectSummary>[];
  ProjectSummary? _project;
  DomainQuote? _quote;
  DomainCheckout? _checkout;
  DomainPaymentGateway _gateway = DomainPaymentGateway.xendit;
  String? _error;
  var _started = false;
  var _loadingProjects = true;
  var _searching = false;
  var _startingCheckout = false;
  var _reconciling = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_loadProjects());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _checkout?.canReconcile == true &&
        !_reconciling) {
      unawaited(_reconcileCheckout());
    }
  }

  @override
  void dispose() {
    if (_started) WidgetsBinding.instance.removeObserver(this);
    for (final controller in <TextEditingController>[
      _domain,
      _firstName,
      _lastName,
      _email,
      _phone,
      _address1,
      _address2,
      _city,
      _state,
      _zip,
      _country,
      _companyName,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadProjects() async {
    try {
      final snapshot =
          await PandoraDependencies.of(context).repository.projects();
      if (!mounted) return;
      final projects = snapshot.data;
      setState(() {
        _projects = projects;
        _project = projects.isEmpty ? null : projects.first;
        _loadingProjects = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingProjects = false;
        _error = 'Pandora could not load your projects right now.';
      });
    }
  }

  Future<void> _search() async {
    final query = _domain.text.trim();
    if (query.isEmpty || _searching || _startingCheckout) return;
    final registrar = PandoraDependencies.of(context).domainRegistrar;
    if (registrar == null) {
      setState(
        () => _error = 'Domain registration is not available in this build.',
      );
      return;
    }
    setState(() {
      _searching = true;
      _quote = null;
      _checkout = null;
      _error = null;
    });
    try {
      final quote = await registrar.quoteDomain(query);
      if (!mounted) return;
      setState(() {
        _quote = quote;
        _domain.text = quote.domain;
        _searching = false;
      });
    } on DomainRegistrarException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _searching = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pandora could not check that domain right now.';
        _searching = false;
      });
    }
  }

  Map<String, Object?>? _contactInformation() {
    final required = <String, TextEditingController>{
      'First name': _firstName,
      'Last name': _lastName,
      'Email': _email,
      'Phone': _phone,
      'Address': _address1,
      'City': _city,
      'State / province': _state,
      'Postal code': _zip,
      'Country': _country,
    };
    for (final entry in required.entries) {
      if (entry.value.text.trim().isEmpty) {
        setState(() => _error = '${entry.key} is required for registration.');
        return null;
      }
    }
    if (!_email.text.contains('@')) {
      setState(() => _error = 'Enter a valid registration email.');
      return null;
    }
    if (!RegExp(r'^\+[1-9][0-9]{7,14}$').hasMatch(_phone.text.trim())) {
      setState(
        () =>
            _error = 'Use an international phone number such as +639171234567.',
      );
      return null;
    }
    final country = _country.text.trim().toUpperCase();
    if (!RegExp(r'^[A-Z]{2}$').hasMatch(country)) {
      setState(() => _error = 'Use a two-letter country code such as PH.');
      return null;
    }
    return <String, Object?>{
      'firstName': _firstName.text.trim(),
      'lastName': _lastName.text.trim(),
      'email': _email.text.trim(),
      'phone': _phone.text.trim(),
      'address1': _address1.text.trim(),
      if (_address2.text.trim().isNotEmpty) 'address2': _address2.text.trim(),
      'city': _city.text.trim(),
      'state': _state.text.trim(),
      'zip': _zip.text.trim(),
      'country': country,
      if (_companyName.text.trim().isNotEmpty)
        'companyName': _companyName.text.trim(),
    };
  }

  Future<void> _startCheckout() async {
    final quote = _quote;
    final project = _project;
    final registrar = PandoraDependencies.of(context).domainRegistrar;
    if (quote == null || !quote.available || quote.displayPrice == null) return;
    if (project == null) {
      setState(() => _error = 'Choose a project for this domain.');
      return;
    }
    if (quote.hasUnsupportedAdditionalContactFields) {
      setState(
        () => _error =
            'This domain ending needs extra registration details that Pandora does not support yet. Choose another domain for now.',
      );
      return;
    }
    final contact = _contactInformation();
    if (contact == null || registrar == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Pay for ${quote.domain}?'),
        content: Text(
          '${quote.formattedPurchasePrice} ${quote.currency} will be paid through ${_gateway.label}. '
          'Pandora registers the domain only after payment is confirmed, then connects it to ${project.name}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Continue to payment'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _startingCheckout = true;
      _error = null;
    });
    try {
      final checkout = await registrar.createCheckout(
        projectIdentifier: project.id,
        quote: quote,
        gateway: _gateway,
        contactInformation: contact,
        autoRenewRequested: false,
      );
      if (!mounted) return;
      setState(() {
        _checkout = checkout;
        _startingCheckout = false;
      });
      if (checkout.checkoutUrl != null) {
        await _openPayment(checkout.checkoutUrl!);
      }
    } on DomainRegistrarException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _startingCheckout = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'RedApple could not start the payment checkout.';
        _startingCheckout = false;
      });
    }
  }

  Future<void> _openPayment(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null || uri.scheme != 'https') {
      if (mounted) {
        setState(
          () => _error = 'That payment link could not be opened safely.',
        );
      }
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        setState(() => _error = 'The payment page could not be opened.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'The payment page could not be opened.');
      }
    }
  }

  Future<void> _reconcileCheckout() async {
    final checkout = _checkout;
    final registrar = PandoraDependencies.of(context).domainRegistrar;
    if (checkout == null || registrar == null || _reconciling) return;
    setState(() {
      _reconciling = true;
      _error = null;
    });
    try {
      final updated = await registrar.reconcileCheckout(checkout.checkoutId);
      if (!mounted) return;
      setState(() {
        _checkout = updated;
        _reconciling = false;
      });
      if (updated.isFulfilled) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${updated.domain} is registered. Pandora is connecting it to your project.',
            ),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } on DomainRegistrarException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _reconciling = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Pandora could not confirm that payment yet.';
        _reconciling = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = _quote;
    final checkout = _checkout;
    return PandoraSimplePage(
      header: PandoraOwnerHeader(
        title: 'Get a domain',
        subtitle: 'Find the right address for your project.',
        showBack: true,
        onBack: () => Navigator.of(context).maybePop(),
        onNotifications: () =>
            _openDomainsSurface(context, const ApprovalsScreen()),
        onAvatar: () => _openDomainsSurface(context, const SettingsScreen()),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Find your domain',
            style: TextStyle(
              color: PandoraSimpleColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w700,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Search for the name customers should use to reach your business.',
            style: pandoraSimpleMutedText,
          ),
          const SizedBox(height: 22),
          TextField(
            controller: _domain,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enabled: !_searching && !_startingCheckout,
            onSubmitted: (_) => unawaited(_search()),
            decoration: const InputDecoration(
              labelText: 'Domain',
              hintText: 'mybusiness.com',
              prefixIcon: Icon(Icons.language_rounded),
            ),
          ),
          const SizedBox(height: 16),
          PandoraPrimaryButton(
            label: _searching ? 'Checking…' : 'Check availability',
            icon: Icons.search_rounded,
            onPressed: _searching || _startingCheckout
                ? null
                : () => unawaited(_search()),
            expanded: true,
          ),
          if (_error != null) ...[
            const SizedBox(height: 14),
            Text(
              _error!,
              style: const TextStyle(
                color: PandoraSimpleColors.deepRed,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (quote != null) ...[
            const SizedBox(height: 22),
            if (!quote.available)
              PandoraSimpleCard(
                shadow: false,
                child: Row(
                  children: [
                    const PandoraIconBadge(
                      icon: Icons.close_rounded,
                      foreground: PandoraSimpleColors.deepRed,
                      background: PandoraSimpleColors.blush,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        '${quote.domain} is not available.',
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else ...[
              PandoraSimpleCard(
                shadow: false,
                child: Row(
                  children: [
                    const PandoraIconBadge(
                      icon: Icons.check_rounded,
                      foreground: PandoraSimpleColors.green,
                      background: PandoraSimpleColors.greenWash,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            quote.domain,
                            style: const TextStyle(
                              color: PandoraSimpleColors.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${quote.formattedPurchasePrice} ${quote.currency} for ${quote.years} year${quote.years == 1 ? '' : 's'}',
                            style: pandoraSimpleMutedText,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const PandoraSectionTitle(title: 'Connect to project'),
              if (_loadingProjects)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: CircularProgressIndicator(
                      color: PandoraSimpleColors.red,
                    ),
                  ),
                )
              else if (_projects.isEmpty)
                const PandoraSimpleCard(
                  shadow: false,
                  child: Text(
                    'Create a project before buying a domain.',
                    style: pandoraSimpleMutedText,
                  ),
                )
              else
                DropdownButtonFormField<ProjectSummary>(
                  value: _project,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Project',
                    prefixIcon: Icon(Icons.folder_outlined),
                  ),
                  items: _projects
                      .map(
                        (project) => DropdownMenuItem<ProjectSummary>(
                          value: project,
                          child: Text(
                            project.name,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: _startingCheckout
                      ? null
                      : (value) => setState(() => _project = value),
                ),
              const SizedBox(height: 22),
              const PandoraSectionTitle(title: 'Registration details'),
              const Text(
                'These details are encrypted temporarily for checkout and deleted after registration or refund.',
                style: pandoraSimpleMutedText,
              ),
              const SizedBox(height: 14),
              _ContactField(controller: _firstName, label: 'First name'),
              _ContactField(controller: _lastName, label: 'Last name'),
              _ContactField(
                controller: _email,
                label: 'Email',
                keyboardType: TextInputType.emailAddress,
              ),
              _ContactField(
                controller: _phone,
                label: 'Phone',
                hint: '+639171234567',
                keyboardType: TextInputType.phone,
              ),
              _ContactField(
                controller: _companyName,
                label: 'Company (optional)',
              ),
              _ContactField(controller: _address1, label: 'Address'),
              _ContactField(
                controller: _address2,
                label: 'Address line 2 (optional)',
              ),
              _ContactField(controller: _city, label: 'City'),
              _ContactField(controller: _state, label: 'State / province'),
              _ContactField(controller: _zip, label: 'Postal code'),
              _ContactField(
                controller: _country,
                label: 'Country code',
                hint: 'PH',
                textCapitalization: TextCapitalization.characters,
              ),
              const SizedBox(height: 8),
              const PandoraSectionTitle(title: 'Pay with'),
              SegmentedButton<DomainPaymentGateway>(
                segments: const <ButtonSegment<DomainPaymentGateway>>[
                  ButtonSegment<DomainPaymentGateway>(
                    value: DomainPaymentGateway.xendit,
                    label: Text('Xendit'),
                  ),
                  ButtonSegment<DomainPaymentGateway>(
                    value: DomainPaymentGateway.paypal,
                    label: Text('PayPal'),
                  ),
                ],
                selected: <DomainPaymentGateway>{_gateway},
                onSelectionChanged: _startingCheckout
                    ? null
                    : (selection) => setState(() => _gateway = selection.first),
              ),
              const SizedBox(height: 12),
              const PandoraSimpleCard(
                shadow: false,
                child: Text(
                  'Auto-renew is off for now. RedApple will ask you before renewal so there are no surprise charges.',
                  style: pandoraSimpleMutedText,
                ),
              ),
              const SizedBox(height: 12),
              if (checkout == null)
                PandoraPrimaryButton(
                  label: _startingCheckout
                      ? 'Starting payment…'
                      : 'Pay & register ${quote.domain}',
                  icon: Icons.lock_outline_rounded,
                  onPressed: _startingCheckout || _project == null
                      ? null
                      : () => unawaited(_startCheckout()),
                  expanded: true,
                )
              else ...[
                PandoraSimpleCard(
                  shadow: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        _checkoutHeadline(checkout),
                        style: const TextStyle(
                          color: PandoraSimpleColors.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        checkout.plainMessage ??
                            'Return to Pandora after payment to finish registration.',
                        style: pandoraSimpleMutedText,
                      ),
                      if (checkout.canOpenPayment) ...[
                        const SizedBox(height: 14),
                        PandoraSecondaryButton(
                          label: 'Open ${checkout.gateway.label}',
                          icon: Icons.open_in_new_rounded,
                          onPressed: () =>
                              unawaited(_openPayment(checkout.checkoutUrl!)),
                          expanded: true,
                        ),
                      ],
                      if (checkout.canReconcile) ...[
                        const SizedBox(height: 10),
                        PandoraPrimaryButton(
                          label: _reconciling
                              ? 'Checking payment…'
                              : 'Check payment',
                          icon: Icons.verified_outlined,
                          onPressed: _reconciling
                              ? null
                              : () => unawaited(_reconcileCheckout()),
                          expanded: true,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ],
          const SizedBox(height: 18),
          const PandoraSimpleCard(
            shadow: false,
            child: Text(
              'Already own a domain? Add it when you publish a project. Pandora verifies ownership, DNS, routing and security before showing it as Live.',
              style: pandoraSimpleMutedText,
            ),
          ),
        ],
      ),
    );
  }

  String _checkoutHeadline(DomainCheckout checkout) =>
      switch (checkout.status) {
        'fulfilled' => '${checkout.domain} is registered',
        'refunded' => 'Payment refunded',
        'refund_pending' => 'Refund processing',
        'needs_attention' => 'Pandora is checking this payment',
        'expired' => 'Payment expired',
        'failed' => 'Payment could not start',
        _ => 'Finish payment with ${checkout.gateway.label}',
      };
}

class _ContactField extends StatelessWidget {
  const _ContactField({
    required this.controller,
    required this.label,
    this.hint,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String label;
  final String? hint;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          keyboardType: keyboardType,
          textCapitalization: textCapitalization,
          decoration: InputDecoration(labelText: label, hintText: hint),
        ),
      );
}
