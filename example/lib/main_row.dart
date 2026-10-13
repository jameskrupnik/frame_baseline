part of 'main.dart';

class _Row extends StatelessWidget {
  const _Row({required this.index, required this.expensive});

  final int index;
  final bool expensive;

  @override
  Widget build(BuildContext context) {
    // Synchronous work on the UI thread during build — the classic cause of
    // build-side jank, and what `build.p90` / missedBuildBudgetCount detect.
    final tint = expensive ? _burnCpu(index) : 0.0;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Color.lerp(
          Colors.indigo.shade100,
          Colors.indigo.shade400,
          tint,
        ),
        child: Text('$index'),
      ),
      title: Text('Item $index'),
      subtitle: Text(expensive ? 'expensive row' : 'cheap row'),
    );
  }
}
