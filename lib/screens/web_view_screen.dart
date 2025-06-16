import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class WebViewScreen extends StatefulWidget {
  final String url;
  final String? title;

  const WebViewScreen({
    super.key,
    required this.url,
    this.title,
  });

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  String _pageTitle = '';
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    _currentUrl = widget.url;
    _pageTitle = widget.title ?? _getDomainFromUrl(widget.url);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.close,
            color: Color(0xFF2F3437),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _pageTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2F3437),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              _getDomainFromUrl(_currentUrl),
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9B9A97),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) async {
              switch (value) {
                case 'open_external':
                  await _launchUrlExternally(_currentUrl);
                  break;
                case 'copy_url':
                  await _copyUrlToClipboard(_currentUrl);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'open_external',
                child: Row(
                  children: [
                    Icon(Icons.open_in_new, size: 18),
                    SizedBox(width: 8),
                    Text('Open in Browser'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'copy_url',
                child: Row(
                  children: [
                    Icon(Icons.copy, size: 18),
                    SizedBox(width: 8),
                    Text('Copy URL'),
                  ],
                ),
              ),
            ],
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(8),
              child: const Icon(
                Icons.more_vert,
                color: Color(0xFF2F3437),
              ),
            ),
          ),
        ],
      ),
      body: Container(
        color: Colors.white,
        child: Column(
          children: [
            // URL bar
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFFF7F6F3),
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE1E1E0), width: 1),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock,
                    color: Color(0xFF00B386),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentUrl,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF2F3437),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            // Main content
            Expanded(
              child: Container(
                color: Colors.white,
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2F3437).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(60),
                        ),
                        child: const Icon(
                          Icons.language,
                          size: 48,
                          color: Color(0xFF2F3437),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        _pageTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2F3437),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _getDomainFromUrl(_currentUrl),
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9B9A97),
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),                      ElevatedButton.icon(
                        onPressed: () async {
                          print('DEBUG: Attempting to launch URL: $_currentUrl');
                          await _launchUrlExternally(_currentUrl);
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: const Text('Open in Browser'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2F3437),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextButton.icon(
                        onPressed: () => _copyUrlToClipboard(_currentUrl),
                        icon: const Icon(Icons.copy),
                        label: const Text('Copy URL'),
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFF2F3437),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getDomainFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }  Future<void> _launchUrlExternally(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      print('DEBUG: Checking if can launch URL: $url');
      
      final canLaunch = await canLaunchUrl(uri);
      print('DEBUG: Can launch URL: $canLaunch');
      
      if (canLaunch) {
        print('DEBUG: Launching with external application mode');
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        print('DEBUG: Successfully launched URL');
      } else {
        print('DEBUG: Cannot launch with external app, trying platform default');
        await launchUrl(uri, mode: LaunchMode.platformDefault);
        print('DEBUG: Successfully launched URL with platform default');
      }
    } catch (e) {
      print('DEBUG: Error launching URL: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Could not open URL in external browser'),
                const SizedBox(height: 4),
                Text('Error: $e', style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        _copyUrlToClipboard(url);
                      },
                      child: const Text('Copy URL'),
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _copyUrlToClipboard(String url) async {
    try {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('URL copied to clipboard'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not copy URL: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
