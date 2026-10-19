import 'package:flutter/material.dart';

import '../widgets.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: MessageView(
        icon: Icons.storefront_outlined,
        title: 'Ouvrez le lien de la boutique',
        message:
            'Chaque boutique a sa propre adresse. Scannez son code QR ou ouvrez le lien qu\'elle vous a envoyé.',
      ),
    );
  }
}
