import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

class NativeAdWidget extends StatefulWidget {
  final NativeAd ad;

  const NativeAdWidget({super.key, required this.ad});

  @override
  State<NativeAdWidget> createState() => _NativeAdWidgetState();
}

class _NativeAdWidgetState extends State<NativeAdWidget> {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Sponsored Advertisement',
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.ad_units, color: Theme.of(context).primaryColor, size: 24),
                  const SizedBox(width: 8),
                  Text(
                    'Sponsored',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Render the styled native ad template
              SizedBox(
                height: 120, // Adjust for small template
                child: AdWidget(ad: widget.ad),
              ),
              // Fallback for custom fields if template doesn't render them
              if (widget.ad.responseInfo?.responseExtras != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.ad.responseInfo!.responseExtras['headline']?.toString() ?? 'Advertisement',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.ad.responseInfo!.responseExtras['body']?.toString() ?? '',
                  style: GoogleFonts.poppins(
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.ad.responseInfo!.responseExtras['call_to_action'] != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton(
                      onPressed: () {
                        // Handle CTA click
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6200),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        widget.ad.responseInfo!.responseExtras['call_to_action'].toString(),
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}