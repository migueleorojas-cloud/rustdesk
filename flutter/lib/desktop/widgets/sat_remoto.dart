// SAT Remoto (OfficeTech): piezas visuales compartidas por la ventana principal
// (desktop_home_page.dart) y la ventana de conexiones (server_page.dart).
// Colores y medidas tomados de design-tokens.json del kit de marca.
// Solo presentación: toda acción llama a los mismos métodos del motor que ya
// usaba RustDesk (aceptar, rechazar, permisos, desconectar).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../../models/platform_model.dart';

class SatColors {
  static const brand = Color(0xFFF5920C);
  static const brandHover = Color(0xFFE8890B);
  static const brandPressed = Color(0xFFD77E08);
  static const header = Color(0xFF191919);
  static const body = Color(0xFFFFFFFF);
  static const text = Color(0xFF14181F);
  static const secondary = Color(0xFF667085);
  static const border = Color(0xFFDCE1E8);
  static const surface = Color(0xFFF4F5F7);
  static const success = Color(0xFF0A9D48);
  static const danger = Color(0xFFD92D20);
  static const dangerSurface = Color(0xFFFEF3F2);
  static const info = Color(0xFF175CD3);
  static const infoSurface = Color(0xFFEFF4FF);
  static const disabledFill = Color(0xFFEAECF0);
  static const focus = Color(0xFF175CD3);
}

const String kSatPortalUrl = 'https://sat.officetech.com.co';
const String kSatWebUrl = 'https://www.officetech.com.co';

/// Cabecera negra con el rótulo SAT Remoto y «por OFFICETECH».
class SatHeader extends StatelessWidget {
  final double height;
  const SatHeader({Key? key, this.height = 64}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      header: true,
      label: 'SAT Remoto por OfficeTech',
      child: ExcludeSemantics(
        child: Container(
          height: height,
          color: SatColors.header,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Flexible(
                child: Image.asset(
                  'assets/sat_header_logo.png',
                  height: height * 0.56,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  errorBuilder: (_, __, ___) => const Text('SAT Remoto',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(width: 12),
              Image.asset(
                'assets/sat_por_officetech.png',
                height: height * 0.24,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Text('por OFFICETECH',
                    style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Iniciales del nombre recibido (no es una foto ni un técnico preconfigurado).
String satInitials(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty)
      .toList();
  if (parts.isEmpty) return '?';
  final first = parts.first.characters.first;
  final second = parts.length > 1 ? parts[1].characters.first : '';
  return (first + second).toUpperCase();
}

class SatAvatar extends StatelessWidget {
  final String name;
  final double size;
  const SatAvatar({Key? key, required this.name, this.size = 56})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: SatColors.brand,
          shape: BoxShape.circle,
        ),
        child: Text(
          satInitials(name),
          style: TextStyle(
            color: SatColors.header,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.38,
          ),
        ),
      ),
    );
  }
}

enum SatButtonKind { primary, outline, danger }

/// Botón real (texto, hover, pressed, disabled y foco), no una imagen.
class SatButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final SatButtonKind kind;
  final VoidCallback? onPressed;
  final String? tooltip;

  const SatButton({
    Key? key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.kind = SatButtonKind.outline,
    this.tooltip,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color fg;
    Color bg;
    Color line;
    switch (kind) {
      case SatButtonKind.primary:
        fg = SatColors.header;
        bg = SatColors.brand;
        line = SatColors.brand;
        break;
      case SatButtonKind.danger:
        fg = SatColors.danger;
        bg = SatColors.dangerSurface;
        line = SatColors.danger;
        break;
      case SatButtonKind.outline:
        fg = SatColors.text;
        bg = Colors.white;
        line = SatColors.header;
        break;
    }
    final style = ButtonStyle(
      minimumSize: MaterialStateProperty.all(const Size(64, 44)),
      padding: MaterialStateProperty.all(
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
      elevation: MaterialStateProperty.all(0),
      shape: MaterialStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      textStyle: MaterialStateProperty.all(
          const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
      foregroundColor: MaterialStateProperty.resolveWith((s) =>
          s.contains(MaterialState.disabled) ? SatColors.secondary : fg),
      backgroundColor: MaterialStateProperty.resolveWith((s) {
        if (s.contains(MaterialState.disabled)) return SatColors.disabledFill;
        if (kind == SatButtonKind.primary) {
          if (s.contains(MaterialState.pressed)) return SatColors.brandPressed;
          if (s.contains(MaterialState.hovered)) return SatColors.brandHover;
        }
        return bg;
      }),
      overlayColor: MaterialStateProperty.resolveWith((s) {
        if (kind == SatButtonKind.primary) return Colors.transparent;
        if (s.contains(MaterialState.pressed)) return fg.withOpacity(0.12);
        if (s.contains(MaterialState.hovered)) return fg.withOpacity(0.06);
        return null;
      }),
      side: MaterialStateProperty.resolveWith((s) {
        if (s.contains(MaterialState.focused)) {
          return const BorderSide(color: SatColors.focus, width: 2);
        }
        if (s.contains(MaterialState.disabled)) {
          return const BorderSide(color: SatColors.disabledFill);
        }
        return BorderSide(color: line, width: 1.5);
      }),
    );
    final child = icon == null
        ? Text(label, textAlign: TextAlign.center)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Flexible(child: Text(label, textAlign: TextAlign.center)),
            ],
          );
    final btn = ElevatedButton(onPressed: onPressed, style: style, child: child);
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}

/// Fila de permiso: casilla real conectada al motor. Con [onChanged] nulo la
/// fila se muestra fija (no se ofrece un interruptor que el motor no respete).
class SatPermRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SatPermRow({
    Key? key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final enabled = onChanged != null;
    return MergeSemantics(
      child: InkWell(
        onTap: enabled ? () => onChanged!(!value) : null,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: value,
                onChanged: enabled ? (v) => onChanged!(v ?? false) : null,
                activeColor: SatColors.brand,
                checkColor: SatColors.header,
                fillColor: !enabled && value
                    ? MaterialStateProperty.all(
                        SatColors.brand.withOpacity(0.55))
                    : null,
                side: const BorderSide(color: SatColors.secondary, width: 1.5),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: SatColors.text)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 13, color: SatColors.secondary)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Punto de estado + texto (el estado lo da el motor, no se inventa).
class SatStatusLine extends StatelessWidget {
  final String text;
  final Color color;
  const SatStatusLine({Key? key, required this.text, required this.color})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: SatColors.text)),
        ),
      ],
    );
  }
}

/// Ilustración decorativa (sin comportamiento).
class SatIllustration extends StatelessWidget {
  final double height;
  const SatIllustration({Key? key, this.height = 80}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SvgPicture.asset('assets/sat_equipos.svg', height: height),
    );
  }
}

Future<void> satOpenPortal() async {
  await launchUrl(Uri.parse(kSatPortalUrl));
}

/// Técnico que SAT reconoce para la solicitud en curso.
/// [registrado] = el ID que se conecta es el del perfil del técnico (verificado);
/// si es false, el técnico está en un PC prestado y SAT solo confirma que tiene
/// una sesión abierta en esa orden.
class SatTecnicoVerificado {
  final String nombre;
  final String orden;
  final bool registrado;
  const SatTecnicoVerificado(this.nombre, this.orden, {this.registrado = true});
}

/// Pregunta a SAT si quien pide la conexión ([peerId]) es el técnico de una sesión
/// remota abierta sobre este equipo (remoto_api.php?ep=quien). La dirección sale de la
/// opción audit-server que deja el agente OfficeTech; si no está, se usa el portal SAT.
/// Cualquier error o respuesta sin coincidencia devuelve null: la ventana sigue
/// mostrando «no verificado». Nunca autoriza nada: solo cambia lo que se muestra.
Future<SatTecnicoVerificado?> satConsultarTecnico(String peerId) async {
  try {
    final peer = peerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (peer.isEmpty) return null;
    final myId = (await bind.mainGetMyId()).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    if (myId.isEmpty) return null;
    var base = (await bind.mainGetOption(key: 'audit-server')).trim();
    if (!base.startsWith('https://')) {
      base = '$kSatPortalUrl/remoto_api.php';
    }
    final uri0 = Uri.parse(base);
    final uri = uri0.replace(
        path: uri0.path.replaceAll(RegExp(r'/api/audit.*$'), ''),
        queryParameters: {'ep': 'quien', 'id': myId, 'peer': peer});
    final r = await http.get(uri).timeout(const Duration(seconds: 8));
    if (r.statusCode != 200) return null;
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j is Map) {
      final registrado = j['verificado'] == true;
      if (!registrado && j['nivel'] != 'sesion') return null;
      final nombre = (j['tecnico'] ?? '').toString().trim();
      if (nombre.isEmpty) return null;
      return SatTecnicoVerificado(nombre, (j['orden'] ?? '').toString().trim(),
          registrado: registrado);
    }
  } catch (_) {}
  return null;
}

/// Sello bajo el nombre del técnico (solo cuando SAT respondió).
/// Verde «Técnico verificado por SAT» si el ID es el registrado del técnico;
/// azul «Sesión abierta en SAT» si se conecta desde un PC prestado.
class SatSelloVerificado extends StatelessWidget {
  final String orden;
  final bool registrado;
  const SatSelloVerificado(
      {Key? key, required this.orden, this.registrado = true})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final color = registrado ? SatColors.success : SatColors.info;
    final fondo = registrado ? const Color(0xFFECFDF3) : SatColors.infoSurface;
    final base =
        registrado ? 'Técnico verificado por SAT' : 'Sesión abierta en SAT';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(registrado ? Icons.verified_user : Icons.assignment_turned_in,
              size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              orden.isEmpty ? base : '$base · Orden $orden',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
    );
  }
}


// ===========================================================================
// SAT Remoto #6: autorización y corte desde SAT (SAT v-386, remoto_api.php
// ?ep=estado y ?ep=pedir). Un SatControl por conexión (connId):
//  · al llegar la solicitud pregunta a SAT; sin sesión vigente para quien se
//    conecta, la ventana no ofrece «Aceptar» y deja «Pedir autorización»;
//  · mientras espera, pregunta cada 5 s (la sesión puede abrirse en SAT o el
//    administrador aprobar); con la conexión abierta, cada 30 s: si la sesión
//    dejó de estar vigente (vencida, terminada o cortada en SAT) la cierra.
//  · si SAT no responde, NO bloquea ni corta: lo avisa en pantalla.
//  · un equipo que SAT no administra o con la exigencia apagada en SAT se
//    comporta como antes (solo muestra el técnico si SAT lo confirma).
// ===========================================================================

enum SatAut {
  consultando, // primera consulta en curso: aún no se ofrece «Aceptar»
  autorizado, // sesión vigente en SAT para quien se conecta
  libre, // SAT no exige (o no administra el equipo): como antes
  sinSat, // SAT no respondió: no se bloquea, se avisa
  sinAutorizacion, // sin sesión: no se puede aceptar; puede pedir
  pidiendo, // solicitud enviada, esperando al administrador
  rechazada, // el administrador la rechazó: se cierra
  vencida, // nadie atendió la solicitud a tiempo: puede pedir de nuevo
  cortada, // la sesión dejó de estar vigente con la conexión abierta
}

Future<Uri?> _satApi(Map<String, String> q) async {
  final myId =
      (await bind.mainGetMyId()).replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  if (myId.isEmpty) return null;
  var base = (await bind.mainGetOption(key: 'audit-server')).trim();
  if (!base.startsWith('https://')) {
    base = '$kSatPortalUrl/remoto_api.php';
  }
  final uri0 = Uri.parse(base);
  return uri0.replace(
      path: uri0.path.replaceAll(RegExp(r'/api/audit.*$'), ''),
      queryParameters: {...q, 'id': myId});
}

class SatControl {
  static final Map<int, SatControl> _todos = {};

  /// El control de una conexión; se crea al mostrarse su tarjeta.
  static SatControl de(int connId, String peerId, String peerNombre) =>
      _todos.putIfAbsent(
          connId, () => SatControl._(connId, peerId, peerNombre)..iniciar());

  static SatControl? buscar(int connId) => _todos[connId];

  static void quitar(int connId) {
    _todos.remove(connId)?._detener();
  }

  final int connId;
  final String peer;
  final String peerNombre;
  final estado = SatAut.consultando.obs;
  final tecnico = Rxn<SatTecnicoVerificado>();
  final restante = RxnInt(); // segundos para que venza la sesión
  final ocupado = false.obs; // enviando la solicitud
  final error = ''.obs;
  String _token = '';
  bool _conectado = false;
  bool _terminada = false;
  Timer? _timer;
  DateTime? _restanteDesde;

  SatControl._(this.connId, String peerId, this.peerNombre)
      : peer = peerId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');

  /// ¿Se puede ofrecer «Aceptar»?
  bool get puedeAceptar =>
      estado.value == SatAut.autorizado ||
      estado.value == SatAut.libre ||
      estado.value == SatAut.sinSat;

  /// Segundos que faltan, descontando el tiempo desde la última consulta.
  int? get segundosRestantes {
    final r = restante.value;
    if (r == null || _restanteDesde == null) return r;
    return r - DateTime.now().difference(_restanteDesde!).inSeconds;
  }

  void iniciar() {
    _consultar();
    _programar();
  }

  void _programar() {
    _timer?.cancel();
    if (_terminada) return;
    _timer = Timer.periodic(Duration(seconds: _conectado ? 30 : 5), (_) {
      _consultar();
    });
  }

  /// Lo llama la tarjeta cada segundo con el estado real del motor.
  void marcarConexion({required bool autorizada, required bool desconectada}) {
    if (desconectada) {
      _terminada = true;
      _timer?.cancel();
      return;
    }
    if (autorizada && !_conectado) {
      _conectado = true;
      _programar();
      // Entró con clave (acceso desatendido) sin pasar por «Aceptar»: se confirma ya con SAT y, si no hay sesión
      // vigente para quien se conecta, se corta enseguida en vez de esperar la consulta de los 30 s.
      if (estado.value != SatAut.autorizado && estado.value != SatAut.libre) {
        _consultar();
      }
    }
  }

  void _detener() {
    _terminada = true;
    _timer?.cancel();
  }

  void _cerrarConexion() {
    _terminada = true;
    _timer?.cancel();
    bind.cmCloseConnection(connId: connId);
  }

  Future<void> _consultar() async {
    if (_terminada || peer.isEmpty) {
      if (peer.isEmpty && estado.value == SatAut.consultando) {
        estado.value = SatAut.libre;
      }
      return;
    }
    Map? j;
    try {
      final q = {'ep': 'estado', 'peer': peer};
      if (_token.isNotEmpty) q['token'] = _token;
      final uri = await _satApi(q);
      if (uri != null) {
        final r = await http.get(uri).timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final d = jsonDecode(utf8.decode(r.bodyBytes));
          if (d is Map && d['ok'] == true) j = d;
        }
      }
    } catch (_) {}
    if (_terminada) return;
    if (j == null) {
      // SAT no respondió: nunca se bloquea ni se corta por eso.
      if (!_conectado && estado.value == SatAut.consultando) {
        estado.value = SatAut.sinSat;
      }
      return;
    }
    final vigente = j['vigente'] == true;
    if (vigente) {
      final nombre = (j['tecnico'] ?? '').toString().trim();
      if (nombre.isNotEmpty) {
        tecnico.value = SatTecnicoVerificado(
            nombre, (j['orden'] ?? '').toString().trim(),
            registrado: j['verificado'] == true);
      }
      final r = j['restante'];
      restante.value = r is int ? r : int.tryParse('$r');
      _restanteDesde = DateTime.now();
    }
    final exige = j['exige'] == true && j['gestionado'] == true;
    if (!exige) {
      estado.value = vigente ? SatAut.autorizado : SatAut.libre;
      return;
    }
    if (vigente) {
      estado.value = SatAut.autorizado;
      return;
    }
    // Exige y no hay sesión vigente para quien se conecta.
    tecnico.value = null;
    restante.value = null;
    if (_conectado) {
      estado.value = SatAut.cortada;
      _cerrarConexion();
      return;
    }
    final sol = j['solicitud'];
    final se = sol is Map ? (sol['estado'] ?? '').toString() : '';
    if (se == 'pendiente') {
      estado.value = SatAut.pidiendo;
    } else if (se == 'rechazada') {
      estado.value = SatAut.rechazada;
      final m = sol is Map ? (sol['motivo'] ?? '').toString().trim() : '';
      error.value = m;
      Future.delayed(const Duration(seconds: 6), _cerrarConexion);
      _timer?.cancel();
    } else if (se == 'vencida') {
      estado.value = SatAut.vencida;
      _token = '';
    } else if (se == 'aprobada') {
      // aprobada pero ya no vigente (venció la ventana): pedir de nuevo
      estado.value = SatAut.vencida;
      _token = '';
    } else {
      estado.value = SatAut.sinAutorizacion;
    }
  }

  /// «Pedir autorización»: avisa a los administradores de OfficeTech.
  Future<void> pedir() async {
    if (ocupado.value || _terminada) return;
    ocupado.value = true;
    error.value = '';
    try {
      final uri = await _satApi({'ep': 'pedir'});
      if (uri == null) throw Exception();
      final myId = uri.queryParameters['id'] ?? '';
      final r = await http
          .post(uri.replace(queryParameters: {'ep': 'pedir'}),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(
                  {'id': myId, 'peer': peer, 'nombre': peerNombre}))
          .timeout(const Duration(seconds: 10));
      final d = jsonDecode(utf8.decode(r.bodyBytes));
      if (d is Map && d['ok'] == true) {
        if (d['ya_autorizada'] == true) {
          await _consultar();
        } else {
          _token = (d['token'] ?? '').toString();
          estado.value = SatAut.pidiendo;
        }
      } else {
        error.value = (d is Map ? (d['error'] ?? '') : '').toString();
        if (error.value.isEmpty) error.value = 'SAT no recibió la solicitud.';
      }
    } catch (_) {
      error.value =
          'No se pudo enviar la solicitud a SAT. Revise el internet o llame a OfficeTech.';
    }
    ocupado.value = false;
  }
}

/// Recuadro de estado de la autorización en SAT (bajo los datos del técnico).
class SatAvisoAutorizacion extends StatelessWidget {
  final SatControl control;
  final bool conectado;
  const SatAvisoAutorizacion(
      {Key? key, required this.control, required this.conectado})
      : super(key: key);

  Widget _caja(IconData icono, Color color, Color fondo, String titulo,
      String texto) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: fondo,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color)),
                if (texto.isNotEmpty) const SizedBox(height: 2),
                if (texto.isNotEmpty)
                  Text(texto,
                      style: const TextStyle(
                          fontSize: 13, color: SatColors.text)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const ambar = Color(0xFFB54708);
    const ambarFondo = Color(0xFFFFFAEB);
    return Obx(() {
      final err = control.error.value;
      switch (control.estado.value) {
        case SatAut.consultando:
          return conectado
              ? const SizedBox.shrink()
              : _caja(Icons.hourglass_top, SatColors.secondary,
                  SatColors.surface, 'Verificando con SAT…', '');
        case SatAut.sinSat:
          return conectado
              ? const SizedBox.shrink()
              : _caja(Icons.cloud_off, ambar, ambarFondo,
                  'No se pudo verificar con SAT',
                  'Acepte solo si está esperando a OfficeTech.');
        case SatAut.sinAutorizacion:
          return _caja(
              Icons.block,
              SatColors.danger,
              SatColors.dangerSurface,
              'Sin autorización en SAT',
              'Esta conexión no tiene una sesión abierta en SAT, así que no se puede aceptar. '
                  'Si está esperando a OfficeTech, pulse «Pedir autorización».'
                  '${err.isNotEmpty ? '\n$err' : ''}');
        case SatAut.pidiendo:
          return _caja(Icons.notifications_active, ambar, ambarFondo,
              'Solicitud enviada a OfficeTech',
              'Esperando que un administrador la apruebe. No cierre esta ventana.');
        case SatAut.vencida:
          return _caja(
              Icons.timer_off,
              ambar,
              ambarFondo,
              'La solicitud venció sin respuesta',
              'Puede pedirla de nuevo o llamar a OfficeTech.'
                  '${err.isNotEmpty ? '\n$err' : ''}');
        case SatAut.rechazada:
          return _caja(
              Icons.cancel,
              SatColors.danger,
              SatColors.dangerSurface,
              'OfficeTech rechazó esta conexión',
              '${err.isNotEmpty ? 'Motivo: $err. ' : ''}La ventana se cerrará.');
        case SatAut.cortada:
          return _caja(
              Icons.stop_circle,
              SatColors.danger,
              SatColors.dangerSurface,
              'SAT terminó esta sesión',
              'Se agotó el tiempo autorizado o OfficeTech la cortó. La conexión se cerró.');
        case SatAut.autorizado:
          final s = control.segundosRestantes;
          if (conectado && s != null && s <= 300 && s > 0) {
            final min = (s / 60).ceil();
            return _caja(Icons.schedule, ambar, ambarFondo,
                'La sesión vence en $min min',
                'Al vencer, la conexión se cierra sola. El técnico puede pedir la prórroga en SAT.');
          }
          return const SizedBox.shrink();
        case SatAut.libre:
          return const SizedBox.shrink();
      }
    });
  }
}
