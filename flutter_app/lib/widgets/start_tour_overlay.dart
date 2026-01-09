import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Full-screen overlay with a big purple START TOUR button
/// Shows when awaiting visitor at start location
/// Optional webpage background (defaults to frontiertower.io)
class StartTourOverlay extends StatefulWidget {
  final String buttonText;
  final String? displayUrl;
  final VoidCallback onStart;

  const StartTourOverlay({
    super.key,
    required this.buttonText,
    this.displayUrl,
    required this.onStart,
  });

  @override
  State<StartTourOverlay> createState() => _StartTourOverlayState();
}

class _StartTourOverlayState extends State<StartTourOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  WebViewController? _webController;

  @override
  void initState() {
    super.initState();
    // Gentle pulse animation on the button
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Setup webview if URL provided
    final url = widget.displayUrl ?? 'https://frontiertower.io';
    _webController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(url));
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Background - webpage or solid color
          if (_webController != null)
            Positioned.fill(
              child: WebViewWidget(controller: _webController!),
            )
          else
            Container(color: Colors.black87),

          // Semi-transparent overlay to make button pop
          Positioned.fill(
            child: Container(
              color: Colors.black.withValues(alpha: 0.3),
            ),
          ),

          // Centered big purple button - Office Depot "That was easy" style
          Center(
            child: ScaleTransition(
              scale: _pulseAnimation,
              child: GestureDetector(
                onTap: widget.onStart,
                child: Container(
                  width: 280,
                  height: 280,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const RadialGradient(
                      colors: [
                        Color(0xFF9C27B0), // Purple 500
                        Color(0xFF7B1FA2), // Purple 700
                        Color(0xFF4A148C), // Purple 900
                      ],
                      stops: [0.0, 0.7, 1.0],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.purple.withValues(alpha: 0.6),
                        blurRadius: 30,
                        spreadRadius: 5,
                      ),
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.4),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 4,
                    ),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 64,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          widget.buttonText,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                            shadows: [
                              Shadow(
                                color: Colors.black54,
                                blurRadius: 4,
                                offset: Offset(2, 2),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Tap anywhere hint at bottom
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Text(
              'Tap the button to begin',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.7),
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
