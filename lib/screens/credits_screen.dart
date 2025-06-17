import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class CreditsScreen extends StatelessWidget {
  const CreditsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6F3),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Color(0xFF2F3437)),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'About',
          style: TextStyle(
            color: Color(0xFF2F3437),
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Section
            _buildHeroSection(),
            const SizedBox(height: 40),
            
            // App Info
            _buildAppSection(),
            const SizedBox(height: 40),
            
            // Creator Info
            _buildCreatorSection(context),
            const SizedBox(height: 40),
            
            // Tech Stack
            _buildTechSection(),
            const SizedBox(height: 40),
            
            // Social Links
            _buildSocialSection(),
            const SizedBox(height: 40),
            
            // Footer
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroSection() {    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE1E1E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.security_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 16),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [                    Text(
                      'Secrecy',
                      style: TextStyle(
                        color: Color(0xFF2F3437),
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Secure & Private Communication',
                      style: TextStyle(
                        color: Color(0xFF6B6B6B),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),          const Text(
            'A modern messaging app built with Flutter, featuring end-to-end encryption, voice & video calls, and a beautiful Notion-inspired interface.',
            style: TextStyle(
              color: Color(0xFF6B6B6B),
              fontSize: 16,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [        const Text(
          '📱 App Features',
          style: TextStyle(
            color: Color(0xFF2F3437),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        _buildFeatureCard('🔒', 'End-to-End Encryption', 'Your messages are secured with industry-standard encryption'),
        _buildFeatureCard('📞', 'Voice & Video Calls', 'Crystal clear calls with WebRTC technology'),
        _buildFeatureCard('☀️', 'Light Mode', 'Beautiful light interface designed for comfort'),
        _buildFeatureCard('📱', 'Cross Platform', 'Available on Android, iOS, and Web'),
      ],
    );
  }  Widget _buildFeatureCard(String emoji, String title, String description) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E1E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF2F3437),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF6B6B6B),
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatorSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [        const Text(
          '👨‍💻 Creator',
          style: TextStyle(
            color: Color(0xFF2F3437),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE1E1E0)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF10B981), Color(0xFF059669)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: const Center(
                      child: Text(
                        'H',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [                        Text(
                          'Harshit Singh',
                          style: TextStyle(
                            color: Color(0xFF2F3437),
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Full Stack Developer',
                          style: TextStyle(
                            color: Color(0xFF6B6B6B),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),              const Text(
                'Passionate developer with expertise in Flutter, React, Node.js, and modern web technologies. I love building beautiful, functional applications that solve real problems.',
                style: TextStyle(
                  color: Color(0xFF6B6B6B),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () => _launchURL('https://leoncyriac.me'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF6366F1).withOpacity(0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.language,
                        color: Color(0xFF6366F1),
                        size: 16,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Visit Portfolio',
                        style: TextStyle(
                          color: Color(0xFF6366F1),
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTechSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [        const Text(
          '⚡ Tech Stack',
          style: TextStyle(
            color: Color(0xFF2F3437),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildTechChip('Flutter', Colors.blue),
            _buildTechChip('Dart', Colors.cyan),
            _buildTechChip('Firebase', Colors.orange),
            _buildTechChip('WebRTC', Colors.green),
            _buildTechChip('Node.js', Colors.lightGreen),
            _buildTechChip('TypeScript', Colors.indigo),
          ],
        ),
      ],
    );
  }

  Widget _buildTechChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildSocialSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [        const Text(
          '🔗 Connect',
          style: TextStyle(
            color: Color(0xFF2F3437),
            fontSize: 20,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [            _buildSocialButton(
              icon: Icons.code,
              label: 'GitHub',
              url: 'https://github.com/harshitSingh9030',
              color: const Color(0xFF2F3437),
            ),
            const SizedBox(width: 12),
            _buildSocialButton(
              icon: Icons.alternate_email,
              label: 'Twitter',
              url: 'https://twitter.com/OhHarshit',
              color: const Color(0xFF1DA1F2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildSocialButton(
          icon: Icons.email,
          label: 'Email',
          url: 'mailto:harshitSingh9030@gmail.com',
          color: const Color(0xFFEA4335),
          fullWidth: true,
        ),
      ],
    );
  }
  Widget _buildSocialButton({
    required IconData icon,
    required String label,
    required String url,
    required Color color,
    bool fullWidth = false,
  }) {
    Widget buttonContent = GestureDetector(
      onTap: () => _launchURL(url),
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );

    return fullWidth ? buttonContent : Flexible(child: buttonContent);
  }
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E1E0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            '✨ Thank you for using Secrecy!',
            style: TextStyle(
              color: Colors.black,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Built with ❤️ using Flutter',
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),          Text(
            '© ${DateTime.now().year} Harshit Singh',
            style: TextStyle(
              color: Colors.black.withOpacity(0.4),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _launchURL(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      // Handle error silently or show a snackbar
      debugPrint('Could not launch $url: $e');
    }
  }
}
