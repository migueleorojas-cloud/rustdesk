// SAT Remoto Técnico (OfficeTech): pantalla principal de la compilación de técnicos
// (res/sat-remoto-tecnico.json, conn-type «outgoing»). Usa la API de SAT v-474
// (remoto_tec_api.php):
//  1. Iniciar sesión sin contraseña: SAT entrega un código y la app lo muestra con un QR;
//     el técnico lo aprueba desde SAT en su celular y la app recibe un token (solo en
//     memoria: cerrar la app es cerrar la sesión).
//  2. Buscar el equipo del cliente por su ID de SAT Remoto → ficha → orden abierta o nueva.
//  3. Conectar: SAT abre la sesión (o pide autorización a un administrador) con las mismas
//     reglas de la Conexión rápida y la deja atada al ID de este PC; luego se conecta aquí.
//  4. Mientras tanto: estado y minutos de la sesión, notas a la bitácora y «Terminar».

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/platform_model.dart';
import 'sat_remoto.dart';

const String kSatTecApi = '$kSatPortalUrl/remoto_tec_api.php';

/// Sesión del técnico: vive solo mientras la app está abierta.
class _SatTecSesion {
  static String token = '';
  static String tecnico = '';
  static String expira = '';
}

class SatTecnicoHome extends StatefulWidget {
  const SatTecnicoHome({Key? key}) : super(key: key);

  @override
  State<SatTecnicoHome> createState() => _SatTecnicoHomeState();
}

class _SatTecnicoHomeState extends State<SatTecnicoHome> {
  String _miId = '';
  String _error = '';
  bool _ocupado = false;

  // Vinculación
  String _codigo = '';
  String _secreto = '';
  String _urlQr = '';
  Timer? _tVinculo;

  // Búsqueda y ficha
  final TextEditingController _idCliente = TextEditingController();
  Map<String, dynamic>? _ficha;
  int _ticket = -1; // -1 sin elegir · 0 orden nueva · >0 orden existente
  final TextEditingController _quien = TextEditingController();
  final TextEditingController _tel = TextEditingController();
  final TextEditingController _falla = TextEditingController();
  final TextEditingController _nota = TextEditingController();

  // Sesión remota sobre el equipo
  Map<String, dynamic>? _estado;
  Timer? _tEstado;
  String _aviso = '';

  @override
  void initState() {
    super.initState();
    _cargarMiId();
  }

  @override
  void dispose() {
    _tVinculo?.cancel();
    _tEstado?.cancel();
    _idCliente.dispose();
    _quien.dispose();
    _tel.dispose();
    _falla.dispose();
    _nota.dispose();
    super.dispose();
  }

  Future<void> _cargarMiId() async {
    for (var i = 0; i < 20 && mounted; i++) {
      final id = (await bind.mainGetMyId()).replaceAll(RegExp(r'[^0-9]'), '');
      if (id.isNotEmpty) {
        setState(() => _miId = id);
        return;
      }
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  /// POST a la API de SAT. Devuelve el JSON o {ok:false, error:…}.
  Future<Map<String, dynamic>> _api(Map<String, dynamic> cuerpo,
      {bool conToken = true}) async {
    try {
      final datos = <String, dynamic>{...cuerpo, 'rustdesk_id': _miId};
      final cab = <String, String>{'Content-Type': 'application/json'};
      if (conToken && _SatTecSesion.token.isNotEmpty) {
        cab['Authorization'] = 'Bearer ${_SatTecSesion.token}';
        datos['token'] = _SatTecSesion.token; // por si el hosting no pasa la cabecera
      }
      final r = await http
          .post(Uri.parse(kSatTecApi), headers: cab, body: jsonEncode(datos))
          .timeout(const Duration(seconds: 25));
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map<String, dynamic>) {
        if (r.statusCode == 401 && conToken) _cerrarLocal();
        return j;
      }
    } catch (e) {
      return {'ok': false, 'error': 'No se pudo comunicar con SAT. Revise la conexión a internet.'};
    }
    return {'ok': false, 'error': 'Respuesta inesperada de SAT.'};
  }

  void _cerrarLocal() {
    _SatTecSesion.token = '';
    _SatTecSesion.tecnico = '';
    _SatTecSesion.expira = '';
    _tEstado?.cancel();
    if (mounted) {
      setState(() {
        _ficha = null;
        _estado = null;
      });
    }
  }

  // ------------------------------------------------------------------ inicio de sesión
  Future<void> _pedirCodigo() async {
    if (_miId.isEmpty) {
      setState(() => _error = 'Este PC todavía no tiene ID. Espere unos segundos.');
      return;
    }
    setState(() {
      _ocupado = true;
      _error = '';
    });
    final j = await _api({'op': 'vincular', 'pc': Platform.localHostname},
        conToken: false);
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (j['ok'] != true) {
      setState(() => _error = (j['error'] ?? 'No se pudo pedir el código.').toString());
      return;
    }
    setState(() {
      _codigo = (j['codigo'] ?? '').toString();
      _secreto = (j['secreto'] ?? '').toString();
      _urlQr = (j['url'] ?? '').toString();
    });
    _tVinculo?.cancel();
    _tVinculo = Timer.periodic(const Duration(seconds: 3), (_) => _revisarCodigo());
  }

  Future<void> _revisarCodigo() async {
    final j = await _api(
        {'op': 'vincular_estado', 'codigo': _codigo, 'secreto': _secreto},
        conToken: false);
    if (!mounted) return;
    final est = (j['estado'] ?? '').toString();
    if (est == 'pendiente') return;
    _tVinculo?.cancel();
    if (est == 'activo') {
      _SatTecSesion.token = (j['token'] ?? '').toString();
      _SatTecSesion.tecnico = (j['tecnico'] ?? '').toString();
      _SatTecSesion.expira = (j['expira'] ?? '').toString();
      setState(() {
        _codigo = '';
        _secreto = '';
        _error = '';
      });
      return;
    }
    setState(() {
      _codigo = '';
      _error = est == 'rechazado'
          ? 'El inicio de sesión fue rechazado en SAT.'
          : 'El código venció. Pida uno nuevo.';
    });
  }

  Future<void> _salir() async {
    await _api({'op': 'salir'});
    _cerrarLocal();
  }

  // ------------------------------------------------------------------ búsqueda y conexión
  Future<void> _buscar() async {
    final id = _idCliente.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (id.isEmpty) return;
    setState(() {
      _ocupado = true;
      _error = '';
      _aviso = '';
      _ficha = null;
      _estado = null;
      _ticket = -1;
    });
    final j = await _api({'op': 'ficha', 'id': id});
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (j['ok'] != true) {
      setState(() => _error = (j['error'] ?? 'No se encontró el equipo.').toString());
      return;
    }
    final ordenes = (j['ordenes'] as List?) ?? [];
    final mia = ordenes.cast<Map>().where((o) => o['mia'] == true).toList();
    setState(() {
      _ficha = j;
      _ticket = mia.isNotEmpty ? (mia.first['id'] as num).toInt() : (ordenes.isEmpty ? 0 : -1);
      if (_quien.text.isEmpty) _quien.text = (j['responsable'] ?? '').toString();
    });
    await _consultarEstado();
  }

  Future<void> _consultarEstado() async {
    final f = _ficha;
    if (f == null) return;
    final j = await _api({'op': 'estado', 'id': f['id']});
    if (!mounted) return;
    if (j['ok'] == true) setState(() => _estado = j);
    final est = (j['estado'] ?? '').toString();
    _tEstado?.cancel();
    if (est == 'esperando' || est == 'autorizada' || est == 'activa') {
      _tEstado = Timer(Duration(seconds: est == 'esperando' ? 5 : 20), _consultarEstado);
    }
  }

  Future<void> _conectar() async {
    final f = _ficha;
    if (f == null) return;
    if (_ticket < 0) {
      setState(() => _error = 'Elija la orden o «Orden nueva».');
      return;
    }
    if (_ticket == 0 && (_quien.text.trim().isEmpty || _falla.text.trim().length < 4)) {
      setState(() => _error = 'Para la orden nueva escriba quién pide el servicio y qué reporta.');
      return;
    }
    setState(() {
      _ocupado = true;
      _error = '';
      _aviso = '';
    });
    final j = await _api({
      'op': 'conectar',
      'id': f['id'],
      'ticket': _ticket,
      'quien': {
        'nombre': _quien.text.trim(),
        'tel': _tel.text.trim(),
        'falla': _falla.text.trim(),
        'canal': 'telefono',
        'prioridad': 'media',
      },
    });
    if (!mounted) return;
    setState(() => _ocupado = false);
    if (j['ok'] != true) {
      setState(() => _error = (j['msg'] ?? j['error'] ?? 'No se pudo abrir la sesión.').toString());
      return;
    }
    final t = (j['ticket'] as num?)?.toInt() ?? 0;
    if (t > 0) _ticket = t;
    setState(() => _aviso = (j['msg'] ?? '').toString());
    if (j['modo'] == 'directo') {
      _abrirConexion();
    }
    await _consultarEstado();
  }

  void _abrirConexion() {
    final f = _ficha;
    if (f == null) return;
    connect(context, f['id'].toString());
  }

  Future<void> _enviarNota() async {
    final t = (_estado?['ticket'] as num?)?.toInt() ?? (_ticket > 0 ? _ticket : 0);
    final txt = _nota.text.trim();
    if (t <= 0 || txt.length < 3) return;
    final j = await _api({'op': 'nota', 'ticket': t, 'texto': txt});
    if (!mounted) return;
    if (j['ok'] == true) {
      _nota.clear();
      showToast('Nota guardada en la orden');
    } else {
      setState(() => _error = (j['error'] ?? 'No se pudo guardar la nota.').toString());
    }
  }

  Future<void> _terminar() async {
    final f = _ficha;
    if (f == null) return;
    final j = await _api({'op': 'terminar', 'id': f['id']});
    if (!mounted) return;
    setState(() => _aviso = (j['msg'] ?? j['error'] ?? '').toString());
    await _consultarEstado();
  }

  // ------------------------------------------------------------------ pantalla
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: MyTheme.lightTheme,
      child: Container(
        color: SatColors.body,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SatHeader(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_SatTecSesion.token.isEmpty) _vistaInicio() else _vistaTecnico(),
                        if (_error.isNotEmpty) _cajaMensaje(_error, error: true),
                        const SizedBox(height: 16),
                        Center(
                          child: Text(_miId.isEmpty ? 'Obteniendo el ID de este PC…' : 'ID de este PC: $_miId',
                              style: const TextStyle(fontSize: 12, color: SatColors.secondary)),
                        ),
                        Center(child: loadPowered(context)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _titulo(String t, [String sub = '']) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(t, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: SatColors.text)),
          if (sub.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(sub, style: const TextStyle(fontSize: 14, color: SatColors.secondary)),
            ),
        ]),
      );

  Widget _cajaMensaje(String t, {bool error = false}) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: error ? SatColors.dangerSurface : SatColors.infoSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(t, style: TextStyle(color: error ? SatColors.danger : SatColors.info, fontSize: 14)),
      );

  Widget _tarjeta(List<Widget> hijos) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: SatColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: hijos),
      );

  Widget _campo(TextEditingController c, String etiqueta, {String pista = '', int lineas = 1, bool numerico = false, VoidCallback? alEnviar}) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: c,
          maxLines: lineas,
          keyboardType: numerico ? TextInputType.number : TextInputType.text,
          onSubmitted: alEnviar == null ? null : (_) => alEnviar(),
          decoration: InputDecoration(
            labelText: etiqueta,
            hintText: pista,
            filled: true,
            fillColor: Colors.white,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      );

  Widget _vistaInicio() {
    if (_codigo.isNotEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _titulo('Apruebe desde su celular', 'Escanee el código con el celular donde tiene SAT abierto y pulse «Sí, soy yo». O entre a SAT → SAT Remoto · modo técnico y escriba el código.'),
        Center(
          child: Container(
            padding: const EdgeInsets.all(10),
            color: Colors.white,
            child: QrImageView(data: _urlQr, size: 200, backgroundColor: Colors.white),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: SelectableText(_codigo,
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, letterSpacing: 4, color: SatColors.text)),
        ),
        const SizedBox(height: 6),
        const Center(
          child: Text('Esperando la aprobación… (vence en 10 minutos)',
              style: TextStyle(fontSize: 13, color: SatColors.secondary)),
        ),
        const SizedBox(height: 12),
        SatButton(
          label: 'Cancelar',
          onPressed: () {
            _tVinculo?.cancel();
            setState(() => _codigo = '');
          },
        ),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _titulo('SAT Remoto para técnicos', 'Inicie sesión con su cuenta de SAT. No escriba su contraseña en este PC: se aprueba desde su celular.'),
      const SizedBox(height: 8),
      const Center(child: SatIllustration(height: 90)),
      const SizedBox(height: 16),
      SatButton(
        label: _ocupado ? 'Pidiendo código…' : 'Soy técnico · iniciar sesión',
        icon: Icons.qr_code_2_rounded,
        kind: SatButtonKind.primary,
        onPressed: _ocupado ? null : _pedirCodigo,
      ),
      const SizedBox(height: 10),
      const Text('La sesión queda solo en este PC, solo mientras la aplicación esté abierta y como máximo durante la jornada.',
          textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: SatColors.secondary)),
    ]);
  }

  Widget _vistaTecnico() {
    final f = _ficha;
    final est = (_estado?['estado'] ?? '').toString();
    final hayMiSesion = est == 'autorizada' || est == 'activa';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Icon(Icons.verified_user, color: SatColors.success, size: 20),
        const SizedBox(width: 6),
        Expanded(
          child: Text('${_SatTecSesion.tecnico} · sesión de técnico',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: SatColors.text)),
        ),
        TextButton(onPressed: _salir, child: const Text('Cerrar sesión')),
      ]),
      _titulo('Conectarse a un cliente', 'Escriba el ID de SAT Remoto que le dicta el usuario.'),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: _campo(_idCliente, 'ID del cliente', pista: '123 456 789', numerico: true, alEnviar: _buscar)),
        const SizedBox(width: 8),
        SatButton(label: 'Buscar', icon: Icons.search, onPressed: _ocupado ? null : _buscar),
      ]),
      if (f != null) ..._vistaFicha(f, hayMiSesion),
      if (_aviso.isNotEmpty) _cajaMensaje(_aviso),
    ]);
  }

  List<Widget> _vistaFicha(Map<String, dynamic> f, bool hayMiSesion) {
    final ordenes = ((f['ordenes'] as List?) ?? []).cast<Map>();
    final pol = (f['politica'] as Map?) ?? {};
    final ses = f['sesion'] as Map?;
    final est = (_estado?['estado'] ?? '').toString();
    final w = <Widget>[
      _tarjeta([
        Text(f['cliente']?.toString() ?? '', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: SatColors.text)),
        Text([f['sede'], f['ubicacion']].where((x) => (x ?? '').toString().isNotEmpty).join(' · '),
            style: const TextStyle(color: SatColors.secondary)),
        const SizedBox(height: 6),
        Text('💻 ${f['equipo'] ?? ''}${(f['placa'] ?? '').toString().isNotEmpty ? ' · placa ${f['placa']}' : ''}${(f['serial'] ?? '').toString().isNotEmpty ? ' · S/N ${f['serial']}' : ''}',
            style: const TextStyle(color: SatColors.text)),
        if ((f['responsable'] ?? '').toString().isNotEmpty) Text('👤 ${f['responsable']}', style: const TextStyle(color: SatColors.text)),
        if ((f['pc'] ?? '').toString().isNotEmpty) Text('🖧 ${f['pc']} · ${f['estado_texto'] ?? ''}', style: const TextStyle(fontSize: 13, color: SatColors.secondary)),
      ]),
    ];
    if (ses != null && ses['mia'] != true) {
      w.add(_cajaMensaje('El equipo ya tiene una sesión de ${ses['tecnico']} (orden ${ses['orden']}).', error: true));
      return w;
    }
    if (hayMiSesion || est == 'esperando') {
      w.add(_tarjeta([
        Text(
          est == 'activa'
              ? '🟢 Conectado · orden ${_estado?['orden']} · quedan ${_estado?['restan_min']} min'
              : est == 'autorizada'
                  ? '🔓 Sesión autorizada · orden ${_estado?['orden']} · ${_estado?['restan_min']} min para conectarse'
                  : '⏳ Esperando que un administrador autorice (orden ${_estado?['orden']})…',
          style: const TextStyle(fontWeight: FontWeight.bold, color: SatColors.text),
        ),
        const SizedBox(height: 10),
        if (hayMiSesion)
          SatButton(label: 'Conectar al equipo', icon: Icons.desktop_windows_rounded, kind: SatButtonKind.primary, onPressed: _abrirConexion),
        if (hayMiSesion) _campo(_nota, 'Nota para la bitácora de la orden', pista: 'Qué hizo o encontró', lineas: 2),
        if (hayMiSesion) const SizedBox(height: 8),
        if (hayMiSesion)
          Row(children: [
            Expanded(child: SatButton(label: 'Guardar nota', icon: Icons.note_add_outlined, onPressed: _enviarNota)),
            const SizedBox(width: 8),
            Expanded(child: SatButton(label: 'Terminar sesión', icon: Icons.stop_circle_outlined, kind: SatButtonKind.danger, onPressed: _terminar)),
          ]),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            final t = (_estado?['ticket'] as num?)?.toInt() ?? 0;
            launchUrl(Uri.parse(t > 0 ? '$kSatPortalUrl/ticket.php?id=$t' : kSatPortalUrl));
          },
          child: const Text('Abrir la orden en SAT (informe, solución y firma)'),
        ),
      ]));
      return w;
    }
    if (est == 'rechazada' || est == 'vencida') {
      w.add(_cajaMensaje(est == 'rechazada' ? 'Un administrador rechazó la última solicitud.' : 'La última solicitud venció sin respuesta.', error: true));
    }
    final opciones = <Widget>[
      for (final o in ordenes)
        RadioListTile<int>(
          dense: true,
          value: (o['id'] as num).toInt(),
          groupValue: _ticket,
          onChanged: (v) => setState(() => _ticket = v ?? -1),
          title: Text('${o['codigo']} · ${o['titulo']}'),
          subtitle: Text('${o['estado']}${(o['tecnico'] ?? '').toString().isNotEmpty ? ' · ${o['tecnico']}' : ''}'),
        ),
      RadioListTile<int>(
        dense: true,
        value: 0,
        groupValue: _ticket,
        onChanged: (v) => setState(() => _ticket = v ?? -1),
        title: const Text('➕ Orden nueva'),
      ),
    ];
    w.add(_tarjeta([
      const Text('¿En qué orden queda la atención?', style: TextStyle(fontWeight: FontWeight.bold, color: SatColors.text)),
      ...opciones,
      if (_ticket == 0) _campo(_quien, 'Quién pide el servicio *'),
      if (_ticket == 0) _campo(_tel, 'Celular'),
      if (_ticket == 0) _campo(_falla, 'Qué reporta *', lineas: 2),
      const SizedBox(height: 10),
      Text(pol['directo'] == true ? '✔ ${pol['razon']}' : '🔔 Necesita autorización: ${pol['razon']}',
          style: TextStyle(fontSize: 13, color: pol['directo'] == true ? SatColors.success : SatColors.info)),
      const SizedBox(height: 10),
      SatButton(
        label: _ocupado ? 'Un momento…' : (pol['directo'] == true ? 'Abrir sesión y conectar' : 'Pedir autorización'),
        icon: pol['directo'] == true ? Icons.bolt_rounded : Icons.notifications_active_outlined,
        kind: SatButtonKind.primary,
        onPressed: _ocupado ? null : _conectar,
      ),
    ]));
    return w;
  }
}
