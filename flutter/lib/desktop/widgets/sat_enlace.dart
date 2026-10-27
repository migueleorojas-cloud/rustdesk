// SAT Remoto Técnico: enlace «sat-remoto-tecnico://sat/<ID>» que abre el botón «Conectar» de SAT web.
// Solo en la compilación de técnicos (saliente). El enlace NO conecta por sí solo: deja el ID para que la pantalla
// de técnicos lo busque en SAT y se conecte con las reglas de siempre (sesión en SAT, clave desatendida, etc.).
// Sin dart:io a propósito: lo importa common.dart, que también se compila para web.

import 'package:flutter/foundation.dart';

import '../../models/platform_model.dart';

class SatEnlace {
  /// ID del equipo pedido desde SAT, pendiente de atender por la pantalla de técnicos.
  static final ValueNotifier<String> id = ValueNotifier<String>('');

  /// La pantalla de técnicos ya está construida (puede traerse al frente).
  static bool listo = false;
}

/// Si es un enlace de SAT para la app de técnicos, guarda el ID y devuelve true (el resto de handleUriLink no debe
/// tratarlo como una conexión directa).
bool satTecnicoTomarEnlace({List<String>? cmdArgs, Uri? uri, String? uriString}) {
  if (!bind.isOutgoingOnly()) return false;
  Uri? u = uri;
  if (u == null && uriString != null) u = Uri.tryParse(uriString);
  if (u == null && cmdArgs != null && cmdArgs.isNotEmpty) u = Uri.tryParse(cmdArgs.first);
  if (u == null) return false;
  final prefijo = bind.mainUriPrefixSync();
  if ('${u.scheme}://' != prefijo || u.host != 'sat') return false;
  final id = u.pathSegments.isNotEmpty ? u.pathSegments.first.replaceAll(RegExp(r'[^0-9]'), '') : '';
  if (id.length < 6 || id.length > 12) return false;
  SatEnlace.id.value = '';
  SatEnlace.id.value = id;
  return true;
}
