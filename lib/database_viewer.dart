import 'database_helper.dart';
import 'package:flutter/material.dart';
import 'dart:io';

class DatabaseViewer extends StatefulWidget {
  const DatabaseViewer({super.key});

  @override
  State<DatabaseViewer> createState() => _DatabaseViewerState();
}

class _DatabaseViewerState extends State<DatabaseViewer>
    with SingleTickerProviderStateMixin {
  final dbHelper = DatabaseHelper();

  late TabController _tabController;

  List<Map<String, dynamic>> eventos = [];
  List<Map<String, dynamic>> fotos = [];

  bool loading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    setState(() => loading = true);

    final ev = await dbHelper.obtenerEventos();
    final ft = await dbHelper.obtenerFotos();

    setState(() {
      eventos = ev;
      fotos = ft;
      loading = false;
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatearFecha(String isoString) {
    final dt = DateTime.tryParse(isoString);
    if (dt == null) return isoString;
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Registros en DB'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Eventos'),
            Tab(text: 'Fotos'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _cargarDatos,
            tooltip: 'Refrescar',
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [_buildEventosList(), _buildFotosList()],
            ),
    );
  }

  Widget _buildEventosList() {
    if (eventos.isEmpty) {
      return const Center(child: Text('No hay eventos registrados'));
    }
    return ListView.separated(
      itemCount: eventos.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final evento = eventos[index];
        return ListTile(
          leading: const Icon(Icons.event_note),
          title: Text('Puerta: ${evento['estadoPuerta']}'),
          subtitle: Text('Movimiento: ${evento['deteccionMovimiento']}'),
          trailing: Text(_formatearFecha(evento['timestamp'])),
        );
      },
    );
  }

  Widget _buildFotosList() {
    if (fotos.isEmpty) {
      return const Center(child: Text('No hay fotos registradas'));
    }
    return ListView.separated(
      itemCount: fotos.length,
      separatorBuilder: (_, __) => const Divider(),
      itemBuilder: (context, index) {
        final foto = fotos[index];
        final ruta = foto['ruta'] as String;
        return ListTile(
          leading: SizedBox(
            width: 50,
            height: 50,
            child: Image.file(
              File(ruta),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return const Icon(Icons.broken_image);
              },
            ),
          ),
          title: Text('Foto tomada'),
          subtitle: Text(_formatearFecha(foto['timestamp'])),
        );
      },
    );
  }
}
