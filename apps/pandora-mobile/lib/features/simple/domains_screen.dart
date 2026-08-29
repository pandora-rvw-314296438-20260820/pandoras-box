import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/data/pandora_repository.dart';
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
            _DomainAcquisitionCard(
              onTap: () => _openDomainsSurface(
                context,
                const DomainAcquisitionScreen(),
              ),
            ),
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
                onAction: () => _openDomainsSurface(
                  context,
                  const DomainAcquisitionScreen(),
                ),
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
            foreground: live
                ? PandoraSimpleColors.green
                : PandoraSimpleColors.deepRed,
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
          color: live ? PandoraSimpleColors.greenWash : PandoraSimpleColors.blush,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: live ? PandoraSimpleColors.green : PandoraSimpleColors.deepRed,
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

class _DomainAcquisitionScreenState extends State<DomainAcquisitionScreen> {
  final TextEditingController _domain = TextEditingController();

  @override
  void dispose() {
    _domain.dispose();
    super.dispose();
  }

  void _search() {
    final query = _domain.text.trim();
    if (query.isEmpty) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Domain purchasing needs the RedApple registrar connection before checkout can go live.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => PandoraSimplePage(
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
              onSubmitted: (_) => _search(),
              decoration: const InputDecoration(
                labelText: 'Domain',
                hintText: 'mybusiness.com',
                prefixIcon: Icon(Icons.language_rounded),
              ),
            ),
            const SizedBox(height: 16),
            PandoraPrimaryButton(
              label: 'Search domains',
              icon: Icons.search_rounded,
              onPressed: _search,
              expanded: true,
            ),
            const SizedBox(height: 18),
            const PandoraSimpleCard(
              shadow: false,
              child: Text(
                'Already own a domain? You can add it when you publish a project. Pandora will verify DNS, routing and security before showing it as Live.',
                style: pandoraSimpleMutedText,
              ),
            ),
          ],
        ),
      );
}
