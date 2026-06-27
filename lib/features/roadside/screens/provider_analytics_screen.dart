// provider_analytics_screen.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

class ProviderAnalyticsScreen extends StatelessWidget {
  const ProviderAnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final providerId = FirebaseAuth.instance.currentUser!.uid;
    return Scaffold(
      appBar: AppBar(
        title: Text('Analytics Dashboard', style: GoogleFonts.poppins()),
        backgroundColor: const Color(0xFF26A69A),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Requests Over Time',
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildRequestChart(providerId),
            const SizedBox(height: 32),
            Text(
              'Service Type Distribution',
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildServiceTypeChart(providerId),
          ],
        ),
      ),
    );
  }

  Widget _buildRequestChart(String providerId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('providerId', isEqualTo: providerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final requests = snapshot.data!.docs;
        // Aggregate by month (simplified)
        final Map<String, int> monthlyCounts = {};
        for (var doc in requests) {
          final timestamp = (doc['createdAt'] as Timestamp).toDate();
          final monthKey = '${timestamp.year}-${timestamp.month}';
          monthlyCounts[monthKey] = (monthlyCounts[monthKey] ?? 0) + 1;
        }
     final spots = monthlyCounts.entries.toList().asMap().entries.map((e) {
        return FlSpot(e.key.toDouble(), e.value.value.toDouble());
      }).toList();

        return Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF26A69A).withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(16),
          child: LineChart(
            LineChartData(
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: const Color(0xFF26A69A),
                  dotData: const FlDotData(show: false),
                ),
              ],
              titlesData: const FlTitlesData(show: false),
              borderData: FlBorderData(show: false),
            ),
          ),
        ).animate().fadeIn();
      },
    );
  }

  Widget _buildServiceTypeChart(String providerId) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('requests')
          .where('providerId', isEqualTo: providerId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final requests = snapshot.data!.docs;
        final Map<String, int> serviceCounts = {};
        for (var doc in requests) {
          final serviceType = doc['service'] as String? ?? 'Unknown';
          serviceCounts[serviceType] = (serviceCounts[serviceType] ?? 0) + 1;
        }
       final pieSections = serviceCounts.entries
          .toList() // Convert Iterable to List
          .asMap()
          .entries
          .map((e) => PieChartSectionData(
                value: e.value.value.toDouble(),
                color: Colors.primaries[e.key % Colors.primaries.length],
                title: e.value.key,
                radius: 100,
                titleStyle: GoogleFonts.poppins(fontSize: 12, color: Colors.white),
              ))
          .toList();

        return Container(
          height: 200,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF26A69A).withOpacity(0.2)),
          ),
          padding: const EdgeInsets.all(16),
          child: PieChart(
            PieChartData(
              sections: pieSections,
              sectionsSpace: 2,
              centerSpaceRadius: 40,
            ),
          ),
        ).animate().fadeIn();
      },
    );
  }
}

