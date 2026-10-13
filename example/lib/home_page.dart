part of 'main.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('frame_baseline demo'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Smooth'),
              Tab(key: jankyTabKey, text: 'Janky'),
            ],
          ),
        ),
        body: const TabBarView(
          physics: NeverScrollableScrollPhysics(),
          children: [
            _ItemList(key: smoothListKey, expensive: false),
            _ItemList(key: jankyListKey, expensive: true),
          ],
        ),
      ),
    );
  }
}
