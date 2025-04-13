import 'dart:async';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flutter/services.dart' show Uint8List, rootBundle;

void main() async {
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  int ticks = 0;
  late final RenderingEngine renderingEngine;

  @override
  void initState() {
    super.initState();
    renderingEngine = RenderingEngine();
    _ticker = Ticker(_onTick)..start();
    loadAssets();
  }

  void _onTick(Duration elapsed) {
    ticks++;
    setState(() {
      renderingEngine.updatePixelMap();
    });
  }

  void loadAssets() async {
    renderingEngine.triangles =
        await loadObjWithMtl('assets/plane.obj', 'assets/plane.mtl');
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = renderingEngine._camera;
    return MaterialApp(
      title: 'Flutter 3D Demo',
      home: Scaffold(
        backgroundColor: Color.fromARGB(255, 171, 189, 189),
        appBar: AppBar(title: const Text('CPU rasterization in Flutter')),
        body: Stack(
          alignment: Alignment.topLeft,
          children: [
            Align(
                alignment: Alignment.topCenter,
                child: PixelMapWidget(pixelMap: renderingEngine.getPixelMap())),
            Align(
              alignment: Alignment.topRight,
              child: Column(
                children: [
                  ElevatedButton(
                      onPressed: () {
                        renderingEngine._pixelMap.width = 100;
                        renderingEngine._pixelMap.height = 100;
                        renderingEngine._pixelMap.clear();
                      },
                      child: Text("100X100")),
                  ElevatedButton(
                      onPressed: () {
                        renderingEngine._pixelMap.width = 400;
                        renderingEngine._pixelMap.height = 400;
                        renderingEngine._pixelMap.clear();
                      },
                      child: Text("400X400")),
                  ElevatedButton(
                      onPressed: () {
                        renderingEngine._pixelMap.width = 800;
                        renderingEngine._pixelMap.height = 800;
                        renderingEngine._pixelMap.clear();
                      },
                      child: Text("800X800"))
                ],
              ),
            ),
            Align(
              alignment: Alignment.bottomRight,
              child: Container(
                color: Color.fromARGB(100, 200, 200, 200),
                child: Text(
                  style: TextStyle(fontSize: 10),
                  "Frame count: $ticks \n\n"
                  "Triangle count: ${renderingEngine.triangles.length}\n"
                  "\n"
                  "View matrix \n${renderingEngine._camera.getViewMatrix()}"
                  "\n"
                  "Projection matrix \n${renderingEngine.ppm.toString()}"
                  "\n"
                  "projection matrix * view matrix \n"
                  "${(renderingEngine.ppm * renderingEngine._camera.getViewMatrix()).toString()}",
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ElevatedButton(
                      onPressed: () => camera.moveForward(),
                      child: const Text('Forward')),
                  ElevatedButton(
                      onPressed: () => camera.moveBackward(),
                      child: const Text('Back')),
                  ElevatedButton(
                      onPressed: () => camera.moveLeft(),
                      child: const Text('Left')),
                  ElevatedButton(
                      onPressed: () => camera.moveRight(),
                      child: const Text('Right')),
                  ElevatedButton(
                      onPressed: () => camera.moveUp(),
                      child: const Text('Up')),
                  ElevatedButton(
                      onPressed: () => camera.moveDown(),
                      child: const Text('Down')),
                  ElevatedButton(
                      onPressed: () => camera.rotateLeft(0.05),
                      child: const Text('Rotate left')),
                  ElevatedButton(
                      onPressed: () => camera.rotateRight(0.05),
                      child: const Text('Rotate right')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class RenderingEngine {
  final PixelMap _pixelMap = PixelMap();
  final Camera _camera = Camera();

  List<Triangle3d> triangles = [];

  void updatePixelMap() {
    if (triangles.isEmpty) return;
    _pixelMap.clear();
    final Matrix4 projection = ppm * _camera.getViewMatrix();

    for (var triangle in triangles) {
      final p1 = projection.transform(triangle.p1.clone());
      final p2 = projection.transform(triangle.p2.clone());
      final p3 = projection.transform(triangle.p3.clone());

      if (p1.w != 0) p1.setValues(p1.x / p1.w, p1.y / p1.w, p1.z / p1.w, 1.0);
      if (p2.w != 0) p2.setValues(p2.x / p2.w, p2.y / p2.w, p2.z / p2.w, 1.0);
      if (p3.w != 0) p3.setValues(p3.x / p3.w, p3.y / p3.w, p3.z / p3.w, 1.0);

      if (isOutside(p1) && isOutside(p2) && isOutside(p3)) continue;
      _pixelMap.drawTriangle(p1, p2, p3, triangle.color);
    }
    _pixelMap.generateImage();
  }

  bool isOutside(Vector4 p) =>
      p.x < -1 || p.x > 1 || p.y < -1 || p.y > 1 || p.z < 0 || p.z > 1;

  PixelMap getPixelMap() {
    return _pixelMap;
  }

  Matrix4 get ppm {
    const fov = 90.0;
    const aspect = 1.0;
    const near = 0.1;
    const far = 100.0;
    final f = 1 / tan(radians(fov) / 2);

    return Matrix4.zero()
      ..setEntry(0, 0, f / aspect)
      ..setEntry(1, 1, f)
      ..setEntry(2, 2, far / (far - near))
      ..setEntry(2, 3, -far * near / (far - near))
      ..setEntry(3, 2, 1);
  }
}

class Camera {
  Vector3 eye = Vector3(20, 15, -12.0);
  Vector3 center = Vector3(20.7, 15.3, -12.5);
  Vector3 up = Vector3(0, 1, 0);

  Matrix4 getViewMatrix() {
    final f = (center - eye).normalized();
    final s = f.cross(up).normalized();
    final u = s.cross(f);

    return Matrix4(
      s.x,
      u.x,
      -f.x,
      0,
      s.y,
      u.y,
      -f.y,
      0,
      s.z,
      u.z,
      -f.z,
      0,
      -s.dot(eye),
      -u.dot(eye),
      f.dot(eye),
      1,
    );
  }

  final moveSpeed = 1.0;

  void moveForward() {
    final dir = (center - eye).normalized();
    eye -= dir * moveSpeed;
    center -= dir * moveSpeed;
  }

  void moveBackward() {
    final dir = (center - eye).normalized();
    eye += dir * moveSpeed;
    center += dir * moveSpeed;
  }

  void moveLeft() {
    final dir = (center - eye).normalized();
    final left = up.cross(dir).normalized();
    eye += left * moveSpeed;
    center += left * moveSpeed;
  }

  void moveRight() {
    final dir = (center - eye).normalized();
    final right = dir.cross(up).normalized();
    eye += right * moveSpeed;
    center += right * moveSpeed;
  }

  void moveUp() {
    final move = up.normalized() * moveSpeed;
    eye += move;
    center += move;
  }

  void moveDown() {
    final move = up.normalized() * moveSpeed;
    eye -= move;
    center -= move;
  }

  void rotateLeft(double angleRadians) {
    final direction = (center - eye);
    final rotation = Quaternion.axisAngle(up, angleRadians);
    final newDir = rotation.rotated(direction);
    center = eye + newDir;
  }

  void rotateRight(double angleRadians) {
    rotateLeft(-angleRadians);
  }
}

class Triangle3d {
  final Vector4 p1;
  final Vector4 p2;
  final Vector4 p3;
  final Color color;

  Triangle3d(this.p1, this.p2, this.p3, this.color);

  @override
  String toString() {
    return "$p1\n$p2\n$p3\n";
  }
}

class PixelMap {
  ui.Image? image;
  int width = 800;
  int height = 800;
  late Float64List distances = Float64List(width * height);
  late Uint8List buffer = Uint8List(width * height * 4);

  PixelMap() {
    clear();
  }

  void clear() {
    if (distances.length != width) {
      // in practise means, resolution has been updated
      distances = Float64List(width * height);
      buffer = Uint8List(width * height * 4);
    }

    for (int i = 0; i < distances.length; i += 1) {
      distances[i] = double.infinity;
    }

    for (int i = 0; i < buffer.length; i += 4) {
      buffer[i] = 170; // R
      buffer[i + 1] = 210; // G
      buffer[i + 2] = 250; // B
      buffer[i + 3] = 255; // A
    }
  }

  void drawTriangle(Vector4 p1, Vector4 p2, Vector4 p3, Color baseColor) {
    int sx(double x) => ((x + 1) * 0.5 * width).toInt();
    int sy(double y) => ((1 - (y + 1) * 0.5) * height).toInt();

    final sx1 = sx(p1.x), sy1 = sy(p1.y);
    final sx2 = sx(p2.x), sy2 = sy(p2.y);
    final sx3 = sx(p3.x), sy3 = sy(p3.y);

    final minX = max(0, min(sx1, min(sx2, sx3)));
    final maxX = min(width - 1, max(sx1, max(sx2, sx3)));
    final minY = max(0, min(sy1, min(sy2, sy3)));
    final maxY = min(height - 1, max(sy1, max(sy2, sy3)));
    if (minX > maxX || minY > maxY) return;

    final a = Vector3(p2.x - p1.x, p2.y - p1.y, p2.z - p1.z);
    final b = Vector3(p3.x - p1.x, p3.y - p1.y, p3.z - p1.z);
    final normal = a.cross(b).normalized();
    final lightDir = Vector3(0, 1, 0);
    double intensity = (0.4 + max(0.0, normal.dot(lightDir))).clamp(0.0, 1.0);
    final cr = (baseColor.red * intensity).toInt();
    final cg = (baseColor.green * intensity).toInt();
    final cb = (baseColor.blue * intensity).toInt();

    final dx1 = sx1.toDouble(), dy1 = sy1.toDouble();
    final dx2 = sx2.toDouble(), dy2 = sy2.toDouble();
    final dx3 = sx3.toDouble(), dy3 = sy3.toDouble();

    final denom = ((dy2 - dy3) * (dx1 - dx3) + (dx3 - dx2) * (dy1 - dy3));
    if (denom == 0) return;
    final invDenom = 1.0 / denom;

    for (int y = minY; y <= maxY; y++) {
      final py = y.toDouble();
      for (int x = minX; x <= maxX; x++) {
        final px = x.toDouble();

        final u =
            ((dy2 - dy3) * (px - dx3) + (dx3 - dx2) * (py - dy3)) * invDenom;
        final v =
            ((dy3 - dy1) * (px - dx3) + (dx1 - dx3) * (py - dy3)) * invDenom;
        final w = 1 - u - v;

        if (u >= 0 && v >= 0 && w >= 0) {
          final z = u * p1.z + v * p2.z + w * p3.z;
          final distanceIndex = (y * width + x);
          if (z < distances[distanceIndex]) {
            if (x < 0 || x >= width || y < 0 || y >= height) return;
            final index = (y * width + x) * 4;
            distances[distanceIndex] = z;
            buffer[index] = cr;
            buffer[index + 1] = cg;
            buffer[index + 2] = cb;
            buffer[index + 3] = 255;
          }
        }
      }
    }
  }

  void generateImage() {
    ui.decodeImageFromPixels(
      buffer,
      width,
      height,
      ui.PixelFormat.rgba8888,
      (ui.Image img) {
        image = img;
      },
    );
  }
}

class PixelMapWidget extends StatelessWidget {
  final PixelMap pixelMap;

  const PixelMapWidget({super.key, required this.pixelMap});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(800, 800),
      painter: _PixelMapPainter(pixelMap),
    );
  }
}

class _PixelMapPainter extends CustomPainter {
  final PixelMap pixelMap;

  _PixelMapPainter(this.pixelMap);

  @override
  void paint(Canvas canvas, Size size) {
    if (pixelMap.image != null) {
      final paint = Paint();
      canvas.drawImageRect(
        pixelMap.image!,
        Rect.fromLTWH(
            0, 0, pixelMap.width.toDouble(), pixelMap.height.toDouble()),
        Rect.fromLTWH(0, 0, size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

Future<List<Triangle3d>> loadObjWithMtl(String objPath, String mtlPath) async {
  final mtl = await loadMtl(mtlPath);
  final obj = await rootBundle.loadString(objPath);
  final lines = obj.split('\n');

  final List<Vector4> vertices = [];
  final List<Triangle3d> triangles = [];
  String currentMaterial = 'default';

  for (final line in lines) {
    if (line.startsWith('v ')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      vertices.add(Vector4(
        double.parse(parts[1]),
        double.parse(parts[2]),
        double.parse(parts[3]),
        1.0,
      ));
    } else if (line.startsWith('usemtl')) {
      currentMaterial = line.substring(6).trim(); // Trim name from obj
    } else if (line.startsWith('f ')) {
      final indices = line
          .substring(2)
          .split(' ')
          .map((s) => int.parse(s.split('/')[0]) - 1)
          .toList();

      for (int i = 1; i < indices.length - 1; i++) {
        triangles.add(Triangle3d(
          vertices[indices[0]],
          vertices[indices[i]],
          vertices[indices[i + 1]],
          mtl[currentMaterial] ?? Color.fromARGB(255, 45, 58, 37),
        ));
      }
    }
  }

  return triangles;
}

Future<Map<String, Color>> loadMtl(String assetPath) async {
  final content = await rootBundle.loadString(assetPath);
  final lines = content.split('\n');
  final Map<String, Color> materials = {};

  String? currentName;

  for (final line in lines) {
    final trimmed = line.trim();
    if (trimmed.startsWith('newmtl')) {
      currentName = trimmed.substring(6).trim();
    } else if (trimmed.startsWith('Kd') && currentName != null) {
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final r = (double.parse(parts[1]) * 255).toInt();
        final g = (double.parse(parts[2]) * 255).toInt();
        final b = (double.parse(parts[3]) * 255).toInt();
        materials[currentName] = Color.fromARGB(255, r, g, b);
      }
    }
  }

  return materials;
}

