import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:padue/core/firestore_service.dart';
import 'package:padue/core/services_cache.dart';

class ProviderServicesOnboardingScreen extends StatefulWidget {
  final String userId;
  const ProviderServicesOnboardingScreen({super.key, required this.userId});

  @override
  State<ProviderServicesOnboardingScreen> createState() => _ProviderServicesOnboardingScreenState();
}

class _ProviderServicesOnboardingScreenState extends State<ProviderServicesOnboardingScreen> {
  List<String> _selectedServices = [];

  @override
  void initState() {
    super.initState();
    ServicesCache.load();
  }

  Future<void> _saveServices() async {
    await FirestoreService().updateProviderProfile(widget.userId, {
      'servicesOffered': _selectedServices,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Services Offered', style: GoogleFonts.poppins()),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What services do you offer?',
              style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'This helps us match you with the right jobs. You can change this anytime in your profile.',
              style: TextStyle(color: Colors.grey, fontSize: 15),
            ),
            const SizedBox(height: 32),

            ElevatedButton.icon(
              onPressed: () async {
                final result = await showModalBottomSheet<List<String>?>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => _ServicePickerSheet(
                    services: ServicesCache.services,
                    selected: _selectedServices,
                  ),
                );
                if (result != null) {
                  setState(() => _selectedServices = result);
                }
              },
              icon: const Icon(Icons.add),
              label: Text(
                _selectedServices.isEmpty
                    ? 'Select Services'
                    : '${_selectedServices.length} selected',
              ),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),

            if (_selectedServices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _selectedServices
                      .map((s) => Chip(
                            label: Text(s),
                            backgroundColor: Colors.orange.shade50,
                          ))
                      .toList(),
                ),
              ),

            const Spacer(),

            ElevatedButton(
              onPressed: () async {
                if (_selectedServices.isEmpty) {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text("Skip for now?"),
                      content: const Text(
                        "You need to add services to start receiving matches.\n\n"
                        "You can add them later in your profile.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                } else {
                  await _saveServices();
                }

                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/provider_dashboard');
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Continue to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== SERVICE PICKER SHEET ====================
class _ServicePickerSheet extends StatefulWidget {
  final List<String> services;
  final List<String> selected;

  const _ServicePickerSheet({
    super.key,
    required this.services,
    required this.selected,
  });

  @override
  State<_ServicePickerSheet> createState() => _ServicePickerSheetState();
}

class _ServicePickerSheetState extends State<_ServicePickerSheet> {
  late List<String> _tempSelected;

  @override
  void initState() {
    super.initState();
    _tempSelected = List.from(widget.selected);
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Select Services',
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, _tempSelected),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: widget.services.length,
                itemBuilder: (context, i) {
                  final service = widget.services[i];
                  return CheckboxListTile(
                    title: Text(service),
                    value: _tempSelected.contains(service),
                    activeColor: Colors.orange,
                    onChanged: (v) {
                      setState(() {
                        if (v == true) {
                          _tempSelected.add(service);
                        } else {
                          _tempSelected.remove(service);
                        }
                      });
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}