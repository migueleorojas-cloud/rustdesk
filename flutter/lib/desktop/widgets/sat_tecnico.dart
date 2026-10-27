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
//  5. (SAT v-475) Equipos con acceso desatendido: la app pide a SAT la clave de un solo uso de
//     la sesión (op=clave) cuando el agente del equipo ya la puso, y se conecta con ella sin que
//     nadie acepte. «Mis sesiones abiertas» (op=mis_sesiones) lista todas las sesiones vigentes
//     del técnico para volver a cada una (nota, terminar, reconectar).
//  6. (SAT v-480) El botón «Conectar» de SAT web abre «sat-remoto-tecnico://sat/<ID>»: la app recibe el ID
//     (sat_enlace.dart), lo busca y se conecta si ya hay sesión. La versión portable se anota sola en Windows
//     (solo para el usuario, sin permisos de administrador) cada vez que se abre; la instalada (MSI) ya lo trae.
//  7. (SAT v-479) Seguimiento técnico de la orden (op=avances / op=avance): los mismos avances de SAT, con el
//     ✅ Cierre / informe final. Fotos, firma y cierre formal de la orden siguen en SAT.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:http/http.dart' as http;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/platform_model.dart';
import 'sat_enlace.dart';
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
  // Seguimiento técnico de la orden (SAT v-479: los mismos avances de la orden)
  Map<String, dynamic>? _seg;
  int _segTicket = 0;
  String _tipoAv = 'diagnostico';
  String _resAv = '';
  final TextEditingController _textoAv = TextEditingController();
  final TextEditingController _recAv = TextEditingController();
  bool _guardandoAv = false;

  // Sesión remota sobre el equipo
  Map<String, dynamic>? _estado;
  Timer? _tEstado;
  String _aviso = '';

  // Mis sesiones abiertas (todas las vigentes del técnico, en cualquier equipo)
  List<Map> _misSesiones = [];
  Timer? _tMis;
  bool _esperandoClave = false;

  // Enlace desde SAT web (ID pedido antes de tener sesión de técnico)
  String _idPendiente = '';

  @override
  void initState() {
    super.initState();
    _cargarMiId();
    SatEnlace.listo = true;
    SatEnlace.id.addListener(_enlaceRecibido);
    if (SatEnlace.id.value.isNotEmpty) Future.microtask(_enlaceRecibido);
    _registrarEnlace();
  }

  /// Portable: deja anotado en Windows (HKCU, solo este usuario) que los enlaces de SAT abren este ejecutable. Se
  /// repite solo si cambió la ruta. Instalada: el MSI ya registró el enlace; se quita el del usuario para no tapar al
  /// del instalador.
  Future<void> _registrarEnlace() async {
    if (!Platform.isWindows) return;
    try {
      final esquema = bind.mainUriPrefixSync().replaceAll('://', '');
      if (esquema.isEmpty) return;
      final clave = 'HKCU\\Software\\Classes\\$esquema';
      if (bind.mainIsInstalled()) {
        if (bind.mainGetLocalOption(key: 'sat-enlace-exe').isNotEmpty) {
          await Process.run('reg', ['delete', clave, '/f']);
          await bind.mainSetLocalOption(key: 'sat-enlace-exe', value: '');
        }
        return;
      }
      final exe = Platform.resolvedExecutable;
      if (bind.mainGetLocalOption(key: 'sat-enlace-exe') == exe) return;
      await Process.run('reg', ['add', clave, '/ve', '/d', 'URL:SAT Remoto Técnico', '/f']);
      await Process.run('reg', ['add', clave, '/v', 'URL Protocol', '/d', '', '/f']);
      await Process.run('reg', ['add', '$clave\\DefaultIcon', '/ve', '/d', '"$exe",0', '/f']);
      final r = await Process.run('reg', ['add', '$clave\\shell\\open\\command', '/ve', '/d', '"$exe" "%1"', '/f']);
      if (r.exitCode == 0) await bind.mainSetLocalOption(key: 'sat-enlace-exe', value: exe);
    } catch (_) {}
  }

  void _enlaceRecibido() {
    final id = SatEnlace.id.value;
    if (id.isEmpty || !mounted) return;
    _idPendiente = id;
    if (_SatTecSesion.token.isNotEmpty) {
      _atenderEnlace();
    } else {
      setState(() => _aviso = 'SAT pidió conectarse al equipo $id. Inicie sesión de técnico y la app sigue con ese equipo.');
    }
  }

  Future<void> _atenderEnlace() async {
    final id = _idPendiente;
    if (id.isEmpty) return;
    _idPendiente = '';
    await _irASesion(id, conectar: true);
  }

  @override
  void dispose() {
    _tVinculo?.cancel();
    _tEstado?.cancel();
    _tMis?.cancel();
    SatEnlace.id.removeListener(_enlaceRecibido);
    SatEnlace.listo = false;
    _idCliente.dispose();
    _quien.dispose();
    _tel.dispose();
    _falla.dispose();
    _textoAv.dispose();
    _recAv.dispose();
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
    _tMis?.cancel();
    if (mounted) {
      setState(() {
        _ficha = null;
        _estado = null;
        _misSesiones = [];
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
      _cargarMisSesiones();
      if (_idPendiente.isNotEmpty) _atenderEnlace();
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
      _seg = null;
      _segTicket = 0;
      _recAv.clear();
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
    final t = (j['ticket'] as num?)?.toInt() ?? 0;
    if ((est == 'autorizada' || est == 'activa') && t > 0 && t != _segTicket) _cargarSeguimiento(t);
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
    await _consultarEstado();
    _cargarMisSesiones();
    if (j['modo'] == 'directo') {
      await _abrirConexion();
    }
  }

  /// Conecta al equipo de la ficha. Si la sesión es desatendida (SAT v-475), espera a que el agente del
  /// equipo ponga la clave de la sesión (máximo ~1 minuto) y se conecta con ella: nadie tiene que aceptar.
  Future<void> _abrirConexion() async {
    final f = _ficha;
    if (f == null || _esperandoClave) return;
    final id = f['id'].toString();
    if (_estado?['desatendido'] != true) {
      connect(context, id);
      return;
    }
    setState(() {
      _esperandoClave = true;
      _error = '';
    });
    String clave = '';
    String falla = '';
    for (var i = 0; i < 15 && mounted; i++) {
      final j = await _api({'op': 'clave', 'id': id});
      if (j['ok'] != true) {
        falla = (j['error'] ?? 'SAT no entregó la clave.').toString();
        break;
      }
      if (j['desatendido'] != true) break; // dejó de ser desatendido: conexión normal (el usuario acepta)
      if (j['lista'] == true && (j['clave'] ?? '').toString().isNotEmpty) {
        clave = j['clave'].toString();
        break;
      }
      await Future.delayed(const Duration(seconds: 4));
    }
    if (!mounted) return;
    setState(() => _esperandoClave = false);
    if (falla.isNotEmpty) {
      setState(() => _error = falla);
      return;
    }
    if (clave.isEmpty && _estado?['desatendido'] == true) {
      setState(() => _aviso = 'El equipo todavía no tiene la clave de la sesión (¿apagado o sin el agente 1.13?). '
          'Se conecta de la forma normal: el usuario debe aceptar.');
    }
    connect(context, id, password: clave.isEmpty ? null : clave);
  }

  // ------------------------------------------------------------------ mis sesiones abiertas
  Future<void> _cargarMisSesiones() async {
    _tMis?.cancel();
    if (_SatTecSesion.token.isEmpty) return;
    final j = await _api({'op': 'mis_sesiones'});
    if (!mounted) return;
    if (j['ok'] == true) {
      setState(() => _misSesiones = ((j['sesiones'] as List?) ?? []).cast<Map>());
    }
    if (_SatTecSesion.token.isNotEmpty) {
      _tMis = Timer(const Duration(seconds: 30), _cargarMisSesiones);
    }
  }

  /// Lleva la ficha a esa sesión (nota, terminar) y, si se pide, se conecta.
  Future<void> _irASesion(String id, {bool conectar = false}) async {
    if (id.isEmpty) return;
    _idCliente.text = id;
    await _buscar();
    if (!mounted || !conectar) return;
    final est = (_estado?['estado'] ?? '').toString();
    if (est == 'autorizada' || est == 'activa') await _abrirConexion();
  }

  // ------------------------------------------------------------------ seguimiento técnico
  Future<void> _cargarSeguimiento(int t) async {
    if (t <= 0) return;
    final j = await _api({'op': 'avances', 'ticket': t});
    if (!mounted || j['ok'] != true) return;
    setState(() {
      _seg = j;
      _segTicket = t;
      if (_recAv.text.isEmpty) _recAv.text = (j['recomendaciones'] ?? '').toString();
    });
  }

  Future<void> _guardarAvance() async {
    final t = (_estado?['ticket'] as num?)?.toInt() ?? 0;
    if (t <= 0 || _guardandoAv) return;
    if (_resAv.isEmpty) {
      setState(() => _error = 'Escoja el resultado del avance.');
      return;
    }
    setState(() {
      _guardandoAv = true;
      _error = '';
    });
    final cuerpo = <String, dynamic>{'op': 'avance', 'ticket': t, 'tipo': _tipoAv, 'resultado': _resAv, 'texto': _textoAv.text.trim()};
    if (_tipoAv == 'cierre') cuerpo['recomendaciones'] = _recAv.text.trim();
    final j = await _api(cuerpo);
    if (!mounted) return;
    setState(() => _guardandoAv = false);
    if (j['ok'] == true) {
      setState(() {
        _seg = j;
        _segTicket = t;
        _textoAv.clear();
        _resAv = '';
        _tipoAv = 'diagnostico';
      });
      showToast((j['msg'] ?? 'Avance guardado').toString());
    } else {
      setState(() => _error = (j['error'] ?? 'No se pudo guardar el avance.').toString());
    }
  }

  static const Map<String, String> _iconosAv = {
    'diagnostico': '🔍', 'reparacion': '🔧', 'cambio_pieza': '🔩', 'prueba': '🧪', 'otro': '📝', 'cierre': '✅'
  };

  List<Widget> _vistaSeguimiento() {
    final g = _seg;
    if (g == null) {
      return [const Padding(padding: EdgeInsets.only(top: 10), child: Text('Cargando el seguimiento de la orden…', style: TextStyle(color: SatColors.secondary)))];
    }
    final avs = ((g['avances'] as List?) ?? []).cast<Map>();
    final tipos = ((g['tipos'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), v.toString()));
    final res = ((g['resultados'] as Map?) ?? {}).map((k, v) => MapEntry(k.toString(), v.toString()));
    final esCierre = _tipoAv == 'cierre';
    final w = <Widget>[
      const SizedBox(height: 14),
      const Text('📋 Seguimiento técnico', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: SatColors.text)),
      const Text('Cada avance queda con fecha, hora y técnico, y el cliente lo ve en el acta. El último es el ✅ Cierre / informe final.',
          style: TextStyle(fontSize: 12.5, color: SatColors.secondary)),
      for (final a in avs)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: a['tipo'] == 'cierre' ? const Color(0xFFF0FDF4) : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_iconosAv[a['tipo']] ?? '📝'} ${a['tipo_txt']} · ${a['resultado_txt']}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: SatColors.text)),
            Text('${a['fecha']} · ${a['autor']}', style: const TextStyle(fontSize: 11.5, color: SatColors.secondary)),
            const SizedBox(height: 2),
            Text((a['texto'] ?? '').toString(), style: const TextStyle(color: SatColors.text)),
          ]),
        ),
    ];
    if (g['abierta'] != true) {
      w.add(_cajaMensaje('La orden ${g['orden']} está ${g['estado']}: el seguimiento ya no admite avances.'));
      return w;
    }
    w.addAll([
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: tipos.containsKey(_tipoAv) ? _tipoAv : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Tipo de avance', filled: true, fillColor: Colors.white, border: OutlineInputBorder(), isDense: true),
            items: [for (final e in tipos.entries) DropdownMenuItem(value: e.key, child: Text('${_iconosAv[e.key] ?? ''} ${e.value}'))],
            onChanged: (v) => setState(() {
              _tipoAv = v ?? 'diagnostico';
              if (_tipoAv == 'cierre' && _resAv.isEmpty) _resAv = 'exitoso';
            }),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: DropdownButtonFormField<String>(
            value: res.containsKey(_resAv) ? _resAv : null,
            isExpanded: true,
            hint: const Text('— Escoja —'),
            decoration: const InputDecoration(labelText: 'Resultado', filled: true, fillColor: Colors.white, border: OutlineInputBorder(), isDense: true),
            items: [for (final e in res.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
            onChanged: (v) => setState(() => _resAv = v ?? ''),
          ),
        ),
      ]),
      const Padding(
        padding: EdgeInsets.only(top: 6),
        child: Text('👁 El cliente ve este texto en el acta. Lo que sea solo para la oficina va en Notas, en SAT.',
            style: TextStyle(fontSize: 12, color: SatColors.secondary)),
      ),
      _campo(_textoAv, esCierre ? 'Informe final: cómo queda el equipo y qué se le hizo *' : '¿Qué encontró o qué hizo? *',
          pista: esCierre
              ? 'Ej.: Se limpió la cola de impresión y se reinstaló el controlador; imprime normal.'
              : 'Ej.: Se cambió la fuente; enciende pero se reinicia al cargar el sistema. Se deja en prueba.',
          lineas: 3),
      if (esCierre) _campo(_recAv, 'Recomendaciones (opcional)', lineas: 2),
      const SizedBox(height: 8),
    ]);
    return w;
  }

  Future<void> _terminar() async {
    final f = _ficha;
    if (f == null) return;
    final j = await _api({'op': 'terminar', 'id': f['id']});
    if (!mounted) return;
    setState(() => _aviso = (j['msg'] ?? j['error'] ?? '').toString());
    await _consultarEstado();
    _cargarMisSesiones();
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
                        if (_SatTecSesion.token.isEmpty && _aviso.isNotEmpty) _cajaMensaje(_aviso),
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
      if (_misSesiones.isNotEmpty) _vistaMisSesiones(),
    ]);
  }

  Widget _vistaMisSesiones() {
    final actual = (_ficha?['id'] ?? '').toString();
    return _tarjeta([
      Row(children: [
        Expanded(
          child: Text('Mis sesiones abiertas (${_misSesiones.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, color: SatColors.text)),
        ),
        IconButton(
          tooltip: 'Actualizar',
          icon: const Icon(Icons.refresh, size: 20),
          onPressed: _cargarMisSesiones,
        ),
      ]),
      for (final s in _misSesiones)
        Container(
          margin: const EdgeInsets.only(top: 6),
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            color: (s['id'] ?? '').toString() == actual ? SatColors.infoSurface : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                    '${s['estado'] == 'activa' ? '🟢' : '🔓'} ${s['orden']} · ${s['cliente']}${s['desatendido'] == true ? ' · 🔑' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w600, color: SatColors.text)),
                Text(
                    '${s['equipo']}${(s['id'] ?? '').toString().isNotEmpty ? ' · ID ${s['id']}' : ''} · '
                    '${s['estado'] == 'activa' ? 'quedan' : 'para conectarse'} ${s['restan_min']} min',
                    style: const TextStyle(fontSize: 12.5, color: SatColors.secondary)),
              ]),
            ),
            if ((s['id'] ?? '').toString().isNotEmpty) ...[
              TextButton(
                onPressed: _ocupado ? null : () => _irASesion(s['id'].toString()),
                child: const Text('Ver'),
              ),
              TextButton(
                onPressed: _ocupado || _esperandoClave ? null : () => _irASesion(s['id'].toString(), conectar: true),
                child: const Text('Conectar'),
              ),
            ],
          ]),
        ),
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
          SatButton(
              label: _esperandoClave
                  ? 'Esperando la clave del equipo…'
                  : (_estado?['desatendido'] == true ? 'Conectar (acceso desatendido 🔑)' : 'Conectar al equipo'),
              icon: Icons.desktop_windows_rounded,
              kind: SatButtonKind.primary,
              onPressed: _esperandoClave ? null : _abrirConexion),
        if (hayMiSesion && _estado?['desatendido'] == true)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text('Equipo con acceso desatendido autorizado por el cliente: entra con la clave de esta sesión, '
                'sin que nadie acepte. Puede reconectarse mientras la sesión siga abierta.',
                style: TextStyle(fontSize: 12.5, color: SatColors.secondary)),
          ),
        if (hayMiSesion) ..._vistaSeguimiento(),
        if (hayMiSesion)
          Row(children: [
            if (_seg?['abierta'] == true)
              Expanded(
                  child: SatButton(
                      label: _guardandoAv ? 'Guardando…' : 'Guardar avance',
                      icon: Icons.save_outlined,
                      kind: SatButtonKind.primary,
                      onPressed: _guardandoAv ? null : _guardarAvance)),
            if (_seg?['abierta'] == true) const SizedBox(width: 8),
            Expanded(child: SatButton(label: 'Terminar sesión', icon: Icons.stop_circle_outlined, kind: SatButtonKind.danger, onPressed: _terminar)),
          ]),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () {
            final t = (_estado?['ticket'] as num?)?.toInt() ?? 0;
            launchUrl(Uri.parse(t > 0 ? '$kSatPortalUrl/ticket.php?id=$t' : kSatPortalUrl));
          },
          child: const Text('Abrir la orden en SAT (fotos, firma y cierre)'),
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
