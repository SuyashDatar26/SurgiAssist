import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_generative_ai/google_generative_ai.dart';

import '../../secrets.dart';

class ProcedureSummaryPage extends StatefulWidget {
  final String procedureName;

  const ProcedureSummaryPage({
    Key? key,
    required this.procedureName,
  }) : super(key: key);

  @override
  State<ProcedureSummaryPage> createState() => _ProcedureSummaryPageState();
}

class _ProcedureSummaryPageState extends State<ProcedureSummaryPage> {
  String summary = "";
  String? generatedImageBase64;
  bool loading = true;

  late GenerativeModel _gemini;

  @override
  void initState() {
    super.initState();
    _gemini = GenerativeModel(
      model: "gemini-2.5-flash",
      apiKey: GEMINI_API_KEY,
    );
    _loadProcedureData();
  }

  Future<void> _loadProcedureData() async {
    await _fetchSummary();
    await _generateImageREST();
    setState(() => loading = false);
  }

  /// 🧠 TEXT SUMMARY
  Future<void> _fetchSummary() async {
    try {
      final response = await _gemini.generateContent([
        Content.text("""
Provide a medically accurate but concise summary of the procedure '${widget.procedureName}'.

Format:
1. **Definition** (2–3 lines)  
2. **Indications** (3–5 key points)  
3. **Contraindications** (3–5 key points)  
4. **Required Instruments** (short list only)  
5. **Step-by-step Procedure**  
   - Maximum 6 steps  
   - Each step 1–2 lines only  
6. **Risks & Complications** (4–6 concise points)  
7. **Recovery & Aftercare** (3–5 practical points)

Constraints:
- Total length MUST be 250–350 words.  
- Avoid overly detailed surgical descriptions.  
- Keep it readable and crisp, but still medically informative.
""")
      ]);


      summary = response.text ?? "No summary found.";
    } catch (e) {
      summary = "Error loading summary: $e";
    }
  }

  /// 🎨 IMAGE GENERATION — REST API (works 100%)
  Future<void> _generateImageREST() async {
    final url =
        "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-fast:generateImage?key=$GEMINI_API_KEY";

    final prompt = """
Create a clean, labeled medical diagram of the procedure:
"${widget.procedureName}"

Requirements:
- Clean white background
- No human faces
- Anatomy schematic
- Labels + arrows
""";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "prompt": {
            "text": prompt,
          },
          "imageGenerationConfig": {
            "numberOfImages": 1,
            "aspectRatio": "1:1",
            "quality": "high"
          }
        }),
      );

      if (response.statusCode != 200) {
        debugPrint("Image API Error: ${response.body}");
        return;
      }

      final json = jsonDecode(response.body);

      if (json["images"] != null && json["images"].isNotEmpty) {
        generatedImageBase64 = json["images"][0]["data"];
      } else {
        debugPrint("No images generated: ${response.body}");
      }
    } catch (e) {
      debugPrint("IMAGE ERROR: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F2027),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(
          widget.procedureName.toUpperCase(),
          style: const TextStyle(color: Colors.tealAccent),
        ),
      ),

      body: loading
          ? const Center(
        child: CircularProgressIndicator(color: Colors.tealAccent),
      )
          : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 🖼 Display Generated Image
            if (generatedImageBase64 != null)
              Column(
                children: [
                  Image.memory(
                    base64Decode(generatedImageBase64!),
                    fit: BoxFit.contain,
                  ),
                  const SizedBox(height: 20),
                ],
              )
            else
              const Text(
                "No illustration available.",
                style: TextStyle(color: Colors.grey),
              ),

            // 📘 Summary Text
            Text(
              summary,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
