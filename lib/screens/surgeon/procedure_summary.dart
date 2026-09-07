import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

class _ProcedureSummaryPageState extends State<ProcedureSummaryPage>
    with TickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // COLORS
  // ---------------------------------------------------------------------------

  static const Color _background = Color(0xFF071521);
  static const Color _backgroundSecondary = Color(0xFF0B1F33);
  static const Color _surface = Color(0xFF102A3D);
  static const Color _surfaceLight = Color(0xFF15364B);

  static const Color _teal = Color(0xFF0E7490);
  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _cyanSoft = Color(0xFF67E8F9);

  static const Color _white = Color(0xFFF8FAFC);
  static const Color _textSecondary = Color(0xFF9DB2C1);
  static const Color _textMuted = Color(0xFF6F8796);

  static const Color _success = Color(0xFF34D399);
  static const Color _warning = Color(0xFFFBBF24);
  static const Color _danger = Color(0xFFFB7185);

  // ---------------------------------------------------------------------------
  // DATA
  // ---------------------------------------------------------------------------

  String summary = "";
  String? generatedImageBase64;

  bool loading = true;
  bool imageLoading = true;
  bool summaryLoading = true;
  bool hasError = false;

  String? errorMessage;

  late GenerativeModel _gemini;

  // ---------------------------------------------------------------------------
  // ANIMATION
  // ---------------------------------------------------------------------------

  late AnimationController _pageController;
  late AnimationController _pulseController;
  late AnimationController _shimmerController;

  late Animation<double> _pageFade;
  late Animation<Offset> _pageSlide;
  late Animation<double> _pulse;

  // ---------------------------------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    _gemini = GenerativeModel(
      model: "gemini-2.5-flash",
      apiKey: GEMINI_API_KEY,
    );

    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );

    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _pageFade = CurvedAnimation(
      parent: _pageController,
      curve: Curves.easeOutCubic,
    );

    _pageSlide = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _pageController,
        curve: Curves.easeOutCubic,
      ),
    );

    _pulse = Tween<double>(
      begin: 0.97,
      end: 1.03,
    ).animate(
      CurvedAnimation(
        parent: _pulseController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseController.repeat(reverse: true);
    _shimmerController.repeat();

    _loadProcedureData();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // DATA LOADING
  // ---------------------------------------------------------------------------

  Future<void> _loadProcedureData() async {
    if (mounted) {
      setState(() {
        loading = true;
        summaryLoading = true;
        imageLoading = true;
        hasError = false;
        errorMessage = null;
        summary = "";
        generatedImageBase64 = null;
      });
    }

    try {
      await Future.wait([
        _fetchSummary(),
        _generateImageREST(),
      ]);

      if (!mounted) return;

      setState(() {
        loading = false;
        summaryLoading = false;
        imageLoading = false;
      });

      _pageController.forward(from: 0);
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        summaryLoading = false;
        imageLoading = false;
        hasError = true;
        errorMessage = e.toString();
      });

      _pageController.forward(from: 0);
    }
  }

  // ---------------------------------------------------------------------------
  // GEMINI TEXT SUMMARY
  // ---------------------------------------------------------------------------

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
"""),
      ]);

      final generatedText = response.text?.trim();

      if (generatedText == null || generatedText.isEmpty) {
        throw Exception("No procedure summary was generated.");
      }

      summary = generatedText;
    } catch (e) {
      summary =
      "Unable to generate the procedure summary at this time.\n\nPlease try again.";
      debugPrint("SUMMARY ERROR: $e");

      if (errorMessage == null) {
        errorMessage = e.toString();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // IMAGE GENERATION
  // ---------------------------------------------------------------------------

  Future<void> _generateImageREST() async {
    final url =
        "https://generativelanguage.googleapis.com/v1beta/models/"
        "imagen-3.0-fast:generateImage?key=$GEMINI_API_KEY";

    final prompt = """
Create a clean, labeled medical diagram of the procedure:
"${widget.procedureName}"

Requirements:
- Clean white background
- No human faces
- Anatomy schematic
- Labels + arrows
- Educational clinical illustration
- High visual clarity
- Professional medical textbook style
- Avoid unnecessary decorative elements
""";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "prompt": {
            "text": prompt,
          },
          "imageGenerationConfig": {
            "numberOfImages": 1,
            "aspectRatio": "1:1",
            "quality": "high",
          },
        }),
      );

      if (response.statusCode != 200) {
        debugPrint("Image API Error: ${response.body}");
        return;
      }

      final data = jsonDecode(response.body);

      if (data["images"] != null &&
          data["images"] is List &&
          data["images"].isNotEmpty) {
        generatedImageBase64 = data["images"][0]["data"];
      } else {
        debugPrint("No images generated: ${response.body}");
      }
    } catch (e) {
      debugPrint("IMAGE ERROR: $e");
    }
  }

  // ---------------------------------------------------------------------------
  // SUMMARY PARSER
  // ---------------------------------------------------------------------------

  List<_ProcedureSection> _parseSummary() {
    if (summary.trim().isEmpty) return [];

    final lines = summary
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    final List<_ProcedureSection> sections = [];

    String? currentTitle;
    final List<String> currentContent = [];

    void flush() {
      if (currentTitle == null) return;

      sections.add(
        _ProcedureSection(
          title: currentTitle!,
          content: List<String>.from(currentContent),
        ),
      );

      currentContent.clear();
    }

    for (final line in lines) {
      final cleaned = line
          .replaceAll(RegExp(r'^\d+\.\s*'), '')
          .replaceAll('**', '')
          .trim();

      final isHeading = _isSectionHeading(cleaned);

      if (isHeading) {
        flush();
        currentTitle = cleaned;
      } else {
        if (currentTitle == null) {
          currentTitle = 'Clinical Overview';
        }

        currentContent.add(cleaned);
      }
    }

    flush();

    return sections;
  }

  bool _isSectionHeading(String text) {
    final lower = text.toLowerCase();

    const headings = [
      'definition',
      'indications',
      'contraindications',
      'required instruments',
      'step-by-step procedure',
      'step by step procedure',
      'risks & complications',
      'risks and complications',
      'recovery & aftercare',
      'recovery and aftercare',
      'clinical overview',
    ];

    return headings.any((heading) => lower == heading);
  }

  // ---------------------------------------------------------------------------
  // SECTION METADATA
  // ---------------------------------------------------------------------------

  _SectionVisual _sectionVisual(String title) {
    final lower = title.toLowerCase();

    if (lower.contains('definition') || lower.contains('overview')) {
      return const _SectionVisual(
        icon: Icons.info_outline_rounded,
        color: _cyan,
      );
    }

    if (lower.contains('indication')) {
      return const _SectionVisual(
        icon: Icons.check_circle_outline_rounded,
        color: _success,
      );
    }

    if (lower.contains('contraindication')) {
      return const _SectionVisual(
        icon: Icons.block_rounded,
        color: _danger,
      );
    }

    if (lower.contains('instrument')) {
      return const _SectionVisual(
        icon: Icons.medical_services_outlined,
        color: _cyanSoft,
      );
    }

    if (lower.contains('step')) {
      return const _SectionVisual(
        icon: Icons.route_rounded,
        color: _warning,
      );
    }

    if (lower.contains('risk') || lower.contains('complication')) {
      return const _SectionVisual(
        icon: Icons.warning_amber_rounded,
        color: _danger,
      );
    }

    if (lower.contains('recovery') || lower.contains('aftercare')) {
      return const _SectionVisual(
        icon: Icons.healing_rounded,
        color: _success,
      );
    }

    return const _SectionVisual(
      icon: Icons.article_outlined,
      color: _cyan,
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      extendBodyBehindAppBar: false,
      appBar: _buildAppBar(context),
      body: loading
          ? _buildLoadingState()
          : hasError
          ? _buildErrorState()
          : _buildContent(),
    );
  }

  // ---------------------------------------------------------------------------
  // APP BAR
  // ---------------------------------------------------------------------------

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: _background,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      leading: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: IconButton(
          tooltip: 'Back',
          onPressed: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).pop();
          },
          style: IconButton.styleFrom(
            backgroundColor: _surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: _white,
            size: 20,
          ),
        ),
      ),
      titleSpacing: 20,
      title: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              gradient: const LinearGradient(
                colors: [
                  _teal,
                  _cyan,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _cyan.withOpacity(0.18),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: const Icon(
              Icons.medical_information_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PROCEDURE REFERENCE',
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  widget.procedureName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: _buildClinicalBadge(),
        ),
      ],
    );
  }

  Widget _buildClinicalBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: _success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _success.withOpacity(0.20),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.verified_outlined,
            color: _success,
            size: 15,
          ),
          SizedBox(width: 6),
          Text(
            'REFERENCE',
            style: TextStyle(
              color: _success,
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOADING STATE
  // ---------------------------------------------------------------------------

  Widget _buildLoadingState() {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 650,
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Transform.scale(
                        scale: _pulse.value,
                        child: child,
                      );
                    },
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            _teal,
                            _cyan,
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _cyan.withOpacity(0.20),
                            blurRadius: 35,
                            spreadRadius: 3,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.medical_information_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  const Text(
                    'Preparing Procedure Reference',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _white,
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Generating clinical summary and visual reference',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _textSecondary.withOpacity(0.85),
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 30),
                  _buildLoadingProgress(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoadingProgress() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _surface.withOpacity(0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        children: [
          _buildLoadingTask(
            icon: Icons.psychology_outlined,
            title: 'Clinical summary',
            completed: !summaryLoading,
            active: summaryLoading,
          ),
          const SizedBox(height: 14),
          _buildLoadingTask(
            icon: Icons.image_outlined,
            title: 'Medical illustration',
            completed: generatedImageBase64 != null,
            active: imageLoading,
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingTask({
    required IconData icon,
    required String title,
    required bool completed,
    required bool active,
  }) {
    return Row(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: completed
                ? _success.withOpacity(0.12)
                : active
                ? _cyan.withOpacity(0.10)
                : Colors.white.withOpacity(0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            completed
                ? Icons.check_rounded
                : active
                ? Icons.sync_rounded
                : icon,
            size: 17,
            color: completed
                ? _success
                : active
                ? _cyan
                : _textMuted,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              color: completed || active ? _white : _textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (active)
          SizedBox(
            width: 15,
            height: 15,
            child: CircularProgressIndicator(
              strokeWidth: 1.8,
              color: _cyan.withOpacity(0.8),
            ),
          ),
        if (completed)
          const Icon(
            Icons.check_circle_rounded,
            color: _success,
            size: 17,
          ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ERROR STATE
  // ---------------------------------------------------------------------------

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            maxWidth: 500,
          ),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: _danger.withOpacity(0.16),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: _danger.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.cloud_off_rounded,
                    color: _danger,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'Unable to prepare reference',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _white,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The procedure information could not be generated. Please try again.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _loadProcedureData,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    size: 18,
                  ),
                  label: const Text('Try Again'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 13,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN CONTENT
  // ---------------------------------------------------------------------------

  Widget _buildContent() {
    final sections = _parseSummary();

    return FadeTransition(
      opacity: _pageFade,
      child: SlideTransition(
        position: _pageSlide,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth >= 1050;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.symmetric(
                horizontal: wide ? 42 : 18,
                vertical: 22,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 1450,
                  ),
                  child: wide
                      ? _buildWideContent(sections)
                      : _buildCompactContent(sections),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWideContent(List<_ProcedureSection> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroHeader(),
        const SizedBox(height: 24),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: _buildIllustrationCard(),
            ),
            const SizedBox(width: 22),
            Expanded(
              flex: 6,
              child: _buildSummaryColumn(sections),
            ),
          ],
        ),
        const SizedBox(height: 28),
        _buildSafetyFooter(),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildCompactContent(List<_ProcedureSection> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroHeader(),
        const SizedBox(height: 20),
        _buildIllustrationCard(),
        const SizedBox(height: 20),
        _buildSummaryColumn(sections),
        const SizedBox(height: 24),
        _buildSafetyFooter(),
        const SizedBox(height: 25),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // HERO
  // ---------------------------------------------------------------------------

  Widget _buildHeroHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _surfaceLight.withOpacity(0.72),
            _surface.withOpacity(0.75),
          ],
        ),
        border: Border.all(
          color: _cyan.withOpacity(0.10),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              gradient: const LinearGradient(
                colors: [
                  _teal,
                  _cyan,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: _cyan.withOpacity(0.15),
                  blurRadius: 20,
                ),
              ],
            ),
            child: const Icon(
              Icons.local_hospital_rounded,
              color: Colors.white,
              size: 27,
            ),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'AI-GENERATED CLINICAL REFERENCE',
                  style: TextStyle(
                    color: _cyan,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.7,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.procedureName,
                  style: const TextStyle(
                    color: _white,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 9),
                const Text(
                  'Structured procedural overview with indications, precautions, instruments, workflow, risks and recovery considerations.',
                  style: TextStyle(
                    color: _textSecondary,
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGE CARD
  // ---------------------------------------------------------------------------

  Widget _buildIllustrationCard() {
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.16),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _cyan.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.image_outlined,
                      color: _cyan,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 11),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Clinical Illustration',
                          style: TextStyle(
                            color: _white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Generated anatomical reference',
                          style: TextStyle(
                            color: _textMuted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (generatedImageBase64 != null)
                    _buildImageAction(),
                ],
              ),
            ),
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              constraints: const BoxConstraints(
                minHeight: 300,
                maxHeight: 620,
              ),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
              ),
              clipBehavior: Clip.antiAlias,
              child: generatedImageBase64 != null
                  ? _buildGeneratedImage()
                  : _buildNoImageState(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImageAction() {
    return IconButton(
      tooltip: 'View full illustration',
      onPressed: _openImageViewer,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withOpacity(0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
      icon: const Icon(
        Icons.fullscreen_rounded,
        color: _textSecondary,
        size: 19,
      ),
    );
  }

  Widget _buildGeneratedImage() {
    try {
      return GestureDetector(
        onTap: _openImageViewer,
        child: Hero(
          tag: 'procedure-image-${widget.procedureName}',
          child: Image.memory(
            base64Decode(generatedImageBase64!),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.high,
            errorBuilder: (context, error, stackTrace) {
              return _buildNoImageState();
            },
          ),
        ),
      );
    } catch (_) {
      return _buildNoImageState();
    }
  }

  Widget _buildNoImageState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(25),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: _backgroundSecondary,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.image_not_supported_outlined,
                color: _textMuted,
                size: 26,
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Illustration unavailable',
              style: TextStyle(
                color: Color(0xFF334155),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 5),
            const Text(
              'The clinical summary is still available below.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IMAGE VIEWER
  // ---------------------------------------------------------------------------

  void _openImageViewer() {
    if (generatedImageBase64 == null) return;

    HapticFeedback.lightImpact();

    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.92),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(20),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 5,
                  child: Hero(
                    tag: 'procedure-image-${widget.procedureName}',
                    child: Image.memory(
                      base64Decode(generatedImageBase64!),
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.pop(context),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white.withOpacity(0.10),
                  ),
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SUMMARY COLUMN
  // ---------------------------------------------------------------------------

  Widget _buildSummaryColumn(List<_ProcedureSection> sections) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(
              Icons.subject_rounded,
              color: _cyan,
              size: 19,
            ),
            const SizedBox(width: 9),
            const Text(
              'PROCEDURE OVERVIEW',
              style: TextStyle(
                color: _cyan,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
              ),
            ),
          ],
        ),
        const SizedBox(height: 13),
        ...List.generate(
          sections.length,
              (index) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: _buildSectionCard(
                sections[index],
                index,
              ),
            );
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SECTION CARD
  // ---------------------------------------------------------------------------

  Widget _buildSectionCard(
      _ProcedureSection section,
      int index,
      ) {
    final visual = _sectionVisual(section.title);

    return TweenAnimationBuilder<double>(
      duration: Duration(
        milliseconds: 350 + (index * 80),
      ),
      tween: Tween(
        begin: 0,
        end: 1,
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(
              0,
              12 * (1 - value),
            ),
            child: child,
          ),
        );
      },
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(19),
          border: Border.all(
            color: Colors.white.withOpacity(0.06),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 37,
                    height: 37,
                    decoration: BoxDecoration(
                      color: visual.color.withOpacity(0.09),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      visual.icon,
                      color: visual.color,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      section.title,
                      style: const TextStyle(
                        color: _white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 1,
                color: Colors.white.withOpacity(0.045),
              ),
              const SizedBox(height: 14),
              _buildSectionContent(
                section,
                visual.color,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionContent(
      _ProcedureSection section,
      Color accent,
      ) {
    final bool isStepSection =
    section.title.toLowerCase().contains('step');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(
        section.content.length,
            (index) {
          final item = section.content[index];

          final cleaned = item
              .replaceFirst(RegExp(r'^[-•*]\s*'), '')
              .trim();

          final isBullet =
              item.startsWith('-') ||
                  item.startsWith('•') ||
                  item.startsWith('*');

          if (isStepSection && !isBullet) {
            return _buildStepItem(
              index + 1,
              cleaned,
              accent,
            );
          }

          return Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isBullet)
                  Container(
                    margin: const EdgeInsets.only(
                      top: 6,
                      right: 10,
                    ),
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                Expanded(
                  child: Text(
                    cleaned,
                    style: const TextStyle(
                      color: _textSecondary,
                      fontSize: 13,
                      height: 1.55,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStepItem(
      int number,
      String text,
      Color accent,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 27,
            height: 27,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              shape: BoxShape.circle,
              border: Border.all(
                color: accent.withOpacity(0.20),
              ),
            ),
            child: Text(
              '$number',
              style: TextStyle(
                color: accent,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                text,
                style: const TextStyle(
                  color: _textSecondary,
                  fontSize: 13,
                  height: 1.55,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SAFETY FOOTER
  // ---------------------------------------------------------------------------

  Widget _buildSafetyFooter() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: _warning.withOpacity(0.055),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _warning.withOpacity(0.13),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: _warning.withOpacity(0.09),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.info_outline_rounded,
              color: _warning,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Clinical reference only. This AI-generated information is intended to support professional reference and should not replace institutional protocols, current clinical guidelines, or professional medical judgment.',
              style: TextStyle(
                color: _textSecondary,
                fontSize: 11,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DATA MODELS
// =============================================================================

class _ProcedureSection {
  final String title;
  final List<String> content;

  const _ProcedureSection({
    required this.title,
    required this.content,
  });
}

class _SectionVisual {
  final IconData icon;
  final Color color;

  const _SectionVisual({
    required this.icon,
    required this.color,
  });
}