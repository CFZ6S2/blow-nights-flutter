import 'package:flutter/material.dart';

import '../../i18n/i18n.dart';
import '../../navigation.dart';
import '../../theme/app_theme.dart';
import '../../widgets/chill_form.dart';
import '../../widgets/common.dart';

/// Port of app/create-plan/page.tsx
class CreatePlanScreen extends StatelessWidget {
  const CreatePlanScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.fromLTRB(24, 40, 24, 128), children: [
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Tw.w(0.05), border: Border.all(color: Tw.w(0.1))),
                  child: const Icon(Icons.arrow_back, color: Tw.white),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(context.t('create_plan.title', fallback: 'Crear plan'), style: tw(20, weight: black)),
                  Text(context.t('create_plan.subtitle', fallback: 'Organiza una quedada, previa o fiesta'), style: tw(12, color: Tw.slate500)),
                ]),
              ),
            ]),
            const SizedBox(height: 24),
            ChillForm(
              page: true,
              onCreated: (id) => openRoute(context, AppRoute.planManage, args: {'id': id}, replace: true),
            ),
          ]),
        ),
      );
}
