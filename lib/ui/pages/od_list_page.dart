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

  Future<void> _openDetailLink(BuildContext context, String link) async {
    // BOM·공백·제어문자 제거 (CSV 파싱/알바몬 등 외부 링크 연동 안정화)
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

  void _copyToClipboard(BuildContext context) {
    final sb = StringBuffer();
    sb.writeln(item.companyName);
    if (item.siteName.isNotEmpty) sb.writeln('사이트명: ${item.siteName}');
    if (item.jobTitle.isNotEmpty) sb.writeln('직무: ${item.jobTitle}');
    if (item.schedule.isNotEmpty) sb.writeln('채용일정: ${item.schedule}');
    if (item.address.isNotEmpty) sb.writeln('주소: ${item.address}');
    if (item.industry.isNotEmpty) sb.writeln('업종: ${item.industry}');
    if (item.contact.isNotEmpty) sb.writeln('연락처: ${item.contact}');
    if (item.link.isNotEmpty) sb.writeln('링크: ${item.link}');
    if (item.region.isNotEmpty) sb.writeln('지역: ${item.region}');
    if (item.hq.isNotEmpty) sb.writeln('본부: ${item.hq}');
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
                    item.companyName.isEmpty ? '-' : item.companyName,
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
            _row('채용일정', item.schedule),
            _row('업종', item.industry),
            _row('연락처', item.contact.isEmpty ? '연락처 없음' : _formatContactSpacing(item.contact)),
            // 주소: "주소: 서울시 송파구 오금로~~" 형식으로 풀 주소 한 줄 표시 (연동 없음, 텍스트만)
            if (item.address.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              RichText(
                text: TextSpan(
                  style: const TextStyle(fontSize: 13, height: 1.3),
                  children: [
                    const TextSpan(
                      text: '주소: ',
                      style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                    TextSpan(
                      text: item.address.trim(),
                      style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w400),
                    ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
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
                // 상세링크: 클릭 확실히 전달되도록 GestureDetector + 넓은 터치 영역
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _openDetailLink(context, linkValue),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: hasLink ? AppColors.border : Colors.grey.shade300,
                      ),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    constraints: const BoxConstraints(minHeight: 40, minWidth: 100),
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
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, height: 1.35),
          children: [
            TextSpan(text: '$label: ', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            TextSpan(text: value, style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
