import 'package:flutter/material.dart';

/// 오버스크롤(글로우/바운스) 효과를 제거하는 ScrollBehavior
///
/// - 관리자 사이트는 "변경하지 않는다" 요구가 있으므로,
///   이 behavior는 `FrameShell` 내부(비관리자 영역)에서만 사용한다.
class NoGlowScrollBehavior extends ScrollBehavior {
  const NoGlowScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

