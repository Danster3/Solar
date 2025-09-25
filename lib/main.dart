import 'package:flutter/material.dart';
import 'sems_client.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Demo',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // TRY THIS: Try running your application with "flutter run". You'll see
        // the application has a purple toolbar. Then, without quitting the app,
        // try changing the seedColor in the colorScheme below to Colors.green
        // and then invoke "hot reload" (save your changes or press the "hot
        // reload" button in a Flutter-supported IDE, or press "r" if you used
        // the command line to start the app).
        //
        // Notice that the counter didn't reset back to zero; the application
        // state is not lost during the reload. To reset the state, use hot
        // restart instead.
        //
        // This works for code too, not just values: Most code changes can be
        // tested with just a hot reload.
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const MyHomePage(title: 'Flutter Demo Home Page'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0;
  String _status = 'idle';
  double _currentPower = 0.0;
  double _consumption = 0.0;
  double _todayKwh = 0.0;
  late final SemsClient _semsClient;

  // removed sample counter; app shows SEMS data instead
  

  Future<void> _fetchSems() async {
    setState(() {
      _status = 'logging in...';
    });
    // Use shared SemsClient instance (created at init)
    final client = _semsClient;
    try {
      final today = DateTime.now();
      final date = '${today.year.toString().padLeft(4,'0')}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';
      final data = await client.fetchPlantPowerChart('58faee60-cc86-4de8-ad3d-575dc3e8c01e', date);
      setState(() {
        _currentPower = (data['current_pv_w'] as double?) ?? 0.0;
        _consumption = (data['current_load_w'] as double?) ?? 0.0;
        _todayKwh = (data['today_kwh'] as double?) ?? 0.0;
        _status = 'ok';
      });
    } catch (e) {
      setState(() {
        _status = 'error: $e';
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // Create SemsClient with hard-coded credentials for test mode
    _semsClient = SemsClient(email: 'daniel.forbes.96@hotmail.com', password: 'Goodwe2018');
    // Attempt to load persisted token from secure storage so the app won't re-login on first fetch
    _semsClient.loadPersistedTokenForApp().then((_) {
      setState(() {
        _status = 'ready (token loaded)';
      });
    }).catchError((e) {
      // ignore load errors; app will login when needed
      setState(() {
        _status = 'ready';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(
        // TRY THIS: Try changing the color here to a specific color (to
        // Colors.amber, perhaps?) and trigger a hot reload to see the AppBar
        // change color while the other colors stay the same.
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        // Here we take the value from the MyHomePage object that was created by
        // the App.build method, and use it to set our appbar title.
        title: Text(widget.title),
      ),
      body: Center(
        // Center is a layout widget. It takes a single child and positions it
        // in the middle of the parent.
        child: Column(
          // Column is also a layout widget. It takes a list of children and
          // arranges them vertically. By default, it sizes itself to fit its
          // children horizontally, and tries to be as tall as its parent.
          //
          // Column has various properties to control how it sizes itself and
          // how it positions its children. Here we use mainAxisAlignment to
          // center the children vertically; the main axis here is the vertical
          // axis because Columns are vertical (the cross axis would be
          // horizontal).
          //
          // TRY THIS: Invoke "debug painting" (choose the "Toggle Debug Paint"
          // action in the IDE, or press "p" in the console), to see the
          // wireframe for each widget.
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Text('Live SEMS data (hard-coded creds for test)'),
            const SizedBox(height: 8),
            Text('Status: $_status'),
            const SizedBox(height: 8),
            Text('Current generation (W): ${_currentPower.toStringAsFixed(1)}'),
            Text('Current consumption (W): ${_consumption.toStringAsFixed(1)}'),
            Text('Today total (kWh): ${_todayKwh.toStringAsFixed(3)}'),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _fetchSems, child: const Text('Fetch SEMS')),
          ],
        ),
      ),
  // no floating action button for this test app
    );
  }
}
