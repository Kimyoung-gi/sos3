import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/od_item.dart';
import '../../repositories/od_repository.dart';
import '../../services/csv_reload_bus.dart';
import '../theme/app_colors.dart';
import '../widgets/page_menu_title.dart';
import '../theme/app_dimens.dart';

/// OD(오디) 리스트 페이지 — 지역 검색, 카드형 목록, 주소(네이버지도)/상세링크/복사
class OdListPage extends StatefulWidget {
  const OdListPage({super.key});

  @override
  State<OdListPage> createState() => _OdListPageState();
}

class _OdListPageState extends State<OdListPage> {
  final OdRepository _repo = OdRepository();
  final TextEditingController _searchController = TextEditingController();

  List<OdItem> _all = [];
  List<OdItem> _filtered = [];
  bool _loading = true;
  String? _errorMessage;
  StreamSubscription<String>? _reloadSub;

  /// CSV 본부 기준: 전체 / 서울 / 경기 / 인천 / 강원 / 동부 / 서부
  static const List<String> _hqList = ['전체', '서울', '경기', '인천', '강원', '동부', '서부'];
  String? _selectedHq;

  @override
  void initState() {
    super.initState();
    _load();
    _searchController.addListener(_applyFilter);
    _reloadSub = CsvReloadBus().stream.listen((filename) {
      if (filename.toUpperCase().contains('OD')) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _reloadSub?.cancel();
    _searchController.removeListener(_applyFilter);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final list = await _repo.loadAll();
      if (!mounted) return;
      setState(() {
        _all = list;
        _loading = false;
      });
      _applyFilter();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _applyFilter() {
    final q = _searchController.text.trim().toLowerCase();
    setState(() {
      var list = _all;
      // 본부 필터 (CSV 본부 컬럼 기준: 서울/경기/인천/강원/동부/서부)
      if (_selectedHq != null && _selectedHq!.isNotEmpty) {
        list = list.where((o) {
          final hq = o.hq.trim();
          return hq == _selectedHq;
        }).toList();
      }
      // 지역 검색
      if (q.isNotEmpty) {
        list = list.where((o) {
          return o.region.toLowerCase().contains(q) ||
              o.hq.toLowerCase().contains(q) ||
              o.companyName.toLowerCase().contains(q) ||
              o.address.toLowerCase().contains(q);
        }).toList();
      }
      _filtered = list;
    });
  }

  Widget _regionChip(String label) {
    final isSelected = (label == '전체' && _selectedHq == null) || _selectedHq == label;
    return Material(
      color: isSelected ? AppColors.pillSelectedBg : AppColors.pillUnselectedBg,
      borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedHq = label == '전체' ? null : label;
          });
          _applyFilter();
        },
        borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : AppColors.pillUnselectedText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 1,
        automaticallyImplyLeading: false,
        leading: const PageMenuTitle(icon: Icons.work_outline_rounded, label: 'OD'),
        leadingWidth: 80,
        centerTitle: true,
        title: Image.asset(
          'assets/images/sos_logo.png',
          height: 28,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
        ),
        actions: const [SizedBox(width: 80)],
      ),
      body: Column(
        children: [
          // 지역 검색 (고객사 메뉴와 동일 스타일)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppDimens.pagePadding, 12, AppDimens.pagePadding, 8),
            child: Container(
              height: AppDimens.searchBarHeight,
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 15),
                decoration: InputDecoration(
                  hintText: '지역 검색',
                  hintStyle: TextStyle(color: AppColors.textSecondary),
                  prefixIcon: Icon(Icons.search, color: AppColors.textSecondary, size: 22),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
              ),
            ),
          ),
          // 지역(본부) 필터: 5*2 그리드 — 전체/서울/경기/인천/강원/동부/서부
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding),
            child: Column(
              children: [
                Row(
                  children: [
                    for (int i = 0; i < 5 && i < _hqList.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(
                        child: _regionChip(_hqList[i]),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (int i = 5; i < 5 + 5; i++) ...[
                      if (i > 5) const SizedBox(width: 8),
                      Expanded(
                        child: i < _hqList.length
                            ? _regionChip(_hqList[i])
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                            const SizedBox(height: 16),
                            Text(_errorMessage!, style: TextStyle(color: AppColors.textSecondary), textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            ElevatedButton(onPressed: _load, child: const Text('다시 시도')),
                          ],
                        ),
                      )
                    : _filtered.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.search_off, size: 64, color: AppColors.textSecondary),
                                const SizedBox(height: 16),
                                Text(
                                  '검색 결과가 없습니다.\n관리자에서 OD.CSV를 업로드해 주세요.',
                                  style: TextStyle(color: AppColors.textSecondary),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: AppDimens.pagePadding, vertical: 8),
                            itemCount: _filtered.length,
                            itemBuilder: (context, index) => _OdCard(item: _filtered[index]),
                          ),
          ),
        ],
      ),
    );
  }
}

/// OD 카드 — 고객사 메뉴 톤앤매너, 주소(네이버지도)/상세링크/복사
class _OdCard extends StatelessWidget {
  final OdItem item;

  const _OdCard({required this.item});

  Future<void> _openNaverMap(BuildContext context, String address) async {
    if (address.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('주소가 없습니다.')));
      return;
    }
    final uri = Uri.parse('https://map.naver.com/v5/search/${Uri.encodeComponent(address)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('지도를 열 수 없습니다.')));
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('오류: $e')));
      }
    }
  }

  /// 링크 문자열 유효 여부 (BOM·제어문자 제거 후 비어있지 않으면 true)
  bool _isLinkValid(String link) {
    return link.trim().replaceAll(RegExp(r'[\uFEFF\u200B-\u200D\u2060]'), '').isNotEmpty;
  }

  /// 상세링크: CSV "링크" 컬럼 값만 사용. 다른 URL 연동 금지.
  Future<void> _openDetailLink(BuildContext context, String link) async {
    final trimmed = link
        .trim()
        .replaceAll(RegExp(r'[\uFEFF\u200B-\u200D\u2060]'), '')
        .replaceAll(RegExp(r'[\r\n\t]'), '');
    if (trimmed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('상세 링크가 없습니다.')));
      return;
    }
    // 스킴 없으면 https 추가 (알바몬 등 www.albamon.com 형태 대응)
    final urlStr = trimmed.contains(RegExp(r'^https?://')) ? trimmed : 'https://$trimmed';
    Uri? uri = Uri.tryParse(urlStr);
    if (uri == null || uri.scheme.isEmpty) {
      uri = Uri.tryParse('https://$trimmed');
    }
    if (uri == null || !uri.isAbsolute) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('올바른 링크가 아닙니다.')));
      }
      return;
    }
    try {
      // 외부 브라우저로 열기: 알바몬 등 채용 사이트가 인앱/WebView에서 막히는 경우 방지
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
      if (!launched && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다. 브라우저를 확인해 주세요.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('링크를 열 수 없습니다: $e')));
      }
    }
  }

  /// 연락처 숫자에 읽기 쉽도록 간격 추가 (예: 01012345678 → 010 1234 5678)
  String _formatContactSpacing(String contact) {
    final digits = contact.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.length >= 9 && digits.length <= 11) {
      if (digits.startsWith('010')) {
        return '${digits.substring(0, 3)} ${digits.substring(3, 7)} ${digits.substring(7)}';
      }
      if (digits.startsWith('02') && digits.length == 9) {
        return '${digits.substring(0, 2)} ${digits.substring(2, 5)} ${digits.substring(5)}';
      }
      if (digits.startsWith('02') && digits.length == 10) {
        return '${digits.substring(0, 2)} ${digits.substring(2, 6)} ${digits.substring(6)}';
      }
      return digits.split('').asMap().entries.map((e) => (e.key > 0 && e.key % 4 == 0) ? ' ${e.value}' : e.value).join();
    }
    return contact;
  }

  static String _emptyToNone(String s) => s.trim().isEmpty ? '없음' : s.trim();

  void _copyToClipboard(BuildContext context) {
    final sb = StringBuffer();
    sb.writeln(_emptyToNone(item.companyName));
    sb.writeln('사이트명: ${_emptyToNone(item.siteName)}');
    sb.writeln('직무: ${_emptyToNone(item.jobTitle)}');
    sb.writeln('일정: ${_emptyToNone(item.schedule)}');
    sb.writeln('업종: ${_emptyToNone(item.industry)}');
    sb.writeln('연락처: ${_emptyToNone(item.contact)}');
    sb.writeln('주소: ${_emptyToNone(item.address)}');
    sb.writeln('링크: ${_emptyToNone(item.link)}');
    if (item.region.isNotEmpty || item.hq.isNotEmpty) {
      sb.writeln('지역: ${_emptyToNone(item.region)}');
      sb.writeln('본부: ${_emptyToNone(item.hq)}');
    }
    Clipboard.setData(ClipboardData(text: sb.toString()));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('복사되었습니다.')));
  }

  @override
  Widget build(BuildContext context) {
    // 상세링크 클로저에서 올바른 값 캡처 (전체 보기 등에서 동작 보장)
    final linkValue = item.link;
    final hasLink = _isLinkValid(linkValue);
    return Container(
      margin: const EdgeInsets.only(bottom: AppDimens.cardSpacing),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[300]!, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 상단: 고객사와 동일 빨간 아이콘 + 회사명 + 복사하기(우측)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.store_outlined, size: 20, color: AppColors.customerRed),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.companyName.trim().isEmpty ? '없음' : item.companyName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                // 복사하기 버튼 상단 오른쪽
                FilledButton.icon(
                  onPressed: () => _copyToClipboard(context),
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white),
                  label: const Text(
                    '복사하기',
                    style: TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.customerRed,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppDimens.filterPillRadius),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _row('사이트명', item.siteName),
            _row('직무', item.jobTitle),
            _row('일정', item.schedule),
            _row('업종', item.industry),
            _row('연락처', item.contact.trim().isEmpty ? '없음' : _formatContactSpacing(item.contact)),
            _row('주소', item.address),
            // 주소는 아래 버튼으로 네이버 지도 연동
            const SizedBox(height: 12),
            // 주소(지도) / 상세링크 — 고객 메뉴 전화·문자처럼 표현
            Row(
              children: [
                // 주소(지도): 빨간 FilledButton
                FilledButton.icon(
                  onPressed: item.address.trim().isEmpty
                      ? null
                      : () => _openNaverMap(context, item.address),
                  icon: Icon(
                    Icons.location_on_outlined,
                    size: 18,
                    color: item.address.trim().isEmpty ? Colors.grey : Colors.white,
                  ),
                  label: Text(
                    '주소',
                    style: TextStyle(
                      fontSize: 13,
                      color: item.address.trim().isEmpty ? Colors.grey : Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.customerRed,
                    disabledBackgroundColor: AppColors.pillUnselectedBg,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    minimumSize: const Size(0, 36),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 상세링크: 주소 버튼과 동일 높이(36), 마우스 오버 시 손가락 커서
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openDetailLink(context, linkValue),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: hasLink ? AppColors.border : Colors.grey.shade300,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      constraints: const BoxConstraints(minHeight: 36, minWidth: 100),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.open_in_new,
                            size: 18,
                            color: hasLink ? AppColors.textSecondary : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '상세링크',
                            style: TextStyle(
                              fontSize: 13,
                              color: hasLink ? AppColors.textSecondary : Colors.grey,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 데이터 비어있으면 "없음" 표시 (모든 채용사이트 동일 원칙)
  Widget _row(String label, String value) {
    final display = value.trim().isEmpty ? '없음' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.35),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            TextSpan(text: display, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
