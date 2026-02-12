import 'package:flutter/material.dart';

/// KT B2B SaaS 스타일 페이지 메뉴 타이틀 (좌측 헤더용)
/// - Pretendard/맑은고딕 Bold, 20~22px, letterSpacing -0.3, #111111
/// - 아이콘·텍스트 간격 8px, 텍스트 하단 2px 레드 포인트 라인 (#E6002D)
/// - 상단 여백 12px, 좌측 여백 16px
class PageMenuTitle extends StatelessWidget {
  final IconData icon;
  final String label;

  const PageMenuTitle({
    super.key,
    required this.icon,
    required this.label,
  });

  static const Color _textColor = Color(0xFF111111);
  static const Color _redLine = Color(0xFFE6002D);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, left: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 18,
            color: _textColor,
          ),
          const SizedBox(width: 8),
          IntrinsicWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                    color: _textColor,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Container(
                  height: 2,
                  color: _redLine,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
