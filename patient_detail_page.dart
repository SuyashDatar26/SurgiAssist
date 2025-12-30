import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

class PatientDetailPage extends StatefulWidget {
  final String patientId;

  const PatientDetailPage({Key? key, required this.patientId}) : super(key: key);

  @override
  State<PatientDetailPage> createState() => _PatientDetailPageState();
}

class _PatientDetailPageState extends State<PatientDetailPage> {
  String? doctorName;

  Future<DocumentSnapshot> _fetchPatientDetails() async {
    return await FirebaseFirestore.instance
        .collection('patients')
        .doc(widget.patientId)
        .get();
  }

  Future<void> _fetchDoctorName(String doctorId) async {
    try {
      final docSnapshot =
      await FirebaseFirestore.instance.collection('users').doc(doctorId).get();
      if (docSnapshot.exists) {
        final data = docSnapshot.data() as Map<String, dynamic>;
        setState(() {
          doctorName = data['name'] ?? 'Unknown Doctor';
        });
      } else {
        setState(() {
          doctorName = 'Doctor Not Found';
        });
      }
    } catch (e) {
      setState(() {
        doctorName = 'Error fetching doctor';
      });
    }
  }

  void _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      throw 'Could not open document: $url';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        title: const Text("Patient Details"),
        backgroundColor: Colors.transparent,
        centerTitle: true,
        elevation: 0,
      ),
      body: FutureBuilder<DocumentSnapshot>(
        future: _fetchPatientDetails(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: Text(
                "Patient not found.",
                style: TextStyle(color: Colors.white),
              ),
            );
          }

          final data = snapshot.data!.data() as Map<String, dynamic>;

          final name = data['name'] ?? 'N/A';
          final age = (data['age'] ?? 'N/A').toString();
          final gender = data['gender'] ?? 'N/A';
          final phone = data['phone'] ?? 'N/A';
          final email = data['email'] ?? 'N/A';
          final patientId = data['patientId'] ?? 'N/A';
          final assignedDoctorId = data['assignedDoctor'] ?? '';
          final createdAt = data['createdAt'] != null
              ? DateFormat('MMM d, yyyy • hh:mm a')
              .format((data['createdAt'] as Timestamp).toDate())
              : 'N/A';
          final List documents = List.from(data['documents'] ?? []);

          if (doctorName == null && assignedDoctorId.isNotEmpty) {
            _fetchDoctorName(assignedDoctorId);
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Card(
                  elevation: 8,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF203A43), Color(0xFF2C5364)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          "Patient ID: $patientId",
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text("Age: $age",
                                style: const TextStyle(color: Colors.white70)),
                            Text("Gender: $gender",
                                style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                _buildInfoTile("Phone", phone),
                _buildInfoTile("Email", email),
                _buildInfoTile("Record Created", createdAt),

                const SizedBox(height: 20),

                // Assigned Doctor Section
                const Text(
                  "Assigned Doctor",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.tealAccent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.tealAccent, width: 0.8),
                  ),
                  child: Text(
                    doctorName ?? "Loading doctor name...",
                    style: const TextStyle(fontSize: 16, color: Colors.white),
                  ),
                ),

                const SizedBox(height: 20),

                // Documents Section
                const Text(
                  "Documents",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 8),
                documents.isNotEmpty
                    ? Column(
                  children: documents.map((docUrl) {
                    return Card(
                      color: Colors.white,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: ListTile(
                        leading: const Icon(Icons.insert_drive_file,
                            color: Colors.teal),
                        title: Text(
                          docUrl.split('/').last,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.open_in_new,
                              color: Colors.teal),
                          onPressed: () => _openUrl(docUrl),
                        ),
                      ),
                    );
                  }).toList(),
                )
                    : const Text(
                  "No documents uploaded.",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Helper Widget for displaying info fields
  Widget _buildInfoTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.tealAccent.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.tealAccent, width: 0.8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white)),
            Flexible(
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 16, color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
