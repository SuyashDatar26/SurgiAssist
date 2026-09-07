import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';

class PDFViewerPage extends StatefulWidget {
  final String pdfUrl;

  const PDFViewerPage({
    super.key,
    required this.pdfUrl,
  });

  @override
  State<PDFViewerPage> createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends State<PDFViewerPage>
    with TickerProviderStateMixin {
// ===========================================================================
// CONTROLLERS
// ===========================================================================

  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();

  final FocusNode _keyboardFocusNode = FocusNode();

  PDFViewController? _pdfController;

  late AnimationController _entranceController;
  late AnimationController _hudController;
  late AnimationController _loadingController;
  late AnimationController _pageControllerAnimation;

// ===========================================================================
// PDF STATE
// ===========================================================================

  String? localPath;

  int _currentPage = 0;
  int _totalPages = 0;

  bool _isReady = false;
  bool _isLoading = true;
  bool _hasError = false;
  bool _isDownloading = false;

  String? _errorMessage;

  double _downloadProgress = 0;

// ===========================================================================
// UI STATE
// ===========================================================================

  bool _showControls = true;
  bool _isFullscreen = false;

  Timer? _controlsTimer;

// ===========================================================================
// COLORS
// ===========================================================================

  static const Color _background = Color(0xFF02080D);
  static const Color _surface = Color(0xFF07131D);
  static const Color _surfaceLight = Color(0xFF0C202D);

  static const Color _cyan = Color(0xFF22D3EE);
  static const Color _teal = Color(0xFF0E7490);

  static const Color _white = Color(0xFFF5FAFC);
  static const Color _secondaryText = Color(0xFFA9C0CC);
  static const Color _mutedText = Color(0xFF6F8A98);

  static const Color _success = Color(0xFF22C55E);
  static const Color _warning = Color(0xFFF59E0B);
  static const Color _danger = Color(0xFFEF4444);

// ===========================================================================
// INIT
// ===========================================================================

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );

    _hudController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );

    _loadingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _pageControllerAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _entranceController.forward();
    _hudController.forward();
    _loadingController.repeat();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _keyboardFocusNode.requestFocus();
      }
    });

    _downloadPdf();
  }

// ===========================================================================
// PDF DOWNLOAD
// ===========================================================================

  Future<void> _downloadPdf() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = null;
      _downloadProgress = 0;
    });

    try {
      final uri = Uri.parse(widget.pdfUrl);

      final request = http.Request(
        'GET',
        uri,
      );

      final response = await request.send();

      if (response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw Exception(
          'Server returned status ${response.statusCode}',
        );
      }

      final contentLength = response.contentLength ?? 0;

      final dir = await getTemporaryDirectory();

      final fileName =
          'clinical_document_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final file = File(
        '${dir.path}/$fileName',
      );

      final sink = file.openWrite();

      int received = 0;

      await for (final chunk in response.stream) {
        if (!mounted) {
          await sink.close();
          return;
        }

        sink.add(chunk);

        received += chunk.length;

        if (contentLength > 0) {
          setState(() {
            _downloadProgress =
                received / contentLength;
          });
        }
      }

      await sink.flush();
      await sink.close();

      if (!mounted) return;

      setState(() {
        localPath = file.path;
        _isLoading = false;
        _downloadProgress = 1;
      });

      _loadingController.stop();
      _loadingController.value = 1;
    } catch (e) {
      debugPrint(
        'PDF download error: $e',
      );

      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage =
        'Unable to load this clinical document.';
      });

      _loadingController.stop();
    }
  }

// ===========================================================================
// PDF READY
// ===========================================================================

  void _onPdfViewCreated(
      PDFViewController controller,
      ) {
    _pdfController = controller;
  }

  void _onRender(int? pages) {
    if (!mounted) return;

    final renderedPages = pages ?? 0;

    setState(() {
      _totalPages = renderedPages;
      _isReady = renderedPages > 0;
      _isLoading = false;
    });

    _pageControllerAnimation
      ..reset()
      ..forward();

    if (renderedPages > 0) {
      _startControlsTimer();
    }
  }

  void _onPageChanged(
      int? page,
      int? total,
      ) {
    if (!mounted) return;

    setState(() {
      _currentPage = page ?? 0;

      if (total != null && total > 0) {
        _totalPages = total;
      }
    });

    _startControlsTimer();
  }

  void _onError(dynamic error) {
    debugPrint(
      'PDF rendering error: $error',
    );

    if (!mounted) return;

    setState(() {
      _hasError = true;
      _isLoading = false;
      _errorMessage =
      'The PDF could not be rendered.';
    });
  }

// ===========================================================================
// PAGE NAVIGATION
// ===========================================================================

  Future<void> _nextPage() async {
    if (_pdfController == null) return;

    if (_currentPage >= _totalPages - 1) {
      _showBoundaryMessage('Already on the last page');
      return;
    }

    await _pdfController!.setPage(
      _currentPage + 1,
    );

    _startControlsTimer();
  }

  Future<void> _previousPage() async {
    if (_pdfController == null) return;

    if (_currentPage <= 0) {
      _showBoundaryMessage('Already on the first page');
      return;
    }

    await _pdfController!.setPage(
      _currentPage - 1,
    );

    _startControlsTimer();
  }

  Future<void> _goToPage(int page) async {
    if (_pdfController == null) return;

    if (page < 0 ||
        page >= _totalPages) {
      return;
    }

    await _pdfController!.setPage(page);

    _startControlsTimer();
  }

// ===========================================================================
// PAGE INPUT
// ===========================================================================

  Future<void> _showPageSelector() async {
    if (_totalPages <= 0) return;

    final controller = TextEditingController(
      text: '${_currentPage + 1}',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.45),
                  blurRadius: 40,
                  offset: const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: _cyan.withOpacity(0.09),
                        borderRadius:
                        BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.find_in_page_outlined,
                        color: _cyan,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                        CrossAxisAlignment.start,
                        children: [
                          Text(
                            'GO TO PAGE',
                            style: GoogleFonts.inter(
                              color: _mutedText,
                              fontSize: 8,
                              fontWeight:
                              FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Navigate document',
                            style: GoogleFonts.poppins(
                              color: _white,
                              fontSize: 15,
                              fontWeight:
                              FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 22),

                TextField(
                  controller: controller,
                  autofocus: true,
                  keyboardType:
                  TextInputType.number,
                  style: GoogleFonts.inter(
                    color: _white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Page number',
                    labelStyle: GoogleFonts.inter(
                      color: _mutedText,
                      fontSize: 11,
                    ),
                    hintText:
                    '1 – $_totalPages',
                    hintStyle: GoogleFonts.inter(
                      color: _mutedText,
                      fontSize: 11,
                    ),
                    filled: true,
                    fillColor: Colors.white
                        .withOpacity(0.035),
                    border: OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white
                            .withOpacity(0.07),
                      ),
                    ),
                    enabledBorder:
                    OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                      borderSide: BorderSide(
                        color: Colors.white
                            .withOpacity(0.07),
                      ),
                    ),
                    focusedBorder:
                    OutlineInputBorder(
                      borderRadius:
                      BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: _cyan,
                      ),
                    ),
                  ),
                  onSubmitted: (_) {
                    final page = int.tryParse(
                      controller.text.trim(),
                    );

                    if (page != null &&
                        page >= 1 &&
                        page <= _totalPages) {
                      Navigator.pop(
                        context,
                        page - 1,
                      );
                    }
                  },
                ),

                const SizedBox(height: 18),

                Row(
                  mainAxisAlignment:
                  MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context);
                      },
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.inter(
                          color: _secondaryText,
                          fontWeight:
                          FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () {
                        final page =
                        int.tryParse(
                          controller.text.trim(),
                        );

                        if (page != null &&
                            page >= 1 &&
                            page <=
                                _totalPages) {
                          Navigator.pop(
                            context,
                            page - 1,
                          );
                        }
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: _cyan,
                        foregroundColor:
                        Colors.black,
                        shape:
                        RoundedRectangleBorder(
                          borderRadius:
                          BorderRadius.circular(
                            12,
                          ),
                        ),
                      ),
                      child: const Text(
                        'Go',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    controller.dispose();

    if (result != null) {
      await _goToPage(result);
    }
  }

// ===========================================================================
// FULLSCREEN
// ===========================================================================

  Future<void> _toggleFullscreen() async {
    setState(() {
      _isFullscreen = !_isFullscreen;
    });

    if (_isFullscreen) {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    } else {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );
    }
  }

// ===========================================================================
// CONTROLS
// ===========================================================================

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });

    if (_showControls) {
      _hudController.forward();
      _startControlsTimer();
    } else {
      _hudController.reverse();
      _controlsTimer?.cancel();
    }
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();

    if (!_showControls) {
      setState(() {
        _showControls = true;
      });

      _hudController.forward();
    }

    _controlsTimer = Timer(
      const Duration(seconds: 6),
          () {
        if (mounted && !_isFullscreen) {
          setState(() {
            _showControls = false;
          });

          _hudController.reverse();
        }
      },
    );
  }

// ===========================================================================
// OPEN EXTERNALLY
// ===========================================================================

  Future<void> _openExternally() async {
    if (localPath == null) return;

    final result = await OpenFile.open(
      localPath!,
    );

    if (result.type != ResultType.done) {
      _showSnackBar(
        'Unable to open PDF externally.',
        _danger,
      );
    }
  }

// ===========================================================================
// DOWNLOAD TO TEMP / SHAREABLE SYSTEM FILE
// ===========================================================================

  Future<void> _savePdf() async {
    if (localPath == null || _isDownloading) {
      return;
    }

    setState(() {
      _isDownloading = true;
    });

    try {
      final directory =
      await getApplicationDocumentsDirectory();

      final fileName =
          'SurgiAssist_Clinical_Report_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final destination = File(
        '${directory.path}/$fileName',
      );

      await File(localPath!).copy(
        destination.path,
      );

      if (!mounted) return;

      _showSnackBar(
        'Clinical PDF saved successfully.',
        _success,
      );
    } catch (e) {
      debugPrint(
        'Save PDF error: $e',
      );

      if (!mounted) return;

      _showSnackBar(
        'Unable to save PDF.',
        _danger,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

// ===========================================================================
// MESSAGES
// ===========================================================================

  void _showBoundaryMessage(
      String message,
      ) {
    _showSnackBar(
      message,
      _mutedText,
    );
  }

  void _showSnackBar(
      String message,
      Color color,
      ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior:
          SnackBarBehavior.floating,
          backgroundColor: _surface,
          margin: const EdgeInsets.fromLTRB(
            18,
            0,
            18,
            18,
          ),
          shape: RoundedRectangleBorder(
            borderRadius:
            BorderRadius.circular(14),
          ),
          content: Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: GoogleFonts.inter(
                    color: _white,
                    fontSize: 11,
                    fontWeight:
                    FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
  }

// ===========================================================================
// BACK
// ===========================================================================

  Future<bool> _onBackPressed() async {
    if (_isFullscreen) {
      await _toggleFullscreen();
      return false;
    }

    Navigator.pop(context);
    return false;
  }

// ===========================================================================
// KEYBOARD
// ===========================================================================

  void _handleKeyEvent(
      KeyEvent event,
      ) {
    if (event is! KeyDownEvent) return;

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowRight) {
      _nextPage();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.pageDown) {
      _nextPage();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.arrowLeft) {
      _previousPage();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.pageUp) {
      _previousPage();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.home) {
      _goToPage(0);
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.end) {
      if (_totalPages > 0) {
        _goToPage(_totalPages - 1);
      }
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.space) {
      _toggleControls();
      return;
    }

    if (event.logicalKey ==
        LogicalKeyboardKey.escape) {
      if (_isFullscreen) {
        _toggleFullscreen();
      } else {
        _onBackPressed();
      }
    }
  }

// ===========================================================================
// DISPOSE
// ===========================================================================

  @override
  void dispose() {
    _controlsTimer?.cancel();

    _keyboardFocusNode.dispose();

    _entranceController.dispose();
    _hudController.dispose();
    _loadingController.dispose();
    _pageControllerAnimation.dispose();

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    super.dispose();
  }

// ===========================================================================
// BUILD
// ===========================================================================

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onBackPressed,
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _background,
        body: KeyboardListener(
          focusNode: _keyboardFocusNode,
          onKeyEvent: _handleKeyEvent,
          child: Stack(
            children: [
              Positioned.fill(
                child: _buildPdfArea(),
              ),

              if (!_isFullscreen)
                _buildTopGradient(),

              if (!_isFullscreen)
                _buildBottomGradient(),

              _buildTopHud(),

              if (_isReady && !_isFullscreen)
                _buildSideNavigation(),

              if (_isReady)
                _buildBottomHud(),

              if (_hasError)
                _buildErrorOverlay(),
            ],
          ),
        ),
      ),
    );
  }

// ===========================================================================
// PDF AREA
// ===========================================================================

  Widget _buildPdfArea() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_hasError || localPath == null) {
      return Container(
        color: Colors.black,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: _startControlsTimer,
      child: AnimatedOpacity(
        duration:
        const Duration(milliseconds: 400),
        opacity: _isReady ? 1 : 0,
        child: PDFView(
          filePath: localPath!,
          enableSwipe: true,
          swipeHorizontal: false,
          autoSpacing: true,
          pageFling: true,
          pageSnap: true,
          fitPolicy: FitPolicy.WIDTH,
          preventLinkNavigation: false,
          onViewCreated:
          _onPdfViewCreated,
          onRender: _onRender,
          onPageChanged:
          _onPageChanged,
          onError: _onError,
          onPageError: (
              page,
              error,
              ) {
            debugPrint(
              'PDF page $page error: $error',
            );
          },
        ),
      ),
    );
  }

// ===========================================================================
// LOADING STATE
// ===========================================================================

  Widget _buildLoadingState() {
    return Container(
      color: _background,
      child: Center(
        child: AnimatedBuilder(
          animation: _loadingController,
          builder: (
              context,
              child,
              ) {
            final pulse =
                0.92 +
                    (_loadingController.value *
                        0.08);

            return Transform.scale(
              scale: pulse,
              child: child,
            );
          },
          child: Container(
            width: 270,
            padding:
            const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius:
              BorderRadius.circular(25),
              border: Border.all(
                color:
                _cyan.withOpacity(0.10),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                  Colors.black.withOpacity(
                    0.35,
                  ),
                  blurRadius: 40,
                  offset:
                  const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration:
                  BoxDecoration(
                    color:
                    _cyan.withOpacity(
                      0.08,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      18,
                    ),
                    border: Border.all(
                      color:
                      _cyan.withOpacity(
                        0.12,
                      ),
                    ),
                  ),
                  child:
                  const Icon(
                    Icons.picture_as_pdf_outlined,
                    color: _cyan,
                    size: 30,
                  ),
                ),

                const SizedBox(height: 18),

                Text(
                  'PREPARING DOCUMENT',
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize: 8.5,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing:
                    1.5,
                  ),
                ),

                const SizedBox(height: 7),

                Text(
                  'Loading clinical PDF',
                  style:
                  GoogleFonts.poppins(
                    color: _white,
                    fontSize: 15,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 18),

                ClipRRect(
                  borderRadius:
                  BorderRadius.circular(
                    20,
                  ),
                  child: LinearProgressIndicator(
                    value:
                    _downloadProgress > 0
                        ? _downloadProgress
                        : null,
                    minHeight: 4,
                    backgroundColor:
                    Colors.white
                        .withOpacity(
                      0.055,
                    ),
                    color: _cyan,
                  ),
                ),

                const SizedBox(height: 9),

                Text(
                  _downloadProgress > 0
                      ? '${(_downloadProgress * 100).round()}% downloaded'
                      : 'Connecting to secure document source…',
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize: 9.5,
                    fontWeight:
                    FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// TOP GRADIENT
// ===========================================================================

  Widget _buildTopGradient() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      height: 190,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration:
          const Duration(milliseconds: 300),
          opacity:
          _showControls ? 1 : 0,
          child: Container(
            decoration:
            const BoxDecoration(
              gradient: LinearGradient(
                begin:
                Alignment.topCenter,
                end:
                Alignment.bottomCenter,
                colors: [
                  Color(0xE802080D),
                  Color(0x9002080D),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// BOTTOM GRADIENT
// ===========================================================================

  Widget _buildBottomGradient() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 240,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration:
          const Duration(milliseconds: 300),
          opacity:
          _showControls ? 1 : 0,
          child: Container(
            decoration:
            const BoxDecoration(
              gradient: LinearGradient(
                begin:
                Alignment.bottomCenter,
                end:
                Alignment.topCenter,
                colors: [
                  Color(0xF002080D),
                  Color(0xA502080D),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// TOP HUD
// ===========================================================================

  Widget _buildTopHud() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: AnimatedSlide(
          duration:
          const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          offset: _showControls
              ? Offset.zero
              : const Offset(
            0,
            -0.3,
          ),
          child: AnimatedOpacity(
            duration:
            const Duration(milliseconds: 300),
            opacity:
            _showControls ? 1 : 0,
            child: Padding(
              padding:
              const EdgeInsets.fromLTRB(
                16,
                12,
                16,
                0,
              ),
              child: Row(
                children: [
                  _buildGlassButton(
                    icon:
                    Icons.arrow_back_rounded,
                    tooltip: 'Back',
                    onPressed:
                    _onBackPressed,
                  ),

                  const SizedBox(width: 11),

                  Expanded(
                    child:
                    _buildDocumentHeader(),
                  ),

                  const SizedBox(width: 11),

                  _buildTopAction(
                    icon:
                    Icons.open_in_new_rounded,
                    tooltip:
                    'Open externally',
                    onPressed:
                    localPath == null
                        ? null
                        : _openExternally,
                  ),

                  const SizedBox(width: 7),

                  _buildTopAction(
                    icon:
                    Icons.download_outlined,
                    tooltip:
                    'Save PDF',
                    onPressed:
                    localPath == null ||
                        _isDownloading
                        ? null
                        : _savePdf,
                    loading:
                    _isDownloading,
                  ),

                  const SizedBox(width: 7),

                  _buildTopAction(
                    icon:
                    _isFullscreen
                        ? Icons
                        .fullscreen_exit_rounded
                        : Icons
                        .fullscreen_rounded,
                    tooltip:
                    'Fullscreen',
                    onPressed:
                    _toggleFullscreen,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// DOCUMENT HEADER
// ===========================================================================

  Widget _buildDocumentHeader() {
    return Container(
      height: 58,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 16,
      ),
      decoration: BoxDecoration(
        color:
        _surface.withOpacity(0.90),
        borderRadius:
        BorderRadius.circular(18),
        border: Border.all(
          color:
          Colors.white.withOpacity(
            0.075,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(
              0.28,
            ),
            blurRadius: 25,
            offset:
            const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration:
            BoxDecoration(
              color:
              _danger.withOpacity(
                0.09,
              ),
              borderRadius:
              BorderRadius.circular(
                10,
              ),
            ),
            child: const Icon(
              Icons.picture_as_pdf_rounded,
              color: _danger,
              size: 18,
            ),
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Text(
                  'CLINICAL DOCUMENT',
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize: 8,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing:
                    1.25,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'Medical Report',
                  maxLines: 1,
                  overflow:
                  TextOverflow.ellipsis,
                  style:
                  GoogleFonts.poppins(
                    color:
                    _white,
                    fontSize: 13.5,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          if (_totalPages > 0)
            _buildPageCounter(),
        ],
      ),
    );
  }

// ===========================================================================
// PAGE COUNTER
// ===========================================================================

  Widget _buildPageCounter() {
    return GestureDetector(
      onTap: _showPageSelector,
      child: Container(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 8,
        ),
        decoration:
        BoxDecoration(
          color:
          Colors.white.withOpacity(
            0.045,
          ),
          borderRadius:
          BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color:
            Colors.white.withOpacity(
              0.06,
            ),
          ),
        ),
        child: Row(
          mainAxisSize:
          MainAxisSize.min,
          children: [
            Text(
              '${_currentPage + 1}',
              style:
              GoogleFonts.inter(
                color:
                _cyan,
                fontSize: 10,
                fontWeight:
                FontWeight.w900,
              ),
            ),
            Text(
              ' / $_totalPages',
              style:
              GoogleFonts.inter(
                color:
                _secondaryText,
                fontSize: 10,
                fontWeight:
                FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

// ===========================================================================
// TOP ACTION
// ===========================================================================

  Widget _buildTopAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
    bool loading = false,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration:
      const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(16),
          onTap: onPressed,
          child: AnimatedOpacity(
            duration:
            const Duration(milliseconds: 200),
            opacity:
            onPressed == null ? 0.35 : 1,
            child: Container(
              width: 48,
              height: 58,
              decoration:
              BoxDecoration(
                color:
                _surface.withOpacity(
                  0.90,
                ),
                borderRadius:
                BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color:
                  Colors.white.withOpacity(
                    0.075,
                  ),
                ),
              ),
              child: loading
                  ? const Center(
                child:
                SizedBox(
                  width: 17,
                  height: 17,
                  child:
                  CircularProgressIndicator(
                    strokeWidth:
                    2,
                    color: _cyan,
                  ),
                ),
              )
                  : Icon(
                icon,
                color: _white,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// GLASS BACK BUTTON
// ===========================================================================

  Widget _buildGlassButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration:
      const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(18),
          onTap: onPressed,
          child: Container(
            width: 58,
            height: 58,
            decoration:
            BoxDecoration(
              color:
              _surface.withOpacity(
                0.90,
              ),
              borderRadius:
              BorderRadius.circular(
                18,
              ),
              border: Border.all(
                color:
                Colors.white.withOpacity(
                  0.075,
                ),
              ),
            ),
            child: Icon(
              icon,
              color: _white,
              size: 20,
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// SIDE NAVIGATION
// ===========================================================================

  Widget _buildSideNavigation() {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_showControls,
        child: Row(
          mainAxisAlignment:
          MainAxisAlignment.spaceBetween,
          children: [
            Padding(
              padding:
              const EdgeInsets.only(
                left: 18,
              ),
              child:
              _buildPageNavigationButton(
                icon:
                Icons.chevron_left_rounded,
                enabled:
                _currentPage > 0,
                onPressed:
                _previousPage,
              ),
            ),
            Padding(
              padding:
              const EdgeInsets.only(
                right: 18,
              ),
              child:
              _buildPageNavigationButton(
                icon:
                Icons.chevron_right_rounded,
                enabled:
                _currentPage <
                    _totalPages - 1,
                onPressed:
                _nextPage,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPageNavigationButton({
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    return AnimatedOpacity(
      duration:
      const Duration(milliseconds: 250),
      opacity:
      enabled ? 1 : 0.25,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(17),
          onTap:
          enabled ? onPressed : null,
          child: Container(
            width: 48,
            height: 88,
            decoration:
            BoxDecoration(
              color:
              _surface.withOpacity(
                0.82,
              ),
              borderRadius:
              BorderRadius.circular(
                17,
              ),
              border: Border.all(
                color:
                Colors.white.withOpacity(
                  0.07,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                  Colors.black.withOpacity(
                    0.25,
                  ),
                  blurRadius: 20,
                  offset:
                  const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              icon,
              color: _white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// BOTTOM HUD
// ===========================================================================

  Widget _buildBottomHud() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        top: false,
        child: AnimatedSlide(
          duration:
          const Duration(milliseconds: 350),
          curve:
          Curves.easeOutCubic,
          offset: _showControls
              ? Offset.zero
              : const Offset(
            0,
            0.35,
          ),
          child: AnimatedOpacity(
            duration:
            const Duration(milliseconds: 300),
            opacity:
            _showControls ? 1 : 0,
            child: Padding(
              padding:
              const EdgeInsets.fromLTRB(
                16,
                0,
                16,
                14,
              ),
              child: _buildControlBar(),
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// CONTROL BAR
// ===========================================================================

  Widget _buildControlBar() {
    return Container(
      height: 64,
      padding:
      const EdgeInsets.symmetric(
        horizontal: 8,
      ),
      decoration:
      BoxDecoration(
        color:
        _surface.withOpacity(
          0.94,
        ),
        borderRadius:
        BorderRadius.circular(
          19,
        ),
        border: Border.all(
          color:
          Colors.white.withOpacity(
            0.075,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color:
            Colors.black.withOpacity(
              0.32,
            ),
            blurRadius: 28,
            offset:
            const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildControlButton(
            icon:
            Icons.keyboard_double_arrow_left_rounded,
            tooltip:
            'First page',
            onPressed:
            _currentPage > 0
                ? () => _goToPage(0)
                : null,
          ),

          _buildControlButton(
            icon:
            Icons.chevron_left_rounded,
            tooltip:
            'Previous page',
            onPressed:
            _currentPage > 0
                ? _previousPage
                : null,
          ),

          _buildCurrentPageButton(),

          _buildControlButton(
            icon:
            Icons.chevron_right_rounded,
            tooltip:
            'Next page',
            onPressed:
            _currentPage <
                _totalPages - 1
                ? _nextPage
                : null,
          ),

          _buildControlButton(
            icon:
            Icons.keyboard_double_arrow_right_rounded,
            tooltip:
            'Last page',
            onPressed:
            _currentPage <
                _totalPages - 1
                ? () => _goToPage(
              _totalPages - 1,
            )
                : null,
          ),

          const SizedBox(width: 7),

          Container(
            width: 1,
            height: 28,
            color:
            Colors.white.withOpacity(
              0.07,
            ),
          ),

          const SizedBox(width: 7),

          Expanded(
            child: _buildDocumentProgress(),
          ),

          const SizedBox(width: 7),

          Container(
            width: 1,
            height: 28,
            color:
            Colors.white.withOpacity(
              0.07,
            ),
          ),

          const SizedBox(width: 7),

          _buildControlButton(
            icon:
            Icons.keyboard_outlined,
            tooltip:
            'Keyboard shortcuts',
            onPressed:
            _showKeyboardShortcuts,
          ),

          _buildControlButton(
            icon:
            Icons.visibility_off_outlined,
            tooltip:
            'Hide controls',
            onPressed:
            _toggleControls,
          ),
        ],
      ),
    );
  }

// ===========================================================================
// CURRENT PAGE
// ===========================================================================

  Widget _buildCurrentPageButton() {
    return Tooltip(
      message: 'Go to page',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
          onTap:
          _showPageSelector,
          child: Container(
            constraints:
            const BoxConstraints(
              minWidth: 65,
            ),
            height: 46,
            alignment:
            Alignment.center,
            child: Column(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children: [
                Text(
                  '${_currentPage + 1}',
                  style:
                  GoogleFonts.poppins(
                    color:
                    _white,
                    fontSize: 13,
                    fontWeight:
                    FontWeight.w800,
                  ),
                ),
                Text(
                  'OF $_totalPages',
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize: 7,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing:
                    0.8,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// DOCUMENT PROGRESS
// ===========================================================================

  Widget _buildDocumentProgress() {
    final progress =
    _totalPages > 0
        ? (_currentPage + 1) /
        _totalPages
        : 0.0;

    return Column(
      mainAxisAlignment:
      MainAxisAlignment.center,
      children: [
        Row(
          children: [
            Text(
              'DOCUMENT PROGRESS',
              style:
              GoogleFonts.inter(
                color:
                _mutedText,
                fontSize: 7.5,
                fontWeight:
                FontWeight.w800,
                letterSpacing:
                1.0,
              ),
            ),
            const Spacer(),
            Text(
              '${(progress * 100).round()}%',
              style:
              GoogleFonts.inter(
                color:
                _secondaryText,
                fontSize: 8,
                fontWeight:
                FontWeight.w800,
              ),
            ),
          ],
        ),

        const SizedBox(height: 6),

        ClipRRect(
          borderRadius:
          BorderRadius.circular(
            20,
          ),
          child: Stack(
            children: [
              Container(
                height: 4,
                decoration:
                BoxDecoration(
                  color:
                  Colors.white.withOpacity(
                    0.055,
                  ),
                ),
              ),
              AnimatedFractionallySizedBox(
                duration:
                const Duration(
                  milliseconds: 350,
                ),
                curve:
                Curves.easeOutCubic,
                widthFactor:
                progress.clamp(
                  0.0,
                  1.0,
                ),
                child: Container(
                  height: 4,
                  decoration:
                  BoxDecoration(
                    color:
                    _cyan,
                    borderRadius:
                    BorderRadius.circular(
                      20,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                        _cyan.withOpacity(
                          0.35,
                        ),
                        blurRadius:
                        8,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

// ===========================================================================
// CONTROL BUTTON
// ===========================================================================

  Widget _buildControlButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onPressed,
  }) {
    final enabled =
        onPressed != null;

    return Tooltip(
      message: tooltip,
      waitDuration:
      const Duration(milliseconds: 500),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius:
          BorderRadius.circular(
            12,
          ),
          onTap: onPressed,
          child: AnimatedOpacity(
            duration:
            const Duration(milliseconds: 200),
            opacity:
            enabled ? 1 : 0.25,
            child: SizedBox(
              width: 43,
              height: 48,
              child: Icon(
                icon,
                color: enabled
                    ? _white
                    : _mutedText,
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }

// ===========================================================================
// ERROR OVERLAY
// ===========================================================================

  Widget _buildErrorOverlay() {
    return Positioned.fill(
      child: Container(
        color:
        _background.withOpacity(0.96),
        child: Center(
          child: Container(
            width: 350,
            margin:
            const EdgeInsets.all(24),
            padding:
            const EdgeInsets.all(28),
            decoration:
            BoxDecoration(
              color:
              _surface,
              borderRadius:
              BorderRadius.circular(
                25,
              ),
              border: Border.all(
                color:
                _danger.withOpacity(
                  0.13,
                ),
              ),
              boxShadow: [
                BoxShadow(
                  color:
                  Colors.black.withOpacity(
                    0.40,
                  ),
                  blurRadius:
                  40,
                  offset:
                  const Offset(0, 15),
                ),
              ],
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration:
                  BoxDecoration(
                    color:
                    _danger.withOpacity(
                      0.08,
                    ),
                    shape:
                    BoxShape.circle,
                  ),
                  child:
                  const Icon(
                    Icons
                        .picture_as_pdf_outlined,
                    color:
                    _danger,
                    size: 31,
                  ),
                ),

                const SizedBox(
                  height: 19,
                ),

                Text(
                  'DOCUMENT UNAVAILABLE',
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize:
                    8.5,
                    fontWeight:
                    FontWeight.w800,
                    letterSpacing:
                    1.3,
                  ),
                ),

                const SizedBox(
                  height: 7,
                ),

                Text(
                  'Unable to open PDF',
                  textAlign:
                  TextAlign.center,
                  style:
                  GoogleFonts.poppins(
                    color:
                    _white,
                    fontSize:
                    17,
                    fontWeight:
                    FontWeight.w700,
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                Text(
                  _errorMessage ??
                      'Something went wrong while loading the clinical document.',
                  textAlign:
                  TextAlign.center,
                  style:
                  GoogleFonts.inter(
                    color:
                    _mutedText,
                    fontSize:
                    10.5,
                    height:
                    1.5,
                  ),
                ),

                const SizedBox(
                  height: 22,
                ),

                SizedBox(
                  width:
                  double.infinity,
                  height:
                  45,
                  child:
                  FilledButton.icon(
                    onPressed:
                    _downloadPdf,
                    style:
                    FilledButton.styleFrom(
                      backgroundColor:
                      _cyan,
                      foregroundColor:
                      Colors.black,
                      shape:
                      RoundedRectangleBorder(
                        borderRadius:
                        BorderRadius.circular(
                          13,
                        ),
                      ),
                    ),
                    icon:
                    const Icon(
                      Icons.refresh_rounded,
                      size: 17,
                    ),
                    label:
                    Text(
                      'Retry document',
                      style:
                      GoogleFonts.inter(
                        fontSize:
                        11,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                  ),
                ),

                const SizedBox(
                  height: 8,
                ),

                TextButton(
                  onPressed:
                  _onBackPressed,
                  child:
                  Text(
                    'Return',
                    style:
                    GoogleFonts.inter(
                      color:
                      _secondaryText,
                      fontSize:
                      11,
                      fontWeight:
                      FontWeight.w600,
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

// ===========================================================================
// KEYBOARD SHORTCUTS
// ===========================================================================

  void _showKeyboardShortcuts() {
    showDialog(
      context: context,
      builder: (context) {
        final shortcuts = [
          [
            '← / Page Up',
            'Previous page',
          ],
          [
            '→ / Page Down',
            'Next page',
          ],
          [
            'Home',
            'First page',
          ],
          [
            'End',
            'Last page',
          ],
          [
            'Space',
            'Show / hide controls',
          ],
          [
            'Esc',
            'Exit fullscreen / viewer',
          ],
        ];

        return Dialog(
          backgroundColor:
          Colors.transparent,
          child: Container(
            width: 390,
            padding:
            const EdgeInsets.all(25),
            decoration:
            BoxDecoration(
              color:
              _surface,
              borderRadius:
              BorderRadius.circular(
                23,
              ),
              border: Border.all(
                color:
                Colors.white.withOpacity(
                  0.075,
                ),
              ),
            ),
            child: Column(
              mainAxisSize:
              MainAxisSize.min,
              crossAxisAlignment:
              CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration:
                      BoxDecoration(
                        color:
                        _cyan.withOpacity(
                          0.08,
                        ),
                        borderRadius:
                        BorderRadius.circular(
                          12,
                        ),
                      ),
                      child:
                      const Icon(
                        Icons
                            .keyboard_outlined,
                        color:
                        _cyan,
                        size: 20,
                      ),
                    ),
                    const SizedBox(
                        width: 12),
                    Text(
                      'Keyboard shortcuts',
                      style:
                      GoogleFonts.poppins(
                        color:
                        _white,
                        fontSize:
                        15,
                        fontWeight:
                        FontWeight.w700,
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 20,
                ),

                ...shortcuts.map(
                      (shortcut) {
                    return Padding(
                      padding:
                      const EdgeInsets
                          .only(
                        bottom: 11,
                      ),
                      child: Row(
                        children: [
                          Container(
                            constraints:
                            const BoxConstraints(
                              minWidth: 82,
                            ),
                            padding:
                            const EdgeInsets
                                .symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration:
                            BoxDecoration(
                              color: Colors
                                  .white
                                  .withOpacity(
                                0.045,
                              ),
                              borderRadius:
                              BorderRadius
                                  .circular(
                                7,
                              ),
                              border:
                              Border.all(
                                color: Colors
                                    .white
                                    .withOpacity(
                                  0.06,
                                ),
                              ),
                            ),
                            child:
                            Text(
                              shortcut[0],
                              textAlign:
                              TextAlign
                                  .center,
                              style:
                              GoogleFonts
                                  .inter(
                                color:
                                _cyan,
                                fontSize:
                                8.5,
                                fontWeight:
                                FontWeight
                                    .w800,
                              ),
                            ),
                          ),
                          const SizedBox(
                              width: 13),
                          Expanded(
                            child:
                            Text(
                              shortcut[1],
                              style:
                              GoogleFonts
                                  .inter(
                                color:
                                _secondaryText,
                                fontSize:
                                10,
                                fontWeight:
                                FontWeight
                                    .w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(
                  height: 6,
                ),

                Align(
                  alignment:
                  Alignment.centerRight,
                  child:
                  TextButton(
                    onPressed:
                        () {
                      Navigator.pop(
                        context,
                      );
                    },
                    child:
                    Text(
                      'Close',
                      style:
                      GoogleFonts.inter(
                        color:
                        _cyan,
                        fontSize:
                        10,
                        fontWeight:
                        FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
