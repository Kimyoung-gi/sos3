import 'package:flutter/material.dart';

import 'no_glow_scroll_behavior.dart';

/// PC(1024px 이상)에서만 중앙 모바일형 컨테이너 + 배경을 적용하는 쉘.
///
/// - **모바일(width < 1024)**: 전체 화면 그대로 사용
/// - **PC(width >= 1024)**: 배경 + 중앙 고정폭 컨테이너(430×100vh, 흰색, 둥근 모서리, 그림자)
class FrameShell extends StatefulWidget {
  final Widget child;

  const FrameShell({
    super.key,
    required this.child,
  });

  @override
  State<FrameShell> createState() => _FrameShellState();
}

class _FrameShellState extends State<FrameShell> {
  final ScrollController _primaryScrollController = ScrollController();

  static const double _pcBreakpoint = 1024;
  static const double _containerWidth = 430;
  static const double _containerRadius = 24;

  @override
  void dispose() {
    _primaryScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final height = MediaQuery.of(context).size.height;
    final isPc = width >= _pcBreakpoint;

    if (!isPc) {
      return ScrollConfiguration(
        behavior: const NoGlowScrollBehavior(),
        child: widget.child,
      );
    }

    // PC: 배경 이미지(assets/images/PCwide.png) + 중앙 모바일 컨테이너
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        image: DecorationImage(
          image: AssetImage('assets/images/PCwide.png'),
          fit: BoxFit.cover,
        ),
      ),
      child: Center(
        child: Container(
          width: _containerWidth,
          height: height,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_containerRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.12),
                blurRadius: 32,
                offset: const Offset(0, 12),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(_containerRadius),
            child: PrimaryScrollController(
              controller: _primaryScrollController,
              child: ScrollConfiguration(
                behavior: const NoGlowScrollBehavior(),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

