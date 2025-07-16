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
  String conexion = 'Desconocido';
  String lastUpdate = 'hace unos segundos';
  Timer? _estadoTimer;
  // Instancia de la base de datos
  final DatabaseHelper dbHelper = DatabaseHelper();

  final String esp32Ip = 'http://172.20.10.2'; // Cambia esta IP si es necesario

  @override
  void initState() {
    super.initState();
    _actualizarEstado();
    _estadoTimer = Timer.periodic(
      const Duration(seconds: 5), // ⏱️ cada 5 segundos
      (timer) => _actualizarEstado(),
    );
  }

  @override
  void dispose() {
    _estadoTimer?.cancel(); // Cancela el Timer si está activo
    super.dispose();
  }

  void _actualizarEstado() async {
    try {
      final response = await http
          .get(Uri.parse('$esp32Ip/estado'))
          .timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          // Ajusta según los valores que envía el ESP32
          estadoPuerta = data['puerta'] == 'abierta' ? 'Abierta' : 'Cerrada';
          deteccionMovimiento =
              data['movimiento'].toString().contains('detectado')
              ? 'Movimiento detectado'
              : 'Sin movimiento';
          conexion = 'Conectado';
          lastUpdate =
              'Actualizado: ${DateTime.now().toString().substring(11, 19)}';
        });

        await dbHelper.insertarEvento(estadoPuerta, deteccionMovimiento);
      } else {
        setState(() {
          conexion = 'Error ${response.statusCode}';
        });
      }
    } on TimeoutException {
      setState(() => conexion = 'Timeout');
    } catch (e) {
      setState(() => conexion = 'Error: $e');
    }
  }

  void _takePhoto() async {
    try {
      final response = await http.get(Uri.parse('$esp32Ip/foto'));

      if (response.statusCode == 200) {
        final directory = await getTemporaryDirectory();
        final filePath =
            '${directory.path}/captura_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final file = File(filePath);
        await file.writeAsBytes(response.bodyBytes);

        // Guardar en galería
        final result = await GallerySaver.saveImage(file.path);
        developer.log(
          result == true
              ? 'Imagen guardada correctamente'
              : 'No se pudo guardar la imagen',
        );

        setState(() {
          lastUpdate = 'Guardada y actualizada ahora';
        });

        // Guardar registro de foto en la base
        await dbHelper.insertarFoto(filePath);
      } else {
        developer.log('Error al capturar imagen');
      }
    } catch (e) {
      developer.log('Error al conectar con ESP32: $e');
    }
  }

  void _sendDoorCommand(String action) async {
    try {
      final response = await http.get(Uri.parse('$esp32Ip/$action'));
      if (response.statusCode == 200) {
        developer.log('Puerta: $action');
        _actualizarEstado(); // actualiza estado tras acción
      } else {
        developer.log('Error al enviar comando de puerta');
      }
    } catch (e) {
      developer.log('Error al conectar con ESP32: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff5f5f5),
      appBar: AppBar(
        title: const Text('Timbre Inteligente con Cámara'),
        centerTitle: true,
        backgroundColor: const Color(0xff2c3e50),
        actions: [
          IconButton(
            icon: const Icon(Icons.storage),
            tooltip: 'Ver registros',
            onPressed: () {
              Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const DatabaseViewer()));
            },
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            CameraView(
              onTakePhoto: _takePhoto,
              lastUpdate: lastUpdate,
              imageUrl: '$esp32Ip/foto',
            ),
            const SizedBox(height: 20),
            DoorControls(onAction: _sendDoorCommand),
            const SizedBox(height: 20),
            StatusBar(
              estadoPuerta: estadoPuerta,
              deteccion: deteccionMovimiento,
              conexion: conexion,
            ),
            const SizedBox(height: 30),
            const Text(
              'Universidad Tecnológica de Tamaulipas Norte - TSU en Tecnologías de la Información\n© 2025 - Proyecto Final',
              style: TextStyle(fontSize: 12, color: Colors.black54),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// Reemplaza tu clase CameraView con esta versión actualizada:

class CameraView extends StatelessWidget {
  final VoidCallback onTakePhoto;
  final String lastUpdate;
  final String imageUrl;

  const CameraView({
    super.key,
    required this.onTakePhoto,
    required this.lastUpdate,
    required this.imageUrl,
  });

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
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          // Vista del stream de video en tiempo real
          Container(
            height: 400,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(8),
                topRight: Radius.circular(8),
              ),
              child: Image.network(
                imageUrl.replaceAll('/foto', '/stream'), // Cambiar a stream
                fit: BoxFit.cover,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(child: CircularProgressIndicator());
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt_outlined,
                          size: 50,
                          color: Colors.grey,
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Cámara no disponible',
                          style: TextStyle(color: Colors.red),
                        ),
                        Text(
                          'Verificar conexión ESP32',
                          style: TextStyle(color: Colors.grey, fontSize: 12),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // Controles de la cámara
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFecf0f1),
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    ElevatedButton.icon(
                      onPressed: onTakePhoto,
                      icon: const Icon(Icons.camera_alt, color: Colors.white),
                      label: const Text(
                        'Guardar foto',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF27ae60),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        // Recargar stream si hay problemas
                        // Esto fuerza un rebuild del widget
                        (context as Element).markNeedsBuild();
                      },
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text(
                        'Recargar',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3498db),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Video en tiempo real • $lastUpdate',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Stream MJPEG activo',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class DoorControls extends StatelessWidget {
  final void Function(String action) onAction;

  const DoorControls({super.key, required this.onAction});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _doorButton(
          icon: '🔓',
          color: const Color(0xff2ecc71),
          label: 'Abrir',
          onTap: () => onAction('abrir'),
        ),
        const SizedBox(width: 20),
        _doorButton(
          icon: '🔒',
          color: const Color(0xffe74c3c),
          label: 'Cerrar',
          onTap: () => onAction('cerrar'),
        ),
      ],
    );
  }

  Widget _doorButton({
    required String icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
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
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 6),
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
      padding: const EdgeInsets.all(16), // Mueve el padding aquí
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _StatusItem(
                title: 'Puerta',
                value: estadoPuerta,
                icon: estadoPuerta.contains('Abierta')
                    ? Icons.lock_open
                    : Icons.lock,
                color: estadoPuerta.contains('Abierta')
                    ? Colors.green
                    : Colors.red,
              ),
              _StatusItem(
                title: 'Movimiento',
                value: deteccion,
                icon: Icons.motion_photos_on,
                color: deteccion.contains('detectado')
                    ? Colors.orange
                    : Colors.grey,
              ),
              _StatusItem(
                title: 'Conexión',
                value: conexion,
                icon: conexion.contains('Error') ? Icons.wifi_off : Icons.wifi,
                color: conexion.contains('Error') ? Colors.red : Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Última actualización: ${DateTime.now().toString().substring(0, 16)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _StatusItem({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 30, color: color),
        const SizedBox(height: 5),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
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
