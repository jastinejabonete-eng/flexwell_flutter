import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_colors.dart';
import 'fade_route.dart';
import 'main_navigation_screen.dart';

/// Remembers whether the user accepted the current version of the terms.
/// Bump [currentVersion] whenever the text changes materially and every user
/// will be asked to accept again.
class TermsService {
  static const int currentVersion = 1;
  static const String _key = 'terms_accepted_version';

  /// Never throws; if storage fails the user is simply asked again.
  static Future<bool> hasAccepted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return (prefs.getInt(_key) ?? 0) >= currentVersion;
    } catch (e) {
      debugPrint('Reading terms acceptance failed: $e');
      return false;
    }
  }

  static Future<void> accept() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_key, currentVersion);
    } catch (e) {
      debugPrint('Saving terms acceptance failed: $e');
    }
  }
}

class _TermItem {
  /// Optional bold lead-in, e.g. "Assumption of Risk:".
  final String? lead;
  final String text;
  const _TermItem(this.text, {this.lead});
}

class _TermSection {
  final String title;
  final List<_TermItem> items;
  const _TermSection(this.title, this.items);
}

const List<_TermSection> _sections = [
  _TermSection('1. Acceptance of Terms', [
    _TermItem(
      'By downloading, accessing, or using the FlexWell mobile application '
      '("the App"), you agree to be bound by these Terms and Conditions. If '
      'you do not agree with any part of these terms, you must immediately '
      'discontinue use of the App.',
    ),
  ]),
  _TermSection('2. Description of the Service', [
    _TermItem(
      'FlexWell is an AI-driven, mobile-based fitness application designed to '
      'analyze exercise posture in real time. The system utilizes your '
      "device's camera, Google ML Kit Pose Detection, and a K-Nearest "
      'Neighbors (KNN) machine learning algorithm to extract skeletal '
      'keypoints and classify your posture as "Correct" or "Incorrect." The '
      'App supports a specific catalog of exercises: Squat, Push-Up, Lunge, '
      'Plank, Pull-Up, and Side Plank. FlexWell also includes a repetition '
      'tracker, an offline video tutorial library, and a gamification system '
      '(badges and streaks) to encourage consistent engagement.',
    ),
  ]),
  _TermSection('3. Medical and Physical Risk Disclaimer', [
    _TermItem(
      'FlexWell is an automated software tool designed to provide '
      'supplementary corrective feedback based on predefined mathematical '
      'datasets. It does not replace the personalized guidance of a certified '
      'professional fitness trainer, physical therapist, or medical expert.',
      lead: 'Not a Replacement for Professionals: ',
    ),
    _TermItem(
      'Engaging in physical exercise carries an inherent risk of injury. By '
      'using FlexWell, you acknowledge that you are voluntarily participating '
      'in these activities and assume all risks associated with your '
      'workouts.',
      lead: 'Assumption of Risk: ',
    ),
    _TermItem(
      'While the App utilizes advanced pose estimation to flag deviations '
      'from standard biomechanical forms, it cannot account for individual '
      'musculoskeletal conditions, prior injuries, or unique anatomical '
      'variations.',
      lead: 'System Limitations: ',
    ),
  ]),
  _TermSection('4. Data Privacy, Camera Usage, and Security', [
    _TermItem(
      'FlexWell strictly complies with Republic Act No. 10173, also known as '
      'the Data Privacy Act of 2012 of the Philippines.',
    ),
    _TermItem(
      'The App requires access to your device\'s rear or front camera to '
      'function. The live video feed is processed locally on your device in '
      'real time to extract coordinate data (skeletal landmarks) via Google '
      'ML Kit.',
      lead: 'Camera Processing: ',
    ),
    _TermItem(
      'The App does not record, upload, or store live video feeds or personal '
      'images of your workouts. Only encrypted numerical data, such as '
      'session accuracy scores, repetition counts, session durations, and '
      'unlocked achievements, are synchronized to our secure Firebase Cloud '
      'Firestore backend.',
      lead: 'Data Storage: ',
    ),
    _TermItem(
      'Anonymized session data is accessible to authorized system '
      'administrators via a secure web dashboard strictly for the purpose of '
      'monitoring system performance and gamification engagement.',
      lead: 'Administrative Access: ',
    ),
  ]),
  _TermSection('5. User Responsibilities and System Requirements', [
    _TermItem(
      "To ensure the system functions as intended, you agree to adhere to the "
      "operational constraints outlined in the App's setup instructions:",
    ),
    _TermItem(
      'You must use the App in a well-lit environment, avoiding heavy '
      'backlighting. The device must be mounted stably (e.g., on a tripod or '
      'shelf) at the designated height and angle for the selected exercise.',
      lead: 'Environment: ',
    ),
    _TermItem(
      'Your full body must remain visible within the camera frame during '
      'active detection. You understand that wearing baggy or heavily '
      'layered clothing may obscure joint detection and degrade system '
      'accuracy.',
      lead: 'Visibility: ',
    ),
    _TermItem(
      'The underlying AI pose estimation model and the posture classification '
      'dataset were trained on standard anatomical silhouettes and typical '
      'biomechanical movements. Accuracy may therefore be reduced, key body '
      'landmarks may go undetected, or false "Incorrect" posture warnings may '
      'be produced for body types, physical proportions, or movement patterns '
      'that differ from those represented in the training data.',
      lead: 'Body Types and Movement Patterns: ',
    ),
  ]),
  _TermSection('6. Limitation of Liability', [
    _TermItem(
      'To the maximum extent permitted by applicable law, the developers of '
      'FlexWell (City College of Calamba, its students, and affiliates) shall '
      'not be held liable for any direct, indirect, incidental, or '
      'consequential damages, including but not limited to physical injury, '
      'muscle strain, or property damage arising from the use or inability to '
      'use the App, reliance on its corrective text prompts, or failure of '
      'the system to detect hazardous posture deviations.',
    ),
  ]),
  _TermSection('7. Data Retention and Termination of Use', [
    _TermItem(
      'You may terminate your use of the service at any time by uninstalling '
      'the FlexWell application from your mobile device. Please note that the '
      'application does not currently support a manual account deletion '
      'feature. Because the App syncs basic numerical session logs (such as '
      "scores and repetition counts) to evaluate the system's performance "
      'for academic research, previously synced anonymized data will remain '
      'in the secure Firebase database even after the application is '
      'uninstalled. We reserve the right to suspend or terminate access to '
      'the App at any time for violations of these Terms and Conditions.',
    ),
  ]),
  _TermSection('8. Modifications to the Terms', [
    _TermItem(
      'The developers reserve the right to update or modify these Terms and '
      'Conditions at any time. Continued use of the FlexWell application '
      'following any changes constitutes your acceptance of the revised '
      'terms.',
    ),
  ]),
  _TermSection('9. Governing Law and Contact', [
    _TermItem(
      'These Terms and Conditions shall be governed by and construed in '
      'accordance with the laws of the Republic of the Philippines.',
      lead: 'Governing Law: ',
    ),
    _TermItem(
      'For questions or concerns regarding these Terms, please contact the '
      'FlexWell development team at City College of Calamba.',
      lead: 'Contact: ',
    ),
  ]),
];

/// Shows the terms.
/// - [requireAcceptance] = true: first-launch gate with checkbox, Accept and
///   Decline buttons. Accepting opens the main app.
/// - [requireAcceptance] = false: read-only view (opened from Settings).
class TermsScreen extends StatefulWidget {
  final bool requireAcceptance;
  const TermsScreen({super.key, this.requireAcceptance = false});

  @override
  State<TermsScreen> createState() => _TermsScreenState();
}

class _TermsScreenState extends State<TermsScreen> {
  bool _agreed = false;
  bool _saving = false;

  Future<void> _accept() async {
    if (!_agreed || _saving) return;
    setState(() => _saving = true);
    await TermsService.accept();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      fadeRoute(const MainNavigationScreen()),
      (route) => false,
    );
  }

  void _decline() {
    // Closes the app on Android. iOS has no sanctioned way to quit, so the
    // user simply stays on this screen until they accept.
    SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final primaryText = scheme.onSurface;
    final secondaryText = scheme.onSurfaceVariant;
    final cardColor = scheme.surface;
    final borderColor = scheme.outlineVariant;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        automaticallyImplyLeading: !widget.requireAcceptance,
        title: const Text('Terms & Conditions'),
        iconTheme: IconThemeData(color: primaryText),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                children: [
                  Text(
                    'FlexWell Application Terms and Conditions',
                    style: TextStyle(
                      color: primaryText,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 12),
                  for (final section in _sections)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: borderColor),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.title,
                            style: TextStyle(
                              color: scheme.primary,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          for (final item in section.items)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text.rich(
                                TextSpan(
                                  children: [
                                    if (item.lead != null)
                                      TextSpan(
                                        text: item.lead,
                                        style: TextStyle(
                                          color: primaryText,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    TextSpan(text: item.text),
                                  ],
                                ),
                                style: TextStyle(
                                  color: secondaryText,
                                  fontSize: 14,
                                  height: 1.45,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (widget.requireAcceptance)
              Material(
                color: cardColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Divider(height: 1, color: borderColor),
                      CheckboxListTile(
                        value: _agreed,
                        onChanged: (v) => setState(() => _agreed = v ?? false),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        activeColor: AppColors.correct,
                        title: Text(
                          'I have read and agree to the Terms and Conditions.',
                          style: TextStyle(
                            color: primaryText,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Stacked full-width buttons: labels never wrap or clip on
                      // narrow screens or with large system font sizes.
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size.fromHeight(52),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 12),
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: scheme.surfaceContainerHighest,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _agreed && !_saving ? _accept : null,
                          child: _saving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'ACCEPT & CONTINUE',
                                    maxLines: 1,
                                    softWrap: false,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            side: BorderSide(
                              color: scheme.outline,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _decline,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              'DECLINE',
                              maxLines: 1,
                              softWrap: false,
                              style: TextStyle(
                                color: primaryText,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}