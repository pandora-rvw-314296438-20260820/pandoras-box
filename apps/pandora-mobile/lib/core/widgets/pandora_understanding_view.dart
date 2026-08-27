import 'package:flutter/material.dart';
import '../../core/design/pandora_tokens.dart';

class PandoraUnderstandingView extends StatelessWidget {
  final String intent;
  final VoidCallback onLooksRight;
  final VoidCallback onChange;

  const PandoraUnderstandingView({
    super.key,
    required this.intent,
    required this.onLooksRight,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isAircon = intent.toLowerCase().contains('aircon') || intent.toLowerCase().contains('booking');

    // Dynamic content based on the input intent to keep the experience highly authentic.
    final goalText = isAircon
        ? "Build an online booking system for your aircon technician business."
        : intent;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: PandoraSpacing.md, vertical: PandoraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Step progress indicator
          _buildStepProgress(context),
          const SizedBox(height: PandoraSpacing.lg),

          // Main Title
          Center(
            child: Column(
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Here's what I understand",
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '✨',
                      style: TextStyle(fontSize: 20),
                    ),
                  ],
                ),
                const SizedBox(height: PandoraSpacing.xs),
                Text(
                  "Tell me if I got this right or if you'd like to change anything.",
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.lg),

          // Your Goal card (Red soft highlight)
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF5F5), // Soft red highlight
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFE3E3)),
            ),
            padding: const EdgeInsets.all(PandoraSpacing.md),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(PandoraSpacing.xs),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.rocket_launch_outlined, color: Color(0xFFC72E25), size: 24),
                ),
                const SizedBox(width: PandoraSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your goal',
                        style: TextStyle(
                          color: Color(0xFFC72E25),
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: PandoraSpacing.xxs),
                      Text(
                        goalText,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),

          // This will include card
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            padding: const EdgeInsets.all(PandoraSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.assignment_outlined, color: Color(0xFFC72E25), size: 20),
                    const SizedBox(width: PandoraSpacing.xs),
                    Text(
                      'This will include',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PandoraSpacing.md),
                _buildIncludesGrid(context),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),

          // A few things I'll need from you
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFF9F2), // Soft orange/yellow
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFEAD2)),
            ),
            padding: const EdgeInsets.all(PandoraSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.lightbulb_outline_rounded, color: Color(0xFFB06800), size: 20),
                    const SizedBox(width: PandoraSpacing.xs),
                    Text(
                      "A few things I'll need from you",
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4A3419),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PandoraSpacing.sm),
                _buildNeededBullet("Your business logo (optional)"),
                _buildNeededBullet("Your working hours"),
                _buildNeededBullet("Service types and pricing"),
                _buildNeededBullet("Payment and messaging setup (we'll connect this later)"),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.md),

          // Before we start
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFF4F7FF), // Soft blue
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E9FF)),
            ),
            padding: const EdgeInsets.all(PandoraSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: Color(0xFF4558C0), size: 20),
                    const SizedBox(width: PandoraSpacing.xs),
                    Text(
                      'Before we start',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF202A5C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: PandoraSpacing.md),
                _buildBeforeStartRow(
                  context,
                  icon: Icons.lock_outline_rounded,
                  title: "Safe & reversible",
                  message: "You can review everything before anything goes live.",
                ),
                const SizedBox(height: PandoraSpacing.sm),
                _buildBeforeStartRow(
                  context,
                  icon: Icons.history_rounded,
                  title: "You're in control",
                  message: "I'll ask for approval for important actions.",
                ),
              ],
            ),
          ),
          const SizedBox(height: PandoraSpacing.lg),

          // Primary and secondary buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onChange,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFC72E25),
                    side: const BorderSide(color: Color(0xFFC72E25), width: 1.5),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Change something',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: PandoraSpacing.md),
              Expanded(
                child: ElevatedButton(
                  onPressed: onLooksRight,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC72E25),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text(
                        'Looks good, continue',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: PandoraSpacing.md),
        ],
      ),
    );
  }

  Widget _buildStepProgress(BuildContext context) {
    const activeColor = Color(0xFFC72E25);
    const inactiveColor = Color(0xFFE4E3DE);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Step 1: Ask (Completed style)
          _buildStepCircle(
            icon: Icons.check,
            label: "Ask",
            color: activeColor,
            isCompleted: true,
          ),
          _buildStepLine(activeColor),
          // Step 2: Understand (Active style)
          _buildStepCircle(
            text: "2",
            label: "Understand",
            color: activeColor,
            isActive: true,
          ),
          _buildStepLine(inactiveColor),
          // Step 3: Build
          _buildStepCircle(
            text: "3",
            label: "Build",
            color: inactiveColor,
          ),
          _buildStepLine(inactiveColor),
          // Step 4: Review
          _buildStepCircle(
            text: "4",
            label: "Review",
            color: inactiveColor,
          ),
        ],
      ),
    );
  }

  Widget _buildStepCircle({
    IconData? icon,
    String? text,
    required String label,
    required Color color,
    bool isActive = false,
    bool isCompleted = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: (isActive || isCompleted) ? color : Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 2),
          ),
          child: Center(
            child: icon != null
                ? Icon(icon, size: 14, color: Colors.white)
                : Text(
                    text ?? "",
                    style: TextStyle(
                      color: isActive ? Colors.white : color,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: (isActive || isCompleted) ? FontWeight.bold : FontWeight.normal,
            color: (isActive || isCompleted) ? const Color(0xFF1E2022) : const Color(0xFF7D7F82),
          ),
        ),
      ],
    );
  }

  Widget _buildStepLine(Color color) {
    return Container(
      width: 40,
      height: 2,
      color: color,
      margin: const EdgeInsets.only(bottom: 14), // aligned with circle centers
    );
  }

  Widget _buildIncludesGrid(BuildContext context) {
    final includes = [
      _IncludeItem(
        icon: Icons.calendar_today_outlined,
        title: "Customer booking page",
        subtitle: "Customers can choose service, date and time.",
      ),
      _IncludeItem(
        icon: Icons.person_outline_rounded,
        title: "Technician schedule",
        subtitle: "Your staff can manage their appointments.",
      ),
      _IncludeItem(
        icon: Icons.notifications_none_rounded,
        title: "Automatic confirmations",
        subtitle: "Customers get booking confirmation instantly.",
      ),
      _IncludeItem(
        icon: Icons.chat_bubble_outline_rounded,
        title: "Reminders",
        subtitle: "Automatic reminders before the appointment.",
      ),
      _IncludeItem(
        icon: Icons.bar_chart_rounded,
        title: "Owner dashboard",
        subtitle: "See bookings, jobs and business overview.",
      ),
      _IncludeItem(
        icon: Icons.phone_android_rounded,
        title: "Mobile friendly",
        subtitle: "Looks great on phones, tablets and desktop.",
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: PandoraSpacing.md,
        crossAxisSpacing: PandoraSpacing.md,
        childAspectRatio: 1.3,
      ),
      itemCount: includes.length,
      itemBuilder: (context, index) {
        final item = includes[index];
        return Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAFAFA),
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(PandoraSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(PandoraSpacing.xxs),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF5F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(item.icon, color: const Color(0xFFC72E25), size: 18),
              ),
              const SizedBox(height: PandoraSpacing.xs),
              Text(
                item.title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Expanded(
                child: Text(
                  item.subtitle,
                  style: const TextStyle(color: Color(0xFF5A5C5E), fontSize: 11, height: 1.3),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNeededBullet(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Color(0xFFB06800), size: 18),
          const SizedBox(width: PandoraSpacing.xs),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                color: Color(0xFF4A3419),
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeforeStartRow(BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(PandoraSpacing.xs),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFE2E9FF)),
          ),
          child: Icon(icon, color: const Color(0xFF4558C0), size: 18),
        ),
        const SizedBox(width: PandoraSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF202A5C),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                message,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF525E92),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IncludeItem {
  final IconData icon;
  final String title;
  final String subtitle;

  _IncludeItem({
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}
