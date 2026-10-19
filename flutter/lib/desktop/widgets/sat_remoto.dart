// SAT Remoto (OfficeTech): piezas visuales compartidas por la ventana principal
// (desktop_home_page.dart) y la ventana de conexiones (server_page.dart).
// Colores y medidas tomados de design-tokens.json del kit de marca.
// Solo presentación: toda acción llama a los mismos métodos del motor que ya
// usaba RustDesk (aceptar, rechazar, permisos, desconectar).

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
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

/// Técnico confirmado por SAT para la solicitud en curso.
class SatTecnicoVerificado {
  final String nombre;
  final String orden;
  const SatTecnicoVerificado(this.nombre, this.orden);
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
    if (j is Map && j['verificado'] == true) {
      final nombre = (j['tecnico'] ?? '').toString().trim();
      if (nombre.isEmpty) return null;
      return SatTecnicoVerificado(nombre, (j['orden'] ?? '').toString().trim());
    }
  } catch (_) {}
  return null;
}

/// Sello verde «Técnico verificado por SAT» (solo cuando SAT lo confirmó).
class SatSelloVerificado extends StatelessWidget {
  final String orden;
  const SatSelloVerificado({Key? key, required this.orden}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SatColors.success.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.verified_user, size: 14, color: SatColors.success),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              orden.isEmpty
                  ? 'Técnico verificado por SAT'
                  : 'Técnico verificado por SAT · Orden $orden',
              style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: SatColors.success),
            ),
          ),
        ],
      ),
    );
  }
}
