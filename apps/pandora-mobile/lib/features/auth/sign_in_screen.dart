import 'package:flutter/material.dart';

import '../../app/pandora_dependencies.dart';
import '../../core/design/pandora_tokens.dart';
import '../../core/security/pandora_auth.dart';
import '../../core/widgets/pandora_mark.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await PandoraDependencies.of(context).auth
          .signIn(email: _email.text.trim(), password: _password.text);
    } on PandoraAuthFailure catch (error) {
      _show(error.message);
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
                    const Center(
                      child: PandoraMark(size: PandoraSize.signInMark),
                    ),
                    const SizedBox(height: PandoraSpacing.xl),
                    Semantics(
                      header: true,
                      child: Text(
                        "Pandora's Box",
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.displaySmall,
                      ),
                    ),
                    const SizedBox(height: PandoraSpacing.xs),
                    Text(
                      'Your private owner control surface.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
                          onPressed: () =>
                              setState(() => _showPassword = !_showPassword),
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
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Sign in securely'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : _resetPassword,
                      child: const Text('Reset password'),
                    ),
                    const SizedBox(height: PandoraSpacing.sm),
                    Text(
                      'If your session expires, Pandora asks you to sign in again. '
                      'Protected actions still require server authorization.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
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
