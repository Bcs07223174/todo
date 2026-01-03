import 'package:flutter/material.dart';

import '../theme/text_styles.dart';
import '../widgets/responsive_container.dart';

class LegalScreen extends StatelessWidget {
  const LegalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: AppBar(
          title: Text('Legal', style: AppTextStyles.h2.copyWith(color: Theme.of(context).colorScheme.onSurface)),
          backgroundColor: Colors.transparent,
          elevation: 0,
          iconTheme: IconThemeData(color: Theme.of(context).colorScheme.onSurface),
          bottom: TabBar(
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
            indicatorColor: Theme.of(context).colorScheme.primary,
            tabs: const [
              Tab(text: 'Privacy Policy'),
              Tab(text: 'Terms of Service'),
            ],
          ),
        ),
        body: const SafeArea(
          child: ResponsiveContainer(
            child: TabBarView(
              children: [
                _PrivacyPolicyContent(),
                _TermsOfServiceContent(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrivacyPolicyContent extends StatelessWidget {
  const _PrivacyPolicyContent();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        'Privacy Policy\n\n'
        '1. Introduction\n'
        'Welcome to Neon Task. We respect your privacy and are committed to protecting your personal data.\n\n'
        '2. Data We Collect\n'
        'We collect information you provide directly to us, such as when you create an account, create tasks, or contact us.\n\n'
        '3. How We Use Your Data\n'
        'We use your data to provide, maintain, and improve our services, and to communicate with you.\n\n'
        '4. Data Security\n'
        'We implement appropriate security measures to protect your personal data.\n\n'
        '5. Contact Us\n'
        'If you have any questions about this Privacy Policy, please contact us.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
      ),
    );
  }
}

class _TermsOfServiceContent extends StatelessWidget {
  const _TermsOfServiceContent();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Text(
        'Terms of Service\n\n'
        '1. Acceptance of Terms\n'
        'By accessing or using Neon Task, you agree to be bound by these Terms of Service.\n\n'
        '2. Use of Service\n'
        'You agree to use the service only for lawful purposes and in accordance with these Terms.\n\n'
        '3. User Accounts\n'
        'You are responsible for maintaining the confidentiality of your account and password.\n\n'
        '4. Termination\n'
        'We reserve the right to terminate or suspend your account at any time for any reason.\n\n'
        '5. Changes to Terms\n'
        'We may modify these Terms at any time. Your continued use of the service constitutes acceptance of the changes.',
        style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
      ),
    );
  }
}
