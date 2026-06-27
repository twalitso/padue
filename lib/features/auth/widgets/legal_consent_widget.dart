// lib/features/auth/widgets/legal_consent_widget.dart

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../screens/legal_viewer_screen.dart';

class LegalConsentWidget extends StatefulWidget {
  final bool showMarketingOptIn;
  final bool showAgeVerification;
  final bool showLocationConsent;

  const LegalConsentWidget({
    super.key,
    this.showMarketingOptIn = true,
    this.showAgeVerification = true,
    this.showLocationConsent = false,
  });

  @override
  State<LegalConsentWidget> createState() => LegalConsentWidgetState();
}

class LegalConsentWidgetState extends State<LegalConsentWidget> {
  bool _agreeTerms = false;
  bool _agreePrivacy = false;
  bool _isOver18 = false;
  bool _locationConsent = false;
  bool _marketingConsent = false;

  String? _error;

  bool get isValid =>
      _agreeTerms &&
      _agreePrivacy &&
      (!widget.showAgeVerification || _isOver18) &&
      (!widget.showLocationConsent || _locationConsent);

  Map<String, dynamic> getConsentData() {
    return {
      'acceptedTerms': _agreeTerms,
      'acceptedPrivacy': _agreePrivacy,
      'isOver18': _isOver18,
      'locationConsent': _locationConsent,
      'marketingConsent': _marketingConsent,
      'acceptedAt': FieldValue.serverTimestamp(),
      'version': '1.0',
    };
  }

    // ✅ These two methods were missing
  void showError(String message) {
    setState(() => _error = message);
  }

  void clearError() {
    setState(() => _error = null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Terms & Privacy
        CheckboxListTile(
          title: RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.black87),
              children: [
                const TextSpan(text: 'I agree to the '),
                TextSpan(
                  text: 'Terms of Service',
                  style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _showLegalDocument(
                          context,
                          'Terms of Service',
                          termsContent, // ← defined below
                        ),
                ),
                const TextSpan(text: ' and '),
                TextSpan(
                  text: 'Privacy Policy',
                  style: const TextStyle(color: Colors.blue, decoration: TextDecoration.underline),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => _showLegalDocument(
                          context,
                          'Privacy Policy',
                          privacyContent,
                        ),
                ),
              ],
            ),
          ),
          value: _agreeTerms && _agreePrivacy,
          onChanged: (val) {
            setState(() {
              _agreeTerms = val ?? false;
              _agreePrivacy = val ?? false;
              _error = null;
            });
          },
          controlAffinity: ListTileControlAffinity.leading,
        ),

        // Other checkboxes (same as before)
        if (widget.showAgeVerification)
          CheckboxListTile(
            title: const Text("I confirm I am at least 18 years old"),
            value: _isOver18,
            onChanged: (val) => setState(() => _isOver18 = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),

        if (widget.showLocationConsent)
          CheckboxListTile(
            title: const Text("I consent to the use of my precise location for service matching"),
            value: _locationConsent,
            onChanged: (val) => setState(() => _locationConsent = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),

        if (widget.showMarketingOptIn)
          CheckboxListTile(
            title: const Text("I agree to receive marketing communications (optional)"),
            value: _marketingConsent,
            onChanged: (val) => setState(() => _marketingConsent = val ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),

        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ),
      ],
    );
  }

  void _showLegalDocument(BuildContext context, String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalViewerScreen(title: title, content: content),
      ),
    );
  }



  // ==================== LEGAL DOCUMENTS ====================

static const String termsContent = '''
Terms of Service

Last updated: May 26, 2026

1. Introduction
Welcome to Padue (the "Platform"), operated by Padue Technologies ("we", "us", or "our"). 

By creating an account or using our Platform, you agree to be bound by these Terms of Service. If you do not agree, please do not use the Platform.

2. Our Service
Padue is a marketplace platform that connects users seeking roadside assistance, towing, tire repair, battery jump-start, fuel delivery, and home assistance services with independent service providers.

We do not provide these services ourselves. All services are performed by independent third-party providers.

3. User Accounts
- You must be at least 18 years old to use the Platform.
- You are responsible for maintaining the confidentiality of your account credentials.
- You agree to provide accurate and complete information.

4. Providers
- Providers are independent contractors and not employees of Padue.
- Providers are solely responsible for the quality, safety, and performance of the services they provide.
- Providers must maintain valid insurance, licenses, and permits as required by law.

5. Bookings and Payments
- All bookings are made directly between users and providers through the Platform.
- Payments are processed securely. Cancellation and refund policies are displayed before booking.
- Service fees and pricing are set by providers or as displayed on the Platform.

6. User Responsibilities
- Provide accurate location and service details.
- Be present at the agreed location at the scheduled time.
- Treat providers with respect.
- Do not request illegal or unsafe services.

7. Prohibited Conduct
You agree not to misuse the Platform, including but not limited to fraud, harassment, providing false information, or attempting to circumvent our systems.

8. Limitation of Liability
To the fullest extent permitted by law:
- Padue is not liable for any acts, omissions, or services provided by independent providers.
- We are not responsible for any damage to your vehicle, property, or any personal injury arising from services.
- Our total liability shall not exceed the amount you paid for the relevant service.

9. Disclaimers
The Platform is provided "as is". We do not guarantee continuous availability, accuracy of provider information, or quality of services.

10. Termination
We reserve the right to suspend or terminate your account at our discretion if you violate these Terms.

11. Governing Law
These Terms shall be governed by the laws of the Republic of Zambia. Any disputes shall be resolved in the courts of Zambia.

12. Changes to Terms
We may update these Terms from time to time. Continued use of the Platform after changes constitutes acceptance of the new Terms.

Contact Us: support@padue.com
''';

static const String privacyContent = '''
Privacy Policy

Last updated: May 26, 2026

1. Introduction
Padue Technologies ("Padue", "we", "us") respects your privacy. This Privacy Policy explains how we collect, use, disclose, and protect your information when you use our mobile application and services.

2. Information We Collect

a. Information You Provide:
- Name, email address, phone number
- Vehicle details
- Location information (when you request services)
- Payment information
- Government-issued ID or insurance documents (for providers)

b. Automatically Collected Information:
- Precise geolocation data
- Device information and IP address
- Usage data and app interactions

3. How We Use Your Information
- To create and manage your account
- To match you with nearby service providers
- To process payments and bookings
- To send service updates and notifications
- To improve our services and user experience
- For customer support and dispute resolution
- To comply with legal obligations

4. Sharing Your Information
- With service providers you book (name, phone, location, vehicle details)
- With payment processors
- With legal authorities when required by law
- With service partners for analytics and crash reporting (anonymized where possible)

We do not sell your personal data to third parties for marketing purposes.

5. Location Data
Precise location data is essential for matching you with providers. You can control location permissions through your device settings. Location data is shared only during active service requests.

6. Data Security
We implement reasonable technical and organizational measures to protect your data. However, no system is completely secure.

7. Your Rights
You may:
- Access, correct, or delete your personal data
- Withdraw consent where applicable
- Opt out of marketing communications

To exercise these rights, contact us at support@padue.com

8. Data Retention
We retain your data for as long as your account is active or as needed for legal and operational purposes.

9. Children's Privacy
Our services are not directed to children under 18. We do not knowingly collect data from children.

10. Changes to this Policy
We may update this Privacy Policy. We will notify you of material changes via the app or email.

11. Contact Us
For any privacy questions, please contact: support@padue.com

This policy is governed by the laws of the Republic of Zambia.
''';
}