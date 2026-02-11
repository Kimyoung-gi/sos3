/// OD(오디) 메뉴 항목 — CSV 컬럼: 사이트명, 회사명, 직무, 일정, 주소, 업종, 연락처, 링크, 지역, 본부
class OdItem {
  final String siteName;
  final String companyName;
  final String jobTitle;
  final String schedule;
  final String address;
  final String industry;
  final String contact;
  final String link;
  final String region;
  final String hq;

  const OdItem({
    this.siteName = '',
    this.companyName = '',
    this.jobTitle = '',
    this.schedule = '',
    this.address = '',
    this.industry = '',
    this.contact = '',
    this.link = '',
    this.region = '',
    this.hq = '',
  });

  Map<String, dynamic> toJson() => {
        'siteName': siteName,
        'companyName': companyName,
        'jobTitle': jobTitle,
        'schedule': schedule,
        'address': address,
        'industry': industry,
        'contact': contact,
        'link': link,
        'region': region,
        'hq': hq,
      };

  factory OdItem.fromJson(Map<String, dynamic> j) => OdItem(
        siteName: j['siteName'] as String? ?? '',
        companyName: j['companyName'] as String? ?? '',
        jobTitle: j['jobTitle'] as String? ?? '',
        schedule: j['schedule'] as String? ?? '',
        address: j['address'] as String? ?? '',
        industry: j['industry'] as String? ?? '',
        contact: j['contact'] as String? ?? '',
        link: j['link'] as String? ?? '',
        region: j['region'] as String? ?? '',
        hq: j['hq'] as String? ?? '',
      );
}
