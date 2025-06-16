import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../screens/web_view_screen.dart';

class LinkifyText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final TextStyle? linkStyle;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool enableEmbeds;

  const LinkifyText({
    super.key,
    required this.text,
    this.style,
    this.linkStyle,
    this.maxLines,
    this.overflow,
    this.enableEmbeds = true,
  });

  @override
  Widget build(BuildContext context) {
    if (enableEmbeds) {
      return _buildWithEmbeds(context);
    } else {
      return _buildTextOnly(context);
    }
  }

  Widget _buildWithEmbeds(BuildContext context) {
    final urlRegex = RegExp(
      r'(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]+\.[^\s]{2,}|www\.[a-zA-Z0-9]+\.[^\s]{2,})',
      caseSensitive: false,
    );

    final matches = urlRegex.allMatches(text);
    if (matches.isEmpty) {
      return _buildTextOnly(context);
    }

    final widgets = <Widget>[];
    int lastIndex = 0;

    for (final match in matches) {
      // Add text before the URL
      if (match.start > lastIndex) {
        final textBefore = text.substring(lastIndex, match.start);
        if (textBefore.isNotEmpty) {
          widgets.add(_buildTextOnly(context, textBefore));
        }
      }

      // Add URL with potential embed
      final url = match.group(0)!;
      final embedWidget = _buildEmbedWidget(context, url);
      if (embedWidget != null) {
        widgets.add(embedWidget);
      } else {
        widgets.add(_buildLinkText(context, url));
      }

      lastIndex = match.end;
    }

    // Add remaining text after the last URL
    if (lastIndex < text.length) {
      final textAfter = text.substring(lastIndex);
      if (textAfter.isNotEmpty) {
        widgets.add(_buildTextOnly(context, textAfter));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widgets,
    );
  }

  Widget _buildTextOnly(BuildContext context, [String? customText]) {
    final textToUse = customText ?? text;
    final spans = _buildTextSpans(context, textToUse);
    
    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: overflow ?? TextOverflow.clip,
    );
  }
  List<TextSpan> _buildTextSpans(BuildContext context, [String? customText]) {
    final textToUse = customText ?? text;
    final spans = <TextSpan>[];
    
    // Regex to detect URLs
    final urlRegex = RegExp(
      r'(https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|www\.[a-zA-Z0-9][a-zA-Z0-9-]+[a-zA-Z0-9]\.[^\s]{2,}|https?:\/\/(?:www\.|(?!www))[a-zA-Z0-9]+\.[^\s]{2,}|www\.[a-zA-Z0-9]+\.[^\s]{2,})',
      caseSensitive: false,
    );

    final matches = urlRegex.allMatches(textToUse);
    int lastIndex = 0;

    for (final match in matches) {
      // Add text before the URL
      if (match.start > lastIndex) {
        spans.add(TextSpan(
          text: textToUse.substring(lastIndex, match.start),
          style: style,
        ));
      }

      // Add the URL as a clickable link
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: linkStyle ?? const TextStyle(
          color: Colors.blue,
          decoration: TextDecoration.underline,
        ),
        recognizer: TapGestureRecognizer()
          ..onTap = () => _launchUrl(url, context),
      ));

      lastIndex = match.end;
    }

    // Add remaining text after the last URL
    if (lastIndex < textToUse.length) {
      spans.add(TextSpan(
        text: textToUse.substring(lastIndex),
        style: style,
      ));
    }

    // If no URLs found, return the original text
    if (spans.isEmpty) {
      spans.add(TextSpan(text: textToUse, style: style));
    }

    return spans;
  }
  Future<void> _launchUrl(String url, [BuildContext? ctx]) async {
    // Add protocol if missing
    String fullUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      fullUrl = 'https://$url';
    }

    try {
      final uri = Uri.parse(fullUrl);
        // Use internal browser for http/https URLs
      if (uri.scheme == 'http' || uri.scheme == 'https') {
        Navigator.of(ctx!).push(
          MaterialPageRoute(
            builder: (context) => WebViewScreen(
              url: fullUrl,
              title: _getUrlTitle(fullUrl),
            ),
          ),
        );
        return;
      }
      
      // Use external launcher for other schemes (mailto, tel, etc.)
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  String _getUrlTitle(String url) {
    try {
      final uri = Uri.parse(url);
      final host = uri.host.toLowerCase();
      
      if (host.contains('youtube.com') || host.contains('youtu.be')) {
        return 'YouTube';
      } else if (host.contains('twitter.com') || host.contains('x.com')) {
        return 'Twitter/X';
      } else if (host.contains('instagram.com')) {
        return 'Instagram';
      } else if (host.contains('github.com')) {
        return 'GitHub';
      } else if (host.contains('linkedin.com')) {
        return 'LinkedIn';
      } else {
        return host.replaceAll('www.', '');
      }
    } catch (e) {
      return 'Web Page';
    }
  }

  Widget? _buildEmbedWidget(BuildContext context, String url) {
    // Normalize URL
    String fullUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      fullUrl = 'https://$url';
    }

    // YouTube embed
    if (_isYouTubeUrl(fullUrl)) {
      return _buildYouTubeEmbed(context, fullUrl);
    }

    // Twitter embed
    if (_isTweetUrl(fullUrl)) {
      return _buildTwitterEmbed(context, fullUrl);
    }

    // Image embed
    if (_isImageUrl(fullUrl)) {
      return _buildImageEmbed(context, fullUrl);
    }

    // For other links, return null to show as regular link
    return null;
  }
  Widget _buildLinkText(BuildContext context, String url) {
    return GestureDetector(
      onTap: () => _launchUrl(url, context),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.blue.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.blue.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Icon(
              Icons.link,
              color: Colors.blue,
              size: 16,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                url,
                style: linkStyle ?? const TextStyle(
                  color: Colors.blue,
                  decoration: TextDecoration.underline,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              Icons.open_in_new,
              color: Colors.blue,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildYouTubeEmbed(BuildContext context, String url) {
    final videoId = _extractYouTubeVideoId(url);
    if (videoId == null) return _buildLinkText(context, url);

    final thumbnailUrl = 'https://img.youtube.com/vi/$videoId/maxresdefault.jpg';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [            GestureDetector(
              onTap: () => _launchUrl(url, context),
              child: Stack(
                children: [
                  CachedNetworkImage(
                    imageUrl: thumbnailUrl,
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      height: 200,
                      color: Colors.grey[300],
                      child: const Center(
                        child: CircularProgressIndicator(),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      height: 200,
                      color: Colors.grey[300],
                      child: const Icon(Icons.error),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withOpacity(0.3),
                      child: const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Colors.white,
                          size: 64,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: Colors.white,
              child: Row(
                children: [
                  Image.asset(
                    'assets/youtube_icon.png', // You'll need to add this asset
                    width: 20,
                    height: 20,
                    errorBuilder: (context, error, stackTrace) => const Icon(
                      Icons.video_library,
                      color: Colors.red,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'YouTube Video',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  Icon(
                    Icons.open_in_new,
                    color: Colors.grey[600],
                    size: 16,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTwitterEmbed(BuildContext context, String url) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
      ),      child: GestureDetector(
        onTap: () => _launchUrl(url, context),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.blue,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.alternate_email,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Twitter/X Post',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    url,
                    style: TextStyle(
                      color: Colors.blue,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Icon(
              Icons.open_in_new,
              color: Colors.grey[600],
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageEmbed(BuildContext context, String url) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),      child: GestureDetector(
        onTap: () => _launchUrl(url, context),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: CachedNetworkImage(
            imageUrl: url,
            width: double.infinity,
            fit: BoxFit.cover,
            placeholder: (context, url) => Container(
              height: 200,
              color: Colors.grey[300],
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
            errorWidget: (context, url, error) => _buildLinkText(context, url),
          ),
        ),
      ),
    );
  }

  bool _isYouTubeUrl(String url) {
    return url.contains('youtube.com/watch') || 
           url.contains('youtu.be/') || 
           url.contains('youtube.com/embed/');
  }

  bool _isTweetUrl(String url) {
    return url.contains('twitter.com/') && url.contains('/status/') ||
           url.contains('x.com/') && url.contains('/status/');
  }

  bool _isImageUrl(String url) {
    return url.toLowerCase().endsWith('.jpg') ||
           url.toLowerCase().endsWith('.jpeg') ||
           url.toLowerCase().endsWith('.png') ||
           url.toLowerCase().endsWith('.gif') ||
           url.toLowerCase().endsWith('.webp');
  }

  String? _extractYouTubeVideoId(String url) {
    final regExp = RegExp(
      r'(?:youtube\.com\/watch\?v=|youtu\.be\/|youtube\.com\/embed\/)([a-zA-Z0-9_-]{11})',
      caseSensitive: false,
    );
    final match = regExp.firstMatch(url);
    return match?.group(1);
  }
}
