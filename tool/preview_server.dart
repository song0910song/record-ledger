// 临时静态服务器 —— 用于本地预览 build/web（用 Edge 打开）。用完可删。
import 'dart:io';

Future<void> main(List<String> args) async {
  final root = Directory(args.isNotEmpty ? args[0] : 'build/web').absolute;
  final port = args.length > 1 ? int.parse(args[1]) : 8765;

  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
  stdout.writeln('Serving ${root.path} at http://127.0.0.1:$port/');

  await for (final req in server) {
    var rel = Uri.decodeComponent(req.uri.path);
    if (rel == '/' || rel.isEmpty) rel = '/index.html';
    var file =
        File('${root.path}${rel.replaceAll('/', Platform.pathSeparator)}');
    if (!file.existsSync()) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      continue;
    }
    String type = 'application/octet-stream';
    final ext = file.path.split('.').last.toLowerCase();
    if (ext == 'html') type = 'text/html; charset=utf-8';
    if (ext == 'js') type = 'text/javascript';
    if (ext == 'json') type = 'application/json';
    if (ext == 'wasm') type = 'application/wasm';
    if (ext == 'png') type = 'image/png';
    req.response.headers.set('Content-Type', type);
    // 让 SharedWorker 可用
    req.response.headers.set('Cross-Origin-Opener-Policy', 'same-origin');
    await req.response.addStream(file.openRead());
    await req.response.close();
  }
}
