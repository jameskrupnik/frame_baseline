part of 'main.dart';

class _ItemList extends StatelessWidget {
  const _ItemList({super.key, required this.expensive});

  /// When true each row burns CPU during build, producing real UI-thread jank.
  final bool expensive;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 500,
      itemBuilder: (context, index) => _Row(index: index, expensive: expensive),
    );
  }
}
