import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';

/// Shared layout of app/terms/page.tsx and app/privacy/page.tsx
class _LegalPage extends StatelessWidget {
  final String ns;
  final List<Widget> Function(BuildContext) sections;
  const _LegalPage({required this.ns, required this.sections});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 24, 24, 128), children: [
            GestureDetector(
              onTap: () => Navigator.of(context).maybePop(),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.arrow_back, size: 14, color: Tw.fuchsia500),
                const SizedBox(width: 8),
                Label(context.t('$ns.back'), color: Tw.fuchsia500),
              ]),
            ),
            const SizedBox(height: 16),
            ShaderMask(
              shaderCallback: (r) => const LinearGradient(colors: [Tw.white, Tw.slate500]).createShader(r),
              child: Text(context.t('$ns.title'), style: tw(36, weight: black, tracking: -0.025, height: 1.1)),
            ),
            const SizedBox(height: 16),
            Text(context.t('$ns.lastUpdated'), style: tw(14, color: Tw.slate500)),
            const SizedBox(height: 48),
            ...sections(context),
            const SizedBox(height: 48),
            Divider(color: Tw.w(0.05)),
            const SizedBox(height: 48),
            Label(context.t('$ns.footer'), color: Tw.slate500, tracking: 0.2, align: TextAlign.center),
          ]),
        ),
      );
}

Widget _section(BuildContext context, String title, List<Widget> body) => Padding(
      padding: const EdgeInsets.only(bottom: 40),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Tw.w(0.05)))),
          child: Label(title, size: 20, color: Tw.white, tracking: 0.05),
        ),
        const SizedBox(height: 16),
        ...body,
      ]),
    );

Widget _p(String text) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(text, style: tw(16, color: Tw.slate300, height: 1.6)));

Widget _li(InlineSpan span) => Padding(
      padding: const EdgeInsets.only(left: 12, bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('•  ', style: tw(16, color: Tw.slate300, height: 1.6)),
        Expanded(child: Text.rich(span, style: tw(16, color: Tw.slate300, height: 1.6))),
      ]),
    );

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) => _LegalPage(
        ns: 'terms',
        sections: (c) => [
          for (final n in [1, 2]) _section(c, c.t('terms.section$n.title'), [_p(c.t('terms.section$n.p1'))]),
          _section(c, c.t('terms.section3.title'), [
            _p(c.t('terms.section3.p1')),
            for (final i in [1, 2, 3, 4]) _li(TextSpan(text: c.t('terms.section3.li$i'))),
          ]),
          for (final n in [4, 5, 6]) _section(c, c.t('terms.section$n.title'), [_p(c.t('terms.section$n.p1'))]),
        ],
      );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  @override
  Widget build(BuildContext context) => _LegalPage(
        ns: 'privacy',
        sections: (c) => [
          _section(c, c.t('privacy.section1.title'), [
            _p(c.t('privacy.section1.p1')),
            for (final i in [1, 2, 3, 4])
              _li(TextSpan(children: [
                TextSpan(text: c.t('privacy.section1.li$i.strong'), style: tw(16, weight: bold, color: Tw.slate300)),
                TextSpan(text: ' ${c.t('privacy.section1.li$i.text')}'),
              ])),
          ]),
          _section(c, c.t('privacy.section2.title'), [
            _p(c.t('privacy.section2.p1')),
            for (final i in [1, 2, 3, 4]) _li(TextSpan(text: c.t('privacy.section2.li$i'))),
          ]),
          for (final n in [3, 4, 5, 6]) _section(c, c.t('privacy.section$n.title'), [_p(c.t('privacy.section$n.p1'))]),
        ],
      );
}

/// Port of app/rules/page.tsx
class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final rules = [
      ('01', 'rules.rule1', Icons.favorite, const [Tw.pink500, Color(0xFFF43F5E)]),
      ('02', 'rules.rule2', Icons.verified, const [Tw.fuchsia500, Tw.purple500]),
      ('03', 'rules.rule3', Icons.visibility_off, const [Tw.purple500, Tw.indigo500]),
      ('04', 'rules.rule4', Icons.security, const [Tw.indigo500, Tw.blue500]),
    ];
    return Scaffold(
      body: SafeArea(
        child: ListView(padding: const EdgeInsets.all(32), children: [
          Row(children: [
            Pressable(
              onTap: () => Navigator.of(context).maybePop(),
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(16), border: Border.all(color: Tw.w(0.1))),
                child: const Icon(Icons.chevron_left),
              ),
            ),
            Expanded(
              child: Center(
                child: ShaderMask(
                  shaderCallback: (r) => const LinearGradient(colors: [Tw.fuchsia500, Tw.indigo500]).createShader(r),
                  child: Label(context.t('rules.title'), size: 18, color: Tw.white, tracking: 0.3),
                ),
              ),
            ),
            const SizedBox(width: 48),
          ]),
          const SizedBox(height: 40),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: '${context.t('rules.header1')}\n'),
              TextSpan(text: context.t('rules.header2'), style: tw(46, weight: black, color: Tw.slate500, tracking: -0.05, height: 1)),
            ]),
            textAlign: TextAlign.center,
            style: tw(46, weight: black, tracking: -0.05, height: 1),
          ),
          const SizedBox(height: 24),
          Text(context.t('rules.subtitle'), textAlign: TextAlign.center, style: tw(16, weight: medium, color: Tw.slate400)),
          const SizedBox(height: 64),
          for (final r in rules) ...[
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: Tw.w(0.05), borderRadius: BorderRadius.circular(48), border: Border.all(color: Tw.w(0.1))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Container(height: 4, decoration: BoxDecoration(gradient: LinearGradient(colors: r.$4))),
                Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: r.$4),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Icon(r.$3, size: 30, color: Tw.white),
                      ),
                      const Spacer(),
                      Text(r.$1, style: tw(36, weight: black, color: Tw.w(0.05), tracking: -0.05)),
                    ]),
                    const SizedBox(height: 32),
                    Label(context.t('${r.$2}.title'), size: 24, color: Tw.white, tracking: -0.025),
                    const SizedBox(height: 16),
                    Text(context.t('${r.$2}.desc'), style: tw(14, weight: medium, color: Tw.slate400, height: 1.6)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 32),
          ],
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Tw.fuchsia600.withValues(alpha: 0.2), Tw.indigo600.withValues(alpha: 0.2)],
              ),
              borderRadius: BorderRadius.circular(32),
              border: Border.all(color: Tw.w(0.1)),
            ),
            child: Column(children: [
              Text(context.t('rules.report_title'), textAlign: TextAlign.center, style: tw(30, weight: black, tracking: -0.025)),
              const SizedBox(height: 24),
              Text(context.t('rules.report_desc'), textAlign: TextAlign.center, style: tw(16, weight: medium, color: Tw.slate300)),
              const SizedBox(height: 32),
              Pressable(
                onTap: () => Navigator.of(context).popUntil((r) => r.isFirst),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  decoration: BoxDecoration(color: Tw.white, borderRadius: BorderRadius.circular(99)),
                  child: Label(context.t('rules.accept_btn'), size: 12, color: Tw.black, tracking: 0.3),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 64),
          Label(context.t('rules.footer'), weight: medium, color: Tw.slate700, tracking: 0.2, align: TextAlign.center),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }
}
