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
      developer.log('Intentando conectar con el ESP32...');

      final response = await http
          .get(Uri.parse('$esp32Ip/estado'))
          .timeout(const Duration(seconds: 10));

      developer.log('Respuesta recibida: ${response.statusCode}');
      developer.log('Cuerpo de respuesta: ${response.body}');

      if (response.statusCode == 200) {
        try {
          // Limpiar la respuesta de posibles caracteres extraños
          String cleanResponse = response.body.trim();
          developer.log('Respuesta limpia: $cleanResponse');

          // Validar que sea un JSON válido
          if (cleanResponse.isEmpty || !cleanResponse.startsWith('{')) {
            developer.log('Respuesta no es JSON válido');
            setState(() {
              conexion = 'Formato inválido';
            });
            return;
          }

          final data = jsonDecode(cleanResponse);
          developer.log('Datos decodificados: $data');

          setState(() {
            // Manejo más robusto de los datos con valores por defecto
            String puertaValue = data['puerta']?.toString() ?? 'desconocida';
            estadoPuerta = puertaValue == 'abierta' ? 'Abierta' : 'Cerrada';

            String movimientoValue =
                data['movimiento']?.toString() ?? 'desconocido';
            deteccionMovimiento = movimientoValue == 'detectado'
                ? 'Movimiento detectado'
                : 'Sin movimiento';

            conexion = 'Conectado';
            lastUpdate =
                'Actualizado: ${DateTime.now().toString().substring(11, 19)}';
          });

          developer.log(
            'Estado actualizado - Puerta: $estadoPuerta, Movimiento: $deteccionMovimiento',
          );

          // Guardar en base de datos solo si los datos son válidos
          if (estadoPuerta != 'Desconocido' &&
              deteccionMovimiento != 'Desconocido') {
            await dbHelper.insertarEvento(estadoPuerta, deteccionMovimiento);
          }
        } catch (jsonError) {
          developer.log('Error al decodificar JSON: $jsonError');
          developer.log('Respuesta que causó el error: ${response.body}');
          setState(() {
            conexion =
                'Error JSON: ${jsonError.toString().substring(0, 20)}...';
          });
        }
      } else {
        developer.log('Error HTTP: ${response.statusCode}');
        setState(() {
          conexion = 'Error HTTP ${response.statusCode}';
        });
      }
    } on TimeoutException catch (e) {
      developer.log('Timeout: $e');
      setState(() {
        conexion = 'Timeout de conexión';
      });
    } on SocketException catch (e) {
      developer.log('Error de conexión: $e');
      setState(() {
        conexion = 'Sin conexión de red';
      });
    } catch (e) {
      developer.log('Error general: $e');
      setState(() {
        conexion = 'Error: ${e.toString().substring(0, 30)}...';
      });
    }
  }

  void _takePhoto() async {
    try {
      developer.log('Tomando foto...');

      final response = await http
          .get(Uri.parse('$esp32Ip/foto'))
          .timeout(const Duration(seconds: 15)); // Timeout más largo para fotos

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
          lastUpdate =
              'Foto guardada: ${DateTime.now().toString().substring(11, 19)}';
        });

        // Guardar registro de foto en la base
        await dbHelper.insertarFoto(filePath);

        // Mostrar mensaje de éxito
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Foto guardada exitosamente'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        developer.log('Error al capturar imagen: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al capturar imagen: ${response.statusCode}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      developer.log('Error al conectar con ESP32: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error de conexión: ${e.toString().substring(0, 30)}...',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _sendDoorCommand(String action) async {
    try {
      developer.log('Enviando comando: $action');

      final response = await http
          .get(Uri.parse('$esp32Ip/$action'))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        developer.log('Comando enviado exitosamente: $action');

        // Actualizar estado inmediatamente
        _actualizarEstado();

        // Mostrar mensaje de éxito
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Puerta ${action == 'abrir' ? 'abierta' : 'cerrada'} exitosamente',
              ),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        developer.log('Error al enviar comando: ${response.statusCode}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al $action puerta: $response.statusCode'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      developer.log('Error al conectar con ESP32: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error de conexión: ${e.toString().substring(0, 30)}...',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
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
              streamUrl: '$esp32Ip/stream',
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

class CameraView extends StatefulWidget {
  final VoidCallback onTakePhoto;
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
  String _imageKey = '0';
  bool _isLoading = false;

  void _refreshImage() {
    setState(() {
      _imageKey = DateTime.now().millisecondsSinceEpoch.toString();
      _isLoading = true;
    });

    // Simular carga
    Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
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
      margin: const EdgeInsets.only(bottom: 20),
      child: Column(
        children: [
          // Vista de la cámara
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
              child: Stack(
                children: [
                  // Imagen de la cámara
                  Image.network(
                    '${widget.imageUrl}?v=$_imageKey',
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 10),
                            Text('Cargando imagen...'),
                          ],
                        ),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      developer.log('Error cargando imagen: $error');
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
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  // Overlay de carga
                  if (_isLoading)
                    Container(
                      color: Colors.black.withAlpha(
                        77,
                      ), // 77 es equivalente a 30% de opacidad // Esto es válido
                      child: const Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CircularProgressIndicator(color: Colors.white),
                            SizedBox(height: 10),
                            Text(
                              'Actualizando...',
                              style: TextStyle(color: Colors.white),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Controles de la cámara
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Color(0xFFecf0f1),
              borderRadius: BorderRadius.only(
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
                      onPressed: widget.onTakePhoto,
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
                      onPressed: _refreshImage,
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      label: const Text(
                        'Actualizar',
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
                  'Imagen actual • ${widget.lastUpdate}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Presiona "Actualizar" para ver imagen reciente',
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
      padding: const EdgeInsets.all(16),
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
                icon:
                    conexion.contains('Error') ||
                        conexion.contains('Sin conexión') ||
                        conexion.contains('Timeout')
                    ? Icons.wifi_off
                    : Icons.wifi,
                color:
                    conexion.contains('Error') ||
                        conexion.contains('Sin conexión') ||
                        conexion.contains('Timeout')
                    ? Colors.red
                    : Colors.green,
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
