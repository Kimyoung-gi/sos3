import 'package:flutter/material.dart';

import 'no_glow_scroll_behavior.dart';

/// PC 웹에서 모바일 프레임(394×811) 안에서만 렌더링되도록 강제하는 쉘.
///
/// - **모바일(width <= 430)**: 프레임 미적용(전체 화면)
/// - **PC(width > 430)**: 중앙 고정 프레임(394×811) + 내부만 스크롤
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

  @override
  void dispose() {
    _primaryScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isMobile = width <= 430;

    if (isMobile) {
      return ScrollConfiguration(
        behavior: const NoGlowScrollBehavior(),
        child: widget.child,
      );
    }

    return ColoredBox(
      color: const Color(0xFFF6F7F9),
      child: Center(
        child: Container(
          width: 394,
          height: 811,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: const Color(0xFFE6E8EC),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.10),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: PrimaryScrollController(
              controller: _primaryScrollController,
              child: ScrollConfiguration(
                behavior: const NoGlowScrollBehavior(),
                // 스크롤바는 화면/플랫폼별 기본 동작에 맡김(선택 사항).
                // RawScrollbar를 강제하면 스크롤러가 없는 화면에서 assertion이 날 수 있어 제외.
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

