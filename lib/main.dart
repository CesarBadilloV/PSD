import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:gallery_saver/gallery_saver.dart';
import 'dart:convert';
import 'dart:async';
import 'database_helper.dart';
import 'database_viewer.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timbre Inteligente',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String estadoPuerta = 'Desconocido';
  String deteccionMovimiento = 'Desconocido';
  String lastUpdate = 'hace unos segundos';
  Timer? _estadoTimer;
  bool _isConnected = false;
  final DatabaseHelper dbHelper = DatabaseHelper();

  // Configuración de conexión (¡Actualiza con tu IP correcta!)
  final String esp32Ip = 'http://172.20.10.2'; // Cambiar por tu IP real
  final int esp32Port = 80;

  // Constructor de URLs unificado
  Uri _buildEsp32Url(String endpoint) {
    return Uri.parse('$esp32Ip:/$endpoint');
  }

  @override
  void initState() {
    super.initState();
    _verifyConnection();
    _estadoTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) => _isConnected ? _actualizarEstado() : _verifyConnection(),
    );
  }

  @override
  void dispose() {
    _estadoTimer?.cancel();
    super.dispose();
  }

  Future<void> _verifyConnection() async {
    try {
      final response = await http
          .get(_buildEsp32Url(''))
          .timeout(const Duration(seconds: 2));
      setState(() => _isConnected = response.statusCode == 200);
      if (_isConnected) _actualizarEstado();
    } catch (e) {
      setState(() => _isConnected = false);
      developer.log('Error de conexión: $e');
    }
  }

  Future<void> _actualizarEstado() async {
    if (!_isConnected) return;

    try {
      developer.log('Consultando estado en: ${_buildEsp32Url('estado')}');
      final response = await http
          .get(_buildEsp32Url('estado'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body.trim()) as Map<String, dynamic>;
        developer.log('Datos recibidos: $data');

        setState(() {
          estadoPuerta = data['puerta'] == 'abierta' ? 'Abierta' : 'Cerrada';
          deteccionMovimiento = data['movimiento'] == 'detectado'
              ? 'Movimiento detectado'
              : 'Sin movimiento';
          lastUpdate =
              'Últ. actualización: ${DateTime.now().toString().substring(11, 19)}';
        });

        await dbHelper.insertarEvento(estadoPuerta, deteccionMovimiento);
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error al actualizar estado: $e');
      setState(() => _isConnected = false);
    }
  }

  Future<void> _takePhoto() async {
    if (!_isConnected) {
      _showSnackBar('No hay conexión con el ESP32');
      return;
    }

    try {
      final response = await http
          .get(_buildEsp32Url('foto'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath =
            '${directory.path}/captura_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        await GallerySaver.saveImage(file.path);
        await dbHelper.insertarFoto(filePath);

        setState(() {
          lastUpdate =
              'Foto guardada: ${DateTime.now().toString().substring(11, 19)}';
        });

        _showSnackBar('Foto guardada exitosamente', isError: false);
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error al tomar foto: $e');
      _showSnackBar('Error al capturar foto: ${e.toString().split(':').first}');
    }
  }

  Future<void> _sendDoorCommand(String action) async {
    if (!_isConnected) {
      _showSnackBar('No hay conexión con el ESP32');
      return;
    }

    try {
      final response = await http
          .get(_buildEsp32Url(action))
          .timeout(const Duration(seconds: 5));

      developer.log(
        'Respuesta comando $action: ${response.statusCode} - ${response.body}',
      );

      if (response.statusCode == 200) {
        await Future.delayed(const Duration(seconds: 1));
        _actualizarEstado();
        _showSnackBar(
          'Puerta ${action == 'abrir' ? 'abierta' : 'cerrada'}',
          isError: false,
        );
      } else {
        throw Exception('HTTP ${response.statusCode}');
      }
    } catch (e) {
      developer.log('Error al $action puerta: $e');
      _showSnackBar('Error al ${action}ar puerta');
    }
  }

  void _showSnackBar(String message, {bool isError = true}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? Colors.red : Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f5f5),
      appBar: AppBar(
        title: const Text('Timbre Inteligente'),
        centerTitle: true,
        backgroundColor: const Color(0xff2c3e50),
        actions: [
          IconButton(
            icon: const Icon(Icons.storage),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const DatabaseViewer()),
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildConnectionStatus(),
            const SizedBox(height: 20),
            CameraView(
              onTakePhoto: _isConnected ? _takePhoto : null,
              lastUpdate: lastUpdate,
              imageUrl: _buildEsp32Url('foto').toString(),
              streamUrl: _isConnected
                  ? _buildEsp32Url('stream').toString()
                  : '',
            ),
            const SizedBox(height: 20),
            DoorControls(
              onAction: _isConnected ? _sendDoorCommand : null,
              isConnected: _isConnected,
            ),
            const SizedBox(height: 20),
            StatusBar(
              estadoPuerta: estadoPuerta,
              deteccion: deteccionMovimiento,
              conexion: _isConnected ? 'Conectado' : 'Desconectado',
            ),
            const SizedBox(height: 30),
            const Text(
              'Universidad Tecnológica de Tamaulipas Norte\n© 2025 - Proyecto Final',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionStatus() {
    return Card(
      color: _isConnected ? Colors.green[50] : Colors.red[50],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 10),
                Text(
                  _isConnected ? 'CONECTADO' : 'SIN CONEXIÓN',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _isConnected ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Endpoint: ${_buildEsp32Url('').toString()}',
              style: const TextStyle(fontSize: 12),
            ),
            if (!_isConnected) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: _verifyConnection,
                child: const Text('Reintentar conexión'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class CameraView extends StatefulWidget {
  final VoidCallback? onTakePhoto;
  final String lastUpdate;
  final String imageUrl;
  final String streamUrl;

  const CameraView({
    super.key,
    required this.onTakePhoto,
    required this.lastUpdate,
    required this.imageUrl,
    required this.streamUrl,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> {
  bool _isLoading = false;

  void _simulateRefresh() {
    setState(() => _isLoading = true);
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) setState(() => _isLoading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(20),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            height: 400,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            child: widget.streamUrl.isNotEmpty
                ? Stack(
                    children: [
                      Mjpeg(
                        stream: widget.streamUrl,
                        isLive: true,
                        timeout: const Duration(seconds: 5),
                        error: (context, error, stack) =>
                            _buildErrorWidget(error),
                      ),
                      if (_isLoading) _buildLoadingOverlay(),
                    ],
                  )
                : _buildDisconnectedOverlay(),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFecf0f1),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: widget.onTakePhoto,
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      label: const Text('Guardar foto'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF27ae60),
                        foregroundColor: Colors.white,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _simulateRefresh,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text('Actualizar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3498db),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Estado: ${widget.lastUpdate}',
                  style: const TextStyle(color: Colors.green),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorWidget(dynamic error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off, size: 50, color: Colors.grey),
          const SizedBox(height: 10),
          Text(
            'Error: ${error.toString()}',
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDisconnectedOverlay() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 50, color: Colors.grey),
          SizedBox(height: 10),
          Text('Cámara no disponible'),
          Text(
            'Conecta el dispositivo al ESP32',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(128),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(50),
            blurRadius: 10,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}

class DoorControls extends StatelessWidget {
  final void Function(String)? onAction;
  final bool isConnected;

  const DoorControls({
    super.key,
    required this.onAction,
    required this.isConnected,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildDoorButton(
          icon: '🔓',
          color: isConnected ? const Color(0xff2ecc71) : Colors.grey,
          label: 'Abrir',
          onTap: onAction != null ? () => onAction!('abrir') : null,
        ),
        const SizedBox(width: 20),
        _buildDoorButton(
          icon: '🔒',
          color: isConnected ? const Color(0xffe74c3c) : Colors.grey,
          label: 'Cerrar',
          onTap: onAction != null ? () => onAction!('cerrar') : null,
        ),
      ],
    );
  }

  Widget _buildDoorButton({
    required String icon,
    required Color color,
    required String label,
    required VoidCallback? onTap,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(128),
                  blurRadius: 6,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Text(icon, style: const TextStyle(fontSize: 30)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label),
      ],
    );
  }
}

class StatusBar extends StatelessWidget {
  final String estadoPuerta;
  final String deteccion;
  final String conexion;

  const StatusBar({
    super.key,
    required this.estadoPuerta,
    required this.deteccion,
    required this.conexion,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusItem(
                title: 'Puerta',
                value: estadoPuerta,
                icon: estadoPuerta.contains('Abierta')
                    ? Icons.lock_open
                    : Icons.lock,
                color: estadoPuerta.contains('Abierta')
                    ? Colors.green
                    : Colors.red,
              ),
              _buildStatusItem(
                title: 'Movimiento',
                value: deteccion,
                icon: Icons.motion_photos_on,
                color: deteccion.contains('detectado')
                    ? Colors.orange
                    : Colors.grey,
              ),
              _buildStatusItem(
                title: 'Conexión',
                value: conexion,
                icon: conexion == 'Conectado' ? Icons.wifi : Icons.wifi_off,
                color: conexion == 'Conectado' ? Colors.green : Colors.red,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(height: 5),
        Text(title, style: const TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}
