// lib/main.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const PocketSimApp());

class PocketSimApp extends StatefulWidget {
  const PocketSimApp({super.key});
  @override
  State<PocketSimApp> createState() => _PocketSimAppState();
}

class _PocketSimAppState extends State<PocketSimApp> {
  ThemeMode themeMode = ThemeMode.dark;
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pocket Option Simulator',
      themeMode: themeMode,
      theme: ThemeData.light().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark().copyWith(useMaterial3: true),
      home: TradingSimPage(onToggleTheme: () {
        setState(() {
          themeMode = themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
        });
      }),
      debugShowCheckedModeBanner: false,
    );
  }
}

class TradingSimPage extends StatefulWidget {
  final VoidCallback onToggleTheme;
  const TradingSimPage({super.key, required this.onToggleTheme});
  @override
  State<TradingSimPage> createState() => _TradingSimPageState();
}

class _TradingSimPageState extends State<TradingSimPage> {
  bool running = false;
  double? lastPrice;
  final List<double> closes = [];
  final List<DateTime> times = [];
  String signal = '—';
  String lastUpdate = '';
  Timer? timer;
  final List<Map<String, dynamic>> history = []; // سجل لحفظه في CSV

  // إعدادات
  final String symbolEndpoint = 'EURUSD=X';
  final int fetchIntervalSec = 30;
  final int maxPoints = 200;

  Future<double?> fetchPrice() async {
    try {
      final uri = Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/$symbolEndpoint?interval=1m&range=1d');
      final res = await http.get(uri);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final close =
            data['chart']['result'][0]['indicators']['quote'][0]['close'];
        // اختر آخر قيمة غير null
        dynamic last;
        for (int i = close.length - 1; i >= 0; i--) {
          if (close[i] != null) {
            last = close[i];
            break;
          }
        }
        if (last != null) return (last as num).toDouble();
      }
    } catch (e) {
      // الصمت هنا — سنعرض إشعارًا عند فشل متكرر
    }
    return null;
  }

  double ema(List<double> values, int period) {
    if (values.isEmpty) return 0.0;
    if (values.length < period) return values.last;
    final k = 2 / (period + 1);
    double emaVal = values.sublist(0, period).reduce((a, b) => a + b) / period;
    for (var i = period; i < values.length; i++) {
      emaVal = values[i] * k + emaVal * (1 - k);
    }
    return emaVal;
  }

  void evaluateSignal() {
    if (closes.length < 22) return;
    final emaShort = ema(closes, 8);
    final emaLong = ema(closes, 21);
    String newSig = signal;
    if (emaShort > emaLong) newSig = 'CALL';
    if (emaShort < emaLong) newSig = 'PUT';
    if (newSig != signal) {
      setState(() => signal = newSig);
      // أضف إلى التاريخ مع الطابع الزمني
      history.add({
        'time': DateTime.now().toIso8601String(),
        'price': lastPrice,
        'signal': signal,
      });
    }
  }

  Future<void> update() async {
    final price = await fetchPrice();
    if (price == null) {
      // فشل في الجلب — لا تغيّر الحالة كثيرًا لتفادي الوميض
      return;
    }
    setState(() {
      lastPrice = price;
      closes.add(price);
      times.add(DateTime.now());
      if (closes.length > maxPoints) {
        closes.removeAt(0);
        times.removeAt(0);
      }
      lastUpdate = DateFormat.Hms().format(DateTime.now());
    });
    evaluateSignal();
  }

  void startSim() {
    timer?.cancel();
    update();
    timer = Timer.periodic(Duration(seconds: fetchIntervalSec), (_) => update());
    setState(() => running = true);
  }

  void stopSim() {
    timer?.cancel();
    setState(() => running = false);
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  // ================= CSV Save =================
  Future<String?> _getAppDirPath() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      return dir.path;
    } catch (e) {
      return null;
    }
  }

  Future<bool> _requestPermissionIfNeeded() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (!status.isGranted) {
        final res = await Permission.storage.request();
        return res.isGranted;
      }
    }
    return true;
  }

  Future<void> saveHistoryAsCsv() async {
    if (history.isEmpty) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('لا توجد بيانات للحفظ')));
      return;
    }
    final ok = await _requestPermissionIfNeeded();
    if (!ok) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('مطلوب إذن التخزين')));
      return;
    }

    final dirPath = await _getAppDirPath();
    if (dirPath == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('فشل الحصول على مجلد التطبيق')));
      return;
    }

    final fileName = 'pocket_sim_history_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    final file = File('$dirPath/$fileName');
    final sb = StringBuffer();
    sb.writeln('time,price,signal');
    for (var row in history) {
      sb.writeln('${row['time']},${row['price']},${row['signal']}');
    }
    await file.writeAsString(sb.toString());
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم الحفظ: $fileName')));
  }

  // ================= Chart Data =================
  List<FlSpot> _priceSpots() {
    final spots = <FlSpot>[];
    for (int i = 0; i < closes.length; i++) {
      spots.add(FlSpot(i.toDouble(), closes[i]));
    }
    return spots;
  }

  List<FlSpot> _emaSpots(int period) {
    final spots = <FlSpot>[];
    for (int i = 0; i < closes.length; i++) {
      final sub = closes.sublist(0, i + 1);
      final val = ema(sub, period);
      spots.add(FlSpot(i.toDouble(), val));
    }
    return spots;
  }

  double _minY() {
    if (closes.isEmpty) return 0;
    final minP = closes.reduce((a, b) => a < b ? a : b);
    return minP * 0.999;
  }

  double _maxY() {
    if (closes.isEmpty) return 0;
    final maxP = closes.reduce((a, b) => a > b ? a : b);
    return maxP * 1.001;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final priceText = lastPrice != null ? lastPrice!.toStringAsFixed(5) : '—';
    final colorSignal = signal == 'CALL' ? Colors.greenAccent : signal == 'PUT' ? Colors.redAccent : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pocket Option Simulator'),
        actions: [
          IconButton(
            tooltip: 'تبديل الوضع الليلي/النهاري',
            icon: const Icon(Icons.brightness_6),
            onPressed: widget.onToggleTheme,
          ),
          IconButton(
            tooltip: 'حفظ السجل CSV',
            icon: const Icon(Icons.save),
            onPressed: saveHistoryAsCsv,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(children: [
              Expanded(child: Text('EUR/USD', style: theme.textTheme.headlineSmall)),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(priceText, style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                  Text('آخر تحديث: $lastUpdate', style: theme.textTheme.bodySmall),
                ],
              )
            ]),
            const SizedBox(height: 12),

            // Card for signal
            Card(
              color: theme.colorScheme.surfaceVariant,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('الإشارة الحالية:', style: TextStyle(fontSize: 16)),
                        const SizedBox(height: 8),
                        Text(signal, style: TextStyle(fontSize: 30, color: colorSignal)),
                      ]),
                    ),
                    Column(
                      children: [
                        ElevatedButton.icon(
                          icon: Icon(running ? Icons.stop : Icons.play_arrow),
                          label: Text(running ? 'إيقاف' : 'ابدأ'),
                          onPressed: running ? stopSim : startSim,
                        ),
                        const SizedBox(height: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('تفريغ السجل'),
                          onPressed: () {
                            setState(() {
                              history.clear();
                            });
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم تفريغ السجل')));
                          },
                        ),
                      ],
                    )
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Chart area
            Expanded(
              child: Card(
                color: theme.cardColor,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: closes.isEmpty
                      ? const Center(child: Text('لا توجد بيانات بعد — اضغط ابدأ'))
                      : LineChart(
                          LineChartData(
                            gridData: FlGridData(show: true),
                            minY: _minY(),
                            maxY: _maxY(),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 40)),
                              bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                              rightTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                              topTitles: AxisTitles(sideTitles: SideTitles(showTitles:false)),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                spots: _priceSpots(),
                                isCurved: false,
                                dotData: FlDotData(show: false),
                                barWidth: 1.4,
                                color: Colors.blueAccent,
                              ),
                              LineChartBarData(
                                spots: _emaSpots(8),
                                isCurved: false,
                                dotData: FlDotData(show: false),
                                barWidth: 1.4,
                                color: Colors.greenAccent,
                              ),
                              LineChartBarData(
                                spots: _emaSpots(21),
                                isCurved: false,
                                dotData: FlDotData(show: false),
                                barWidth: 1.4,
                                color: Colors.orangeAccent,
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),

            const SizedBox(height: 8),

            // history preview
            SizedBox(
              height: 120,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: history.isEmpty
                      ? const Center(child: Text('سجل الإشارات فارغ'))
                      : ListView.builder(
                          itemCount: history.length,
                          itemBuilder: (c, i) {
                            final item = history[history.length - 1 - i];
                            return ListTile(
                              dense: true,
                              title: Text('${item['signal']} — ${item['price']?.toStringAsFixed(5) ?? '-'}'),
                              subtitle: Text(item['time']),
                              leading: item['signal'] == 'CALL'
                                  ? const Icon(Icons.arrow_upward, color: Colors.green)
                                  : item['signal'] == 'PUT'
                                      ? const Icon(Icons.arrow_downward, color: Colors.red)
                                      : const Icon(Icons.remove),
                            );
                          },
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