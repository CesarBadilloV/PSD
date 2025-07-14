import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

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
  String lastUpdate = 'hace unos segundos';
  final String esp32Ip = 'http://192.168.1.100'; // ← Cambia esta IP

  void _takePhoto() async {
    try {
      final response = await http.get(Uri.parse('$esp32Ip/foto'));
      if (response.statusCode == 200) {
        setState(() {
          lastUpdate = 'actualizado ahora';
        });
        // Opcional: puedes guardar la imagen si lo necesitas.
      } else {
        print('Error al capturar imagen');
      }
    } catch (e) {
      print('Error al conectar con ESP32: $e');
    }
  }

  void _sendDoorCommand(String action) async {
    try {
      final response = await http.get(Uri.parse('$esp32Ip/$action'));
      if (response.statusCode == 200) {
        print('Puerta: $action');
      } else {
        print('Error al enviar comando de puerta');
      }
    } catch (e) {
      print('Error al conectar con ESP32: $e');
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
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 20),
            CameraView(
              onTakePhoto: _takePhoto,
              lastUpdate: lastUpdate,
              imageUrl: '$esp32Ip/foto', // ← Vista directa desde la IP
            ),
            const SizedBox(height: 20),
            DoorControls(onAction: _sendDoorCommand),
            const SizedBox(height: 20),
            const StatusBar(),
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
          // Vista de la cámara desde la red
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
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Center(
                  child: Text(
                    'No se pudo cargar la imagen',
                    style: TextStyle(color: Colors.red),
                  ),
                );
              },
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
                ElevatedButton(
                  onPressed: onTakePhoto,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3498db),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'Tomar foto',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Última actualización: $lastUpdate',
                  style: const TextStyle(fontWeight: FontWeight.w500),
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
  const StatusBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: const [
          _StatusItem(title: 'Estado de la puerta', value: 'Cerrada'),
          _StatusItem(
            title: 'Detección de movimiento',
            value: 'Activo',
            isAlert: true,
          ),
          _StatusItem(title: 'Conexión', value: 'Estable'),
        ],
      ),
    );
  }
}

class _StatusItem extends StatelessWidget {
  final String title;
  final String value;
  final bool isAlert;

  const _StatusItem({
    required this.title,
    required this.value,
    this.isAlert = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.black54),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: isAlert ? const Color(0xffe74c3c) : Colors.black,
          ),
        ),
      ],
    );
  }
}
