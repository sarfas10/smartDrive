import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'ui_common.dart';
import 'package:smart_drive/reusables/vehicle_icons.dart'; // ⬅️ icon mapping lives here

class SettingsBlock extends StatelessWidget {
  const SettingsBlock({super.key});

  @override
  Widget build(BuildContext context) {
    final doc = FirebaseFirestore.instance.collection('settings').doc('system');
    final radiusCtrl = TextEditingController();
    final perKmCtrl = TextEditingController();
    final policyCtrl = TextEditingController();

    return Container(
      color: Colors.white,
      child: StreamBuilder<DocumentSnapshot>(
        stream: doc.snapshots(),
        builder: (context, snap) {
          final m = (snap.data?.data() as Map?) ?? {};
          radiusCtrl.text = (m['free_radius_km'] ?? 5).toString();
          perKmCtrl.text = (m['surcharge_per_km'] ?? 10).toString();
          policyCtrl.text = (m['cancellation_policy'] ?? 'Cancellations within 24 hours incur 20% fee.').toString();

          return ListView(
            padding: const EdgeInsets.all(16.0),
            children: [
              // Vehicle Management Section
              Container(
                padding: const EdgeInsets.all(16.0),
                margin: const EdgeInsets.only(bottom: 20.0),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Vehicle Management',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _showAddVehicleDialog(context),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Vehicle'),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Display existing vehicles (from 'vehicles' collection)
                    StreamBuilder<QuerySnapshot>(
                      stream: FirebaseFirestore.instance
                          .collection('vehicles')
                          .orderBy('created_at', descending: true)
                          .snapshots(),
                      builder: (context, vehicleSnap) {
                        if (!vehicleSnap.hasData || vehicleSnap.data!.docs.isEmpty) {
                          return Container(
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              border: Border.all(color: Colors.grey[200]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Center(
                              child: Text(
                                'No vehicles added yet. Click "Add Vehicle" to get started.',
                                style: TextStyle(color: Colors.grey),
                              ),
                            ),
                          );
                        }

                        return Column(
                          children: vehicleSnap.data!.docs.map((vehicleDoc) {
                            final data = vehicleDoc.data() as Map<String, dynamic>;
                            final carType = (data['car_type'] ?? 'Unknown Vehicle').toString();
                            final charge = (data['vehicle_charge'] ?? 0);
                            final icon = VehicleIcons.forType(carType);

                            return Container(
                              margin: const EdgeInsets.only(bottom: 12),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                border: Border.all(color: Colors.grey[200]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: Colors.blue[50],
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Icon(icon, color: Colors.blue[600], size: 28),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          carType,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '₹${charge.toString()} per session',
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                                    onPressed: () async {
                                      await vehicleDoc.reference.delete();
                                    },
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),

              // Payment Settings Section
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Payment Settings',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 16),
                    field('Free Radius (km)', radiusCtrl, number: true),
                    const SizedBox(height: 8),
                    field('Surcharge per km (₹)', perKmCtrl, number: true),
                    const SizedBox(height: 8),
                    area('Cancellation Policy', policyCtrl),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () async {
                          await doc.set({
                            'free_radius_km': double.tryParse(radiusCtrl.text.trim()) ?? 5,
                            'surcharge_per_km': double.tryParse(perKmCtrl.text.trim()) ?? 10,
                            'cancellation_policy': policyCtrl.text.trim(),
                            'updated_at': FieldValue.serverTimestamp(),
                          }, SetOptions(merge: true));
                        },
                        child: const Text('Save Payment Settings'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showAddVehicleDialog(BuildContext context) {
    // No icon here; we resolve icon by car_type via VehicleIcons.forType()
    final predefinedVehicles = [
      {'type': 'Manual Sedan', 'description': 'Standard transmission', 'defaultFee': 500},
      {'type': 'Automatic Sedan', 'description': 'Automatic transmission', 'defaultFee': 600},
      {'type': 'Manual Hatchback', 'description': 'Compact car with manual transmission', 'defaultFee': 450},
      {'type': 'Automatic Hatchback', 'description': 'Compact car with automatic transmission', 'defaultFee': 550},
      {'type': 'Manual SUV', 'description': 'Sports utility vehicle', 'defaultFee': 700},
      {'type': 'Automatic SUV', 'description': 'Sports utility vehicle', 'defaultFee': 800},
      {'type': 'Motorcycle', 'description': 'Two wheeler vehicle', 'defaultFee': 300},
      {'type': 'Scooter', 'description': 'Automatic two wheeler', 'defaultFee': 250},
    ];

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            height: MediaQuery.of(context).size.height * 0.7,
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Add Vehicle Type',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Select a vehicle type to add:',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                const SizedBox(height: 16),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: predefinedVehicles.length,
                    itemBuilder: (context, index) {
                      final vehicle = predefinedVehicles[index];
                      final carType = vehicle['type'] as String;
                      final icon = VehicleIcons.forType(carType);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: InkWell(
                          onTap: () => _showFeeDialog(context, vehicle),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: Colors.blue[50],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(icon, color: Colors.blue[600], size: 28),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        carType,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        vehicle['description'] as String,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(Icons.arrow_forward_ios, color: Colors.grey[400], size: 16),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFeeDialog(BuildContext context, Map<String, dynamic> vehicle) {
    final feeController = TextEditingController(text: vehicle['defaultFee'].toString());

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Set Fee for ${vehicle['type']}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: feeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Fee (₹)',
                  border: OutlineInputBorder(),
                  prefixText: '₹',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final fee = double.tryParse(feeController.text.trim()) ?? vehicle['defaultFee'];
                final carType = vehicle['type'] as String;

                // Write to 'vehicles' collection with our new schema
                final col = FirebaseFirestore.instance.collection('vehicles');
                final docRef = col.doc();
                await docRef.set({
                  'vehicle_id': docRef.id,
                  'car_type': carType,
                  'vehicle_charge': fee,
                  'created_at': FieldValue.serverTimestamp(),
                });

                Navigator.of(context).pop(); // Close fee dialog
                Navigator.of(context).pop(); // Close vehicle selection dialog
              },
              child: const Text('Add Vehicle'),
            ),
          ],
        );
      },
    );
  }
}
