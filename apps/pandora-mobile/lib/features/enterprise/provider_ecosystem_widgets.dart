
part of 'provider_ecosystem_screen.dart';

class _CapabilityTile extends StatelessWidget {
  const _CapabilityTile({required this.family, required this.onTap});

  final _CapabilityFamily family;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final preview = family.providers.take(3).join(' · ');
    final remaining = family.providers.length - 3;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: PandoraV2Colors.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border.all(color: PandoraV2Colors.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: PandoraV2Colors.soft,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(family.icon, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        family.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        remaining > 0 ? '$preview · +$remaining' : preview,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PandoraV2Colors.muted,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: PandoraV2Colors.muted,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _OutcomeCard extends StatelessWidget {
  const _OutcomeCard({required this.outcome});

  final _ProviderOutcome outcome;

  @override
  Widget build(BuildContext context) => Container(
        width: 190,
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: PandoraV2Colors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PandoraV2Colors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '“${outcome.command}”',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
            const Spacer(),
            Text(
              outcome.route,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: PandoraV2Colors.muted,
                fontSize: 11.5,
                height: 1.3,
              ),
            ),
          ],
        ),
      );
}

class _CapabilityFamily {
  const _CapabilityFamily({
    required this.name,
    required this.icon,
    required this.providers,
  });

  final String name;
  final IconData icon;
  final List<String> providers;
}

class _ProviderOutcome {
  const _ProviderOutcome(this.command, this.route);

  final String command;
  final String route;
}
