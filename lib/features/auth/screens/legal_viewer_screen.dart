import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class LegalViewerScreen extends StatelessWidget {
  final String title;
  final String content;

  const LegalViewerScreen({
    super.key,
    required this.title,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title, style: GoogleFonts.poppins()),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(
          content,
          style: GoogleFonts.poppins(fontSize: 15, height: 1.6),
        ),
      ),
    );
  }
}