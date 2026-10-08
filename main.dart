import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

void main() {
  runApp(const EmergencyApp());
}

class EmergencyApp extends StatelessWidget {
  const EmergencyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'לחצן מצוקה',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Arial',
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.red),
      ),
      home: const EmergencyHomePage(),
    );
  }
}

class EmergencyHomePage extends StatefulWidget {
  const EmergencyHomePage({super.key});

  @override
  State<EmergencyHomePage> createState() => _EmergencyHomePageState();
}

class _EmergencyHomePageState extends State<EmergencyHomePage> {
  final _accountController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController();

  bool _sending = false;
  String _status = 'מוכן';
  String _lastFrame = '';
  int _sequence = 1;

  @override
  void dispose() {
    _accountController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  int _siaCrc16(List<int> bytes) {
    int crc = 0xFFFF;
    for (final byte in bytes) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        crc = (crc & 1) != 0 ? ((crc >> 1) ^ 0xA001) : (crc >> 1);
      }
    }
    return crc & 0xFFFF;
  }

  List<int> _buildFrame(String account) {
    final sequence = _sequence.toString().padLeft(4, '0');

    // ADM-CID Contact ID 120:
    // qualifier 1 + event 120 + group/partition 00 + zone/user 000
    final data =
        '"ADM-CID"$sequence'
        'R0'
        'L0'
        '#$account'
        '[#$account|1120 00 000]';

    final dataBytes = ascii.encode(data);
    if (dataBytes.length > 0xFFF) {
      throw Exception('הודעה ארוכה מדי');
    }

    final length = dataBytes.length
        .toRadixString(16)
        .toUpperCase()
        .padLeft(3, '0');

    final crc = _siaCrc16(dataBytes)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(4, '0');

    // LF + CRC + 0LLL + data + CR
    return ascii.encode('\x0A$crc' '0$length' '$data\x0D');
  }

  Future<void> _sendEmergency() async {
    if (_sending) return;

    final account = _accountController.text.trim().toUpperCase();
    final host = _ipController.text.trim();
    final port = int.tryParse(_portController.text.trim());

    if (account.isEmpty) {
      _error('יש להזין מספר לקוח / Account ID');
      return;
    }
    if (account.length > 16 || !RegExp(r'^[A-Z0-9]+$').hasMatch(account)) {
      _error('Account ID חייב להכיל אותיות באנגלית ומספרים בלבד, עד 16 תווים');
      return;
    }
    if (host.isEmpty) {
      _error('יש להזין כתובת IP או Hostname');
      return;
    }
    if (port == null || port < 1 || port > 65535) {
      _error('יש להזין Port בין 1 ל־65535');
      return;
    }

    setState(() {
      _sending = true;
      _status = 'מתחבר לשרת...';
    });

    Socket? socket;
    try {
      final frame = _buildFrame(account);
      _lastFrame = frame
          .map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase())
          .join(' ');

      socket = await Socket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );

      setState(() => _status = 'שולח אות מצוקה...');
      socket.add(frame);
      await socket.flush();

      // Give a receiver a short opportunity to answer/ACK.
      final response = <int>[];
      final completer = Completer<void>();
      late StreamSubscription<List<int>> sub;

      sub = socket.listen(
        (data) {
          response.addAll(data);
          if (!completer.isCompleted) completer.complete();
        },
        onError: (_) {
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      try {
        await completer.future.timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        );
      } finally {
        await sub.cancel();
      }

      await socket.close();

      _sequence++;
      if (_sequence > 9999) _sequence = 1;

      if (!mounted) return;
      setState(() {
        _sending = false;
        _status = response.isNotEmpty
            ? 'אות המצוקה נשלח והתקבלה תשובה'
            : 'אות המצוקה נשלח';
      });

      _success(
        response.isNotEmpty
            ? 'האות נשלח והתקבלה תשובה מהשרת.'
            : 'האות נשלח לשרת.',
      );
    } on TimeoutException {
      await socket?.close();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _status = 'Timeout';
      });
      _error('לא התקבלה תגובה מהשרת בזמן שהוגדר.');
    } on SocketException catch (e) {
      await socket?.close();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _status = 'שגיאת תקשורת';
      });
      _error('שגיאת תקשורת: ${e.message}');
    } catch (e) {
      await socket?.close();
      if (!mounted) return;
      setState(() {
        _sending = false;
        _status = 'שגיאה';
      });
      _error('אירעה שגיאה: $e');
    }
  }

  void _error(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.red.shade800,
        content: Text(message, textDirection: TextDirection.rtl),
      ),
    );
  }

  void _success(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: Colors.green.shade700,
        content: Text(message, textDirection: TextDirection.rtl),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: Colors.grey.shade50,
        ),
      ),
    );
  }

  Widget _button() {
    return GestureDetector(
      onLongPress: _sendEmergency,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 230,
        height: 230,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _sending ? Colors.red.shade900 : Colors.red.shade600,
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(.35),
              blurRadius: 25,
              spreadRadius: 5,
            ),
          ],
        ),
        child: Center(
          child: _sending
              ? const SizedBox(
                  width: 55,
                  height: 55,
                  child: CircularProgressIndicator(
                    strokeWidth: 5,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.warning_rounded, size: 70, color: Colors.white),
                    SizedBox(height: 8),
                    Text(
                      'מצוקה',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'לחצן מצוקה',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _field(
                  controller: _accountController,
                  label: 'מספר לקוח (Account ID)',
                  hint: 'לדוגמה: A123',
                ),
                _field(
                  controller: _ipController,
                  label: 'כתובת IP / Host',
                  hint: 'לדוגמה: 192.168.1.100',
                  keyboardType: TextInputType.url,
                ),
                _field(
                  controller: _portController,
                  label: 'Port',
                  hint: 'לדוגמה: 5000',
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'סטטוס',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 5),
                      Text(_status, textAlign: TextAlign.center),
                    ],
                  ),
                ),
                const SizedBox(height: 35),
                _button(),
                const SizedBox(height: 20),
                const Text(
                  'יש ללחוץ לחיצה ממושכת על הלחצן',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Contact ID 120 באמצעות SIA DC-09',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 25),
                if (_lastFrame.isNotEmpty)
                  ExpansionTile(
                    title: const Text('מידע טכני'),
                    children: [
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'הודעה אחרונה (Hex):',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: SelectableText(
                          _lastFrame,
                          textDirection: TextDirection.ltr,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
