/// Helpers for storage object naming and content types.
class FileUtils {
  const FileUtils._();

  static const cadExtensions = <String>['step', 'stp', 'ifc', 'ocx', 'obj', 'stl', 'ply', 'glb', 'gltf'];
  static const documentExtensions = <String>['pdf', 'png', 'jpg', 'jpeg', 'webp', 'txt', 'docx', 'xlsx'];

  /// Storage-safe file name: keeps letters, digits, dot, dash, underscore.
  static String safeName(String name) {
    final cleaned = name.trim().replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    return cleaned.isEmpty ? 'file' : cleaned;
  }

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  static String contentType(String name) {
    switch (extensionOf(name)) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'txt':
        return 'text/plain';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'glb':
        return 'model/gltf-binary';
      case 'gltf':
        return 'model/gltf+json';
      case 'ifc':
        return 'application/x-step';
      case 'step':
      case 'stp':
        return 'model/step';
      case 'obj':
        return 'model/obj';
      case 'stl':
        return 'model/stl';
      case 'ocx':
        return 'application/xml';
      default:
        return 'application/octet-stream';
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
