import 'package:flutter/material.dart';

class SearchPage extends StatelessWidget {
  const SearchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset('assets/images/search.png', fit: BoxFit.cover),
            Column(
              children: const [
                SizedBox(height: 16),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Buscar',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                SizedBox(height: 12),
                SizedBox(height: 260, child: EducationCarouselSection()),
              ],
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: IgnorePointer(
                child: Container(
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withOpacity(0.4),
                        Colors.black.withOpacity(0.8),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class EducationCarouselSection extends StatefulWidget {
  const EducationCarouselSection({super.key});

  @override
  State<EducationCarouselSection> createState() => _EducationCarouselSectionState();
}

class _EducationCarouselSectionState extends State<EducationCarouselSection> {
  final PageController _controller = PageController(viewportFraction: 0.88);
  int _index = 0;

  static final List<_EducationCardData> _cards = <_EducationCardData>[
    _EducationCardData(
      title: 'RA y Dec (Ascensión recta y Declinación)',
      icon: Icons.my_location,
      text:
          'Coordenadas celestes fijas sobre la esfera celeste. La RA es análoga a la longitud y la Dec a la latitud. No dependen del lugar del observador.',
    ),
    _EducationCardData(
      title: 'Altitud y Azimut',
      icon: Icons.explore,
      text:
          'Sistema local del observador. Altitud mide la altura sobre el horizonte (0° a 90°) y Azimut el ángulo respecto al Norte (0°=N, 90°=E).',
    ),
    _EducationCardData(
      title: 'Fases lunares',
      icon: Icons.brightness_2,
      text:
          'La fracción iluminada de la Luna cambia conforme su posición respecto al Sol y la Tierra: nueva, creciente, llena y menguante.',
    ),
    _EducationCardData(
      title: 'Eclipses',
      icon: Icons.brightness_3,
      text:
          'Ocurren cuando el Sol, la Tierra y la Luna se alinean: eclipse solar (la Luna tapa al Sol) y lunar (la Tierra proyecta sombra sobre la Luna).',
    ),
    _EducationCardData(
      title: 'Magnitud aparente',
      icon: Icons.star,
      text:
          'Medida del brillo observado: menor magnitud = más brillo (magnitudes negativas son muy brillantes). Depende de distancia y luminosidad.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0),
          child: Row(
            children: const [
              Text('Aprende astronomía', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: PageView.builder(
            controller: _controller,
            itemCount: _cards.length,
            onPageChanged: (int i) => setState(() => _index = i),
            itemBuilder: (context, i) => _EducationCard(card: _cards[i]),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List<Widget>.generate(_cards.length, (int i) {
            final bool active = i == _index;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: active ? 22 : 8,
              height: 8,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF33FFE6) : const Color(0x55FFFFFF),
                borderRadius: BorderRadius.circular(8),
              ),
            );
          }),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _EducationCardData {
  _EducationCardData({required this.title, required this.icon, required this.text});

  final String title;
  final IconData icon;
  final String text;
}

class _EducationCard extends StatelessWidget {
  const _EducationCard({required this.card});

  final _EducationCardData card;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C1C),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0x22FFFFFF)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 8, offset: const Offset(0, 2)),
          ],
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF2A2A2A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(card.icon, color: const Color(0xFF33FFE6), size: 36),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    card.title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    card.text,
                    style: const TextStyle(color: Colors.white70, height: 1.25),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

