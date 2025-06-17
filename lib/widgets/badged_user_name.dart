import 'package:flutter/material.dart';
import '../utils/owner_utils.dart';

class BadgedUserName extends StatelessWidget {
  final String senderName;
  final String senderEmail;
  final TextStyle style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;

  const BadgedUserName({
    super.key,
    required this.senderName,
    required this.senderEmail,
    required this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = OwnerUtils.getDisplayNameWithBadge(senderName, senderEmail);
    final tooltip = OwnerUtils.getSpecialUserTooltip(senderEmail);
    
    // If there's a tooltip, wrap in Tooltip widget
    if (tooltip.isNotEmpty) {
      return Tooltip(
        message: tooltip,
        decoration: BoxDecoration(
          color: Colors.black87,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onLongPress: () {
            // Show a snackbar on long press for mobile
            if (tooltip.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(tooltip),
                  duration: const Duration(seconds: 2),
                  backgroundColor: Colors.black87,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  behavior: SnackBarBehavior.floating,
                  margin: const EdgeInsets.all(16),
                ),
              );
            }
          },
          child: Text(
            displayName,
            style: style,
            textAlign: textAlign,
            overflow: overflow,
            maxLines: maxLines,
          ),
        ),
      );
    }
    
    // If no tooltip, just return regular text
    return Text(
      displayName,
      style: style,
      textAlign: textAlign,
      overflow: overflow,
      maxLines: maxLines,
    );
  }
}