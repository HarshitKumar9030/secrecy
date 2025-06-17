import 'package:flutter/material.dart';

class UploadProgressWidget extends StatelessWidget {
  final double progress;
  final String fileName;
  final VoidCallback? onCancel;
  final bool isCompleted;
  final bool isError;
  final String? errorMessage;

  const UploadProgressWidget({
    super.key,
    required this.progress,
    required this.fileName,
    this.onCancel,
    this.isCompleted = false,
    this.isError = false,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isError 
              ? const Color(0xFFE03E3E).withOpacity(0.3)
              : const Color(0xFFE1E1E0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              // File icon
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isError 
                      ? const Color(0xFFE03E3E).withOpacity(0.1)
                      : isCompleted 
                          ? const Color(0xFF0F8B0F).withOpacity(0.1)
                          : const Color(0xFF0B6BCB).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  isError
                      ? Icons.error_outline
                      : isCompleted
                          ? Icons.check
                          : _getFileIcon(fileName),
                  size: 16,
                  color: isError 
                      ? const Color(0xFFE03E3E)
                      : isCompleted 
                          ? const Color(0xFF0F8B0F)
                          : const Color(0xFF0B6BCB),
                ),
              ),
              
              const SizedBox(width: 12),
              
              // File info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF37352F),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isError 
                          ? (errorMessage ?? 'Upload failed')
                          : isCompleted 
                              ? 'Upload complete'
                              : 'Uploading... ${(progress * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 12,
                        color: isError 
                            ? const Color(0xFFE03E3E)
                            : isCompleted 
                                ? const Color(0xFF0F8B0F)
                                : const Color(0xFF787774),
                      ),
                    ),
                  ],
                ),
              ),
              
              // Cancel button
              if (!isCompleted && !isError && onCancel != null)
                IconButton(
                  onPressed: onCancel,
                  icon: const Icon(
                    Icons.close,
                    size: 16,
                    color: Color(0xFF9B9A97),
                  ),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
            ],
          ),
          
          if (!isCompleted && !isError) ...[
            const SizedBox(height: 8),
            
            // Progress bar
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F1EF),
                borderRadius: BorderRadius.circular(2),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF0B6BCB),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final extension = fileName.split('.').last.toLowerCase();
    
    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'mov':
      case 'avi':
      case 'mkv':
        return Icons.videocam;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc':
      case 'docx':
        return Icons.description;
      case 'mp3':
      case 'wav':
      case 'aac':
        return Icons.audiotrack;
      default:
        return Icons.insert_drive_file;
    }
  }
}
