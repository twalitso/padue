import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/features/roadside/models/provider.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:ui';

class ProviderProfilePreviewScreen extends StatelessWidget {
  final Provider provider;

  const ProviderProfilePreviewScreen({required this.provider, super.key});

  Widget _buildSocialMediaLink(String url) {
    return ListTile(
      leading: Icon(Icons.link, color: Color(0xFF26A69A)),
      title: Text(url, style: GoogleFonts.poppins(), overflow: TextOverflow.ellipsis),
      onTap: () {}, // Disabled for preview
    );
  }

  Widget _buildReviewsSection() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('provider_reviews')
          .where('providerId', isEqualTo: provider.id)
          .orderBy('timestamp', descending: true)
          .limit(5)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator(color: Color(0xFF26A69A));
        var reviews = snapshot.data!.docs;
        return Container(
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Color(0xFF26A69A).withOpacity(0.2)),
          ),
          padding: EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recent Reviews', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
              if (reviews.isEmpty)
                Text('No reviews yet', style: GoogleFonts.poppins(color: Colors.grey)),
              ...reviews.map((doc) {
                var data = doc.data() as Map<String, dynamic>;
                final timestamp = (data['timestamp'] as Timestamp?)?.toDate();
                final timeAgo = timestamp != null ? timeago.format(timestamp) : 'Just now';
                return ListTile(
                  leading: Icon(Icons.star, color: Colors.amber),
                  title: Text(data['review'] ?? 'No comment', style: GoogleFonts.poppins()),
                  subtitle: Text('Rating: ${data['rating']} • $timeAgo', style: GoogleFonts.poppins(color: Colors.grey)),
                ).animate().fadeIn(duration: Duration(milliseconds: 400));
              }),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('${provider.name}’s Profile', style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1E3A8A), Color(0xFF7C3AED)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFE6F0FA), Color(0xFFF3E8FF)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Color(0xFF26A69A).withOpacity(0.2)),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: CircleAvatar(
                          radius: 50,
                          backgroundImage: provider.profilePicUrl != null
                              ? NetworkImage(provider.profilePicUrl!)
                              : const AssetImage('assets/default_profile.png'),
                        ).animate().scale(duration: Duration(milliseconds: 800)),
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Text(
                          provider.name,
                          style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              provider.rating != null ? provider.rating!.toStringAsFixed(1) : 'No ratings yet',
                              style: GoogleFonts.poppins(fontSize: 16, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (provider.description != null)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('About', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text(
                              provider.description!,
                              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[800]),
                            ),
                          ],
                        ).animate().fadeIn(duration: Duration(milliseconds: 400)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.build, color: Color(0xFF26A69A), size: 20),
                          const SizedBox(width: 8),
                          Text('Service Type: ${provider.type}', style: GoogleFonts.poppins(fontSize: 16)),
                        ],
                      ).animate().fadeIn(duration: Duration(milliseconds: 400)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Icon(provider.isVerified ? Icons.verified : Icons.verified_user_outlined,
                              color: provider.isVerified ? Colors.green : Colors.grey, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Verification: ${provider.isVerified ? "Verified" : "Unverified"}',
                            style: GoogleFonts.poppins(fontSize: 16),
                          ),
                        ],
                      ).animate().fadeIn(duration: Duration(milliseconds: 400)),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.location_on, color: Color(0xFF26A69A), size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Location: ${provider.address ?? "Unknown"}',
                              style: GoogleFonts.poppins(fontSize: 16),
                            ),
                          ),
                        ],
                      ).animate().fadeIn(duration: Duration(milliseconds: 400)),
                      const SizedBox(height: 12),
                      if (provider.operatingHours != null && provider.operatingHours!.isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Operating Hours', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                            ...provider.operatingHours!.entries.map((entry) => ListTile(
                                  title: Text(entry.key, style: GoogleFonts.poppins()),
                                  subtitle: Text(entry.value, style: GoogleFonts.poppins(color: Colors.grey)),
                                )),
                          ],
                        ).animate().fadeIn(duration: Duration(milliseconds: 400)),
                      const SizedBox(height: 12),
                      Text('Services Offered', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                      if (provider.servicesOffered.isEmpty)
                        Text('No services listed', style: GoogleFonts.poppins(color: Colors.grey))
                      else
                        Wrap(
                          spacing: 8,
                          children: provider.servicesOffered.map((service) => Chip(
                                label: Text(service, style: GoogleFonts.poppins()),
                                backgroundColor: Color(0xFF26A69A).withOpacity(0.1),
                              )).toList(),
                        ).animate().fadeIn(duration: Duration(milliseconds: 400)),
                      const SizedBox(height: 12),
                      if (provider.website != null || (provider.socialMediaLinks != null && provider.socialMediaLinks!.isNotEmpty))
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Links', style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.bold)),
                            if (provider.website != null) _buildSocialMediaLink(provider.website!),
                            if (provider.socialMediaLinks != null)
                              ...provider.socialMediaLinks!.map((link) => _buildSocialMediaLink(link)),
                          ],
                        ).animate().fadeIn(duration: Duration(milliseconds: 400)),
                      const SizedBox(height: 16),
                      _buildReviewsSection(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}