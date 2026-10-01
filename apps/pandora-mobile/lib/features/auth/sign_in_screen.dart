import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/security/facebook_provider_settings.dart';
import '../../core/security/pandora_auth.dart';
import '../../core/widgets/pandora_mark.dart';

class SignInPresentation {
  const SignInPresentation({
    required this.title,
    required this.subtitle,
    required this.footer,
    this.eyebrow,
    this.brandAsset,
    this.allowFacebookSignIn = true,
    this.backgroundColor,
  });

  static const pandora = SignInPresentation(
    title: "Pandora's Box",
    subtitle: 'Build, change, and publish with Pandora.',
    footer: 'Sign in to continue to your private projects.',
  );

  static const plp = SignInPresentation(
    eyebrow: 'PLP BORACAY · LUXURY RESORT',
    title: 'Pueblo La Perla',
    subtitle: 'Private resort command center',
    footer: 'Authorized PLP owners and staff only.',
    brandAsset: 'assets/workspaces/plp.webp',
    allowFacebookSignIn: false,
    backgroundColor: Color(0xFFFAF7F1),
  );

  final String title;
  final String subtitle;
  final String footer;
  final String? eyebrow;
  final String? brandAsset;
  final bool allowFacebookSignIn;
  final Color? backgroundColor;
}

class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    this.checkFacebookProviderEnabled,
    this.presentation = SignInPresentation.pandora,
  });

  /// Tests may supply a settings read; production always calls Supabase Auth.
  final Future<bool> Function()? checkFacebookProviderEnabled;
  final SignInPresentation presentation;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;
  bool _facebookProviderEnabled = false;

  Future<bool> _providerEnabled() =>
      (widget.checkFacebookProviderEnabled ?? pandoraFacebookProviderEnabled)();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshFacebookProvider();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refreshFacebookProvider();
  }

  Future<void> _refreshFacebookProvider() async {
    if (!widget.presentation.allowFacebookSignIn) {
      return;
    }
    if (!pandoraFacebookSignInSupported(
      isWeb: kIsWeb,
      platform: defaultTargetPlatform,
    )) {
      return;
    }
    var enabled = false;
    try {
      enabled = await _providerEnabled();
    } catch (_) {
      // Settings failures are an unavailable provider, not an OAuth launch.
    }
    if (mounted) setState(() => _facebookProviderEnabled = enabled);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await PandoraDependencies.of(context)
          .auth
          .signIn(email: _email.text.trim(), password: _password.text);
    } on PandoraAuthFailure catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signInWithFacebook() async {
    setState(() => _busy = true);
    try {
      // Recheck at click time: a stale visible button cannot start OAuth after
      // the provider was disabled between the settings read and the tap.
      if (!await _providerEnabled()) {
        if (mounted) setState(() => _facebookProviderEnabled = false);
        _show('Facebook sign-in is not available yet.');
        return;
      }
      if (!mounted) return;
      await PandoraDependencies.of(context).auth.signInWithFacebook();
    } on PandoraAuthFailure catch (error) {
      _show(error.message);
    } catch (_) {
      if (mounted) setState(() => _facebookProviderEnabled = false);
      _show('Facebook sign-in is not available yet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _resetPassword() async {
    final email = _email.text.trim();
    if (email.isEmpty) {
      _show('Enter your email first.');
      return;
    }
    setState(() => _busy = true);
    try {
      await PandoraDependencies.of(context).auth.requestPasswordReset(email);
      _show('Password reset instructions were requested for $email.');
    } on PandoraAuthFailure catch (error) {
      _show(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: widget.presentation.backgroundColor,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(PandoraSpacing.xl),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: AutofillGroup(
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.presentation.brandAsset == null)
                          const Center(
                            child: PandoraMark(size: PandoraSize.signInMark),
                          )
                        else
                          Center(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: SizedBox.square(
                                dimension: 72,
                                child: Image.asset(
                                  widget.presentation.brandAsset!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const PandoraMark(
                                    size: PandoraSize.signInMark,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        const SizedBox(height: PandoraSpacing.xl),
                        if (widget.presentation.eyebrow != null) ...[
                          Text(
                            widget.presentation.eyebrow!,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  letterSpacing: 1.8,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: PandoraSpacing.xs),
                        ],
                        Semantics(
                          header: true,
                          child: Text(
                            widget.presentation.title,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.displaySmall,
                          ),
                        ),
                        const SizedBox(height: PandoraSpacing.xs),
                        Text(
                          widget.presentation.subtitle,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: PandoraSpacing.xxl),
                        TextFormField(
                          controller: _email,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autocorrect: false,
                          autofillHints: const [AutofillHints.username],
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            prefixIcon: Icon(Icons.alternate_email_rounded),
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? 'Enter your email.'
                                  : null,
                        ),
                        const SizedBox(height: PandoraSpacing.sm),
                        TextFormField(
                          controller: _password,
                          obscureText: !_showPassword,
                          enableSuggestions: false,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          onFieldSubmitted: (_) {
                            if (!_busy) _signIn();
                          },
                          decoration: InputDecoration(
                            labelText: 'Password',
                            prefixIcon: const Icon(Icons.lock_outline_rounded),
                            suffixIcon: IconButton(
                              tooltip: _showPassword
                                  ? 'Hide password'
                                  : 'Show password',
                              onPressed: () => setState(
                                  () => _showPassword = !_showPassword),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          validator: (value) => value == null || value.isEmpty
                              ? 'Enter your password.'
                              : null,
                        ),
                        const SizedBox(height: PandoraSpacing.lg),
                        FilledButton(
                          onPressed: _busy ? null : _signIn,
                          child: _busy
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Sign in'),
                        ),
                        TextButton(
                          onPressed: _busy ? null : _resetPassword,
                          child: const Text('Reset password'),
                        ),
                        if (widget.presentation.allowFacebookSignIn &&
                            _facebookProviderEnabled &&
                            pandoraFacebookSignInSupported(
                              isWeb: kIsWeb,
                              platform: defaultTargetPlatform,
                            )) ...[
                          const SizedBox(height: PandoraSpacing.sm),
                          OutlinedButton(
                            onPressed: _busy ? null : _signInWithFacebook,
                            child: const Text('Continue with Facebook'),
                          ),
                        ],
                        const SizedBox(height: PandoraSpacing.sm),
                        Text(
                          widget.presentation.footer,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
