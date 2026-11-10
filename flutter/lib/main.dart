// Flutter Check: Flutter's own renderer -- Impeller, on Metal: on an iPhone the only one Flutter has -- drawing known
// pictures that are read back and compared, and a moving scene timed. It runs by itself when opened; the results are
// on the screen and in Documents/fluttercheck.log, one line a check (VERDICT<TAB>name<TAB>detail), "done" at the end.
// The screen stays dark: the phone it was written for has an OLED panel.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CheckApp());
}

class Result {
  Result(this.name, this.verdict, this.detail);
  final String name;
  final String verdict; // PASS, FAIL
  final String detail;
}

/// Documents/fluttercheck.log, started afresh at each launch, and the console.
class Log {
  Log() {
    // (where the log goes, said on the console: on the K40 port it was in no container's Documents, 2026-11-10)
    final home = Platform.environment['HOME'];
    debugPrint('fluttercheck: HOME is ${home ?? "not set"}');
    if (home == null) return;
    try {
      final file = File('$home/Documents/fluttercheck.log');
      file.parent.createSync(recursive: true);
      file.writeAsStringSync('');
      _file = file;
      debugPrint('fluttercheck: log at ${file.path}');
    } catch (e) {
      debugPrint('fluttercheck: no log file: $e');
    }
  }

  File? _file;

  void say(String line) {
    debugPrint('fluttercheck: $line');
    try {
      _file?.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}

/// The pixels of an image as Flutter reads them back (RGBA, premultiplied).
class Pixels {
  Pixels(this.data, this.width, this.height);
  final ByteData data;
  final int width, height;

  List<int> at(int x, int y) {
    final i = (y * width + x) * 4;
    return [data.getUint8(i), data.getUint8(i + 1), data.getUint8(i + 2), data.getUint8(i + 3)];
  }

  static Future<Pixels?> of(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data == null ? null : Pixels(data, image.width, image.height);
  }
}

String rgba(List<int> p) => '${p[0]} ${p[1]} ${p[2]} ${p[3]}';

bool near(List<int> p, List<int> want, int slack) {
  for (var i = 0; i < 4; i++) {
    if ((p[i] - want[i]).abs() > slack) return false;
  }
  return true;
}

/// A picture made into an image of w x h and the given pixels compared: (x, y, RGBA, what it is, slack).
Future<Result> expectPicture(String name, ui.Picture picture, int w, int h,
    List<(int, int, List<int>, String, int)> want) async {
  final image = await picture.toImage(w, h);
  final px = await Pixels.of(image);
  image.dispose();
  picture.dispose();
  if (px == null) return Result(name, 'FAIL', 'no pixels came back (toByteData gave null)');
  final wrong = <String>[];
  for (final (x, y, color, what, slack) in want) {
    final p = px.at(x, y);
    if (!near(p, color, slack)) wrong.add('$what at ($x,$y) is ${rgba(p)}, want ${rgba(color)}');
  }
  return wrong.isEmpty
      ? Result(name, 'PASS', 'all ${want.length} pixels checked are right')
      : Result(name, 'FAIL', wrong.join('; '));
}

/// Rectangles, a circle and a clip path: solid colours where they must be.
Future<Result> checkShapes() {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = const Color(0xFF000000));
  c.drawRect(const Rect.fromLTWH(0, 0, 32, 32), Paint()..color = const Color(0xFFFF0000));
  c.drawRect(const Rect.fromLTWH(32, 0, 32, 32), Paint()..color = const Color(0xFF00FF00));
  c.drawCircle(const Offset(16, 48), 12, Paint()..color = const Color(0xFF0000FF));
  c.save();
  c.clipPath(Path()
    ..moveTo(32, 32)
    ..lineTo(64, 32)
    ..lineTo(64, 64)
    ..close());
  c.drawRect(const Rect.fromLTWH(32, 32, 32, 32), Paint()..color = const Color(0xFFFFFFFF));
  c.restore();
  return expectPicture('shapes', recorder.endRecording(), 64, 64, [
    (8, 8, [255, 0, 0, 255], 'the red square', 2),
    (48, 8, [0, 255, 0, 255], 'the green square', 2),
    (16, 48, [0, 0, 255, 255], "the blue circle's middle", 2),
    (2, 62, [0, 0, 0, 255], 'black outside the circle', 2),
    (60, 36, [255, 255, 255, 255], 'the white triangle (a clip path)', 2),
    (36, 60, [0, 0, 0, 255], 'black outside the clip', 2),
  ]);
}

/// A linear gradient (Impeller dithers it: a few levels of slack) and a layer drawn at half opacity.
Future<Result> checkLayers() {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = const Color(0xFF000000));
  c.drawRect(
      const Rect.fromLTWH(0, 0, 64, 32),
      Paint()
        ..shader = ui.Gradient.linear(
            const Offset(0, 0), const Offset(64, 0), [const Color(0xFFFF0000), const Color(0xFF0000FF)]));
  c.saveLayer(const Rect.fromLTWH(0, 32, 64, 32), Paint()..color = const Color(0x80000000));
  c.drawRect(const Rect.fromLTWH(0, 32, 64, 32), Paint()..color = const Color(0xFFFFFFFF));
  c.restore();
  return expectPicture('layers', recorder.endRecording(), 64, 64, [
    (0, 16, [253, 0, 2, 255], "the gradient's red end", 6),
    (32, 16, [125, 0, 130, 255], "the gradient's middle", 8),
    (63, 16, [2, 0, 253, 255], "the gradient's blue end", 6),
    (32, 48, [128, 128, 128, 255], 'white through a layer at half opacity', 3),
  ]);
}

Future<ui.FragmentProgram?> loadProgram(String asset, List<String> problem) async {
  try {
    return await ui.FragmentProgram.fromAsset(asset);
  } catch (e) {
    problem.add('$e');
    return null;
  }
}

/// The application's own fragment program (shaders/quarters.frag): four quarters, the right way up.
Future<Result> checkShader() async {
  final problem = <String>[];
  final program = await loadProgram('shaders/quarters.frag', problem);
  if (program == null) return Result('shader', 'FAIL', 'the fragment program did not load: ${problem.join()}');
  final shader = program.fragmentShader()
    ..setFloat(0, 64)
    ..setFloat(1, 64);
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..shader = shader);
  final result = await expectPicture('shader', recorder.endRecording(), 64, 64, [
    (16, 16, [255, 0, 0, 255], 'the top left quarter (red)', 2),
    (48, 16, [0, 0, 255, 255], 'the top right quarter (blue)', 2),
    (16, 48, [0, 255, 0, 255], 'the bottom left quarter (green)', 2),
    (48, 48, [255, 255, 255, 255], 'the bottom right quarter (white)', 2),
  ]);
  shader.dispose();
  return result;
}

/// A white square blurred (sigma 4) on black: full in the middle, half at its edge, nothing 3 sigma out, and rising
/// in between.
Future<Result> checkBlur() async {
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(const Rect.fromLTWH(0, 0, 64, 64), Paint()..color = const Color(0xFF000000));
  c.saveLayer(null, Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4));
  c.drawRect(const Rect.fromLTWH(16, 16, 32, 32), Paint()..color = const Color(0xFFFFFFFF));
  c.restore();
  final picture = recorder.endRecording();
  final image = await picture.toImage(64, 64);
  final px = await Pixels.of(image);
  image.dispose();
  picture.dispose();
  if (px == null) return Result('blur', 'FAIL', 'no pixels came back');
  final far = px.at(3, 32)[0], edge = px.at(16, 32)[0], inside = px.at(20, 32)[0], middle = px.at(32, 32)[0];
  final said = 'red at x = 3, 16, 20, 32: $far, $edge, $inside, $middle';
  final ok = middle > 225 && far < 30 && edge > 60 && edge < 200 && far < edge && edge < inside && inside <= middle;
  return Result('blur', ok ? 'PASS' : 'FAIL', ok ? said : '$said (want ~0, ~128, ~215, ~255, rising)');
}

/// An image made from pixels (four colours, 2 x 2) drawn 32 times larger, nearest; then the same through PNG: encoded
/// by Flutter, decoded by Flutter's codec, read back.
Future<Result> checkImage() async {
  final source = Uint8List.fromList([255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255]);
  final made = Completer<ui.Image>();
  ui.decodeImageFromPixels(source, 2, 2, ui.PixelFormat.rgba8888, made.complete);
  final small = await made.future;
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawImageRect(small, const Rect.fromLTWH(0, 0, 2, 2), const Rect.fromLTWH(0, 0, 64, 64),
      Paint()..filterQuality = FilterQuality.none);
  final drawn = await expectPicture('image', recorder.endRecording(), 64, 64, [
    (16, 16, [255, 0, 0, 255], 'the red texel', 2),
    (48, 16, [0, 255, 0, 255], 'the green texel', 2),
    (16, 48, [0, 0, 255, 255], 'the blue texel', 2),
    (48, 48, [255, 255, 255, 255], 'the white texel', 2),
  ]);
  if (drawn.verdict != 'PASS') {
    small.dispose();
    return drawn;
  }
  final png = await small.toByteData(format: ui.ImageByteFormat.png);
  small.dispose();
  if (png == null) return Result('image', 'FAIL', 'drawn right, but no PNG came out of it');
  final codec = await ui.instantiateImageCodec(png.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  final back = await Pixels.of(frame.image);
  frame.image.dispose();
  codec.dispose();
  if (back == null) return Result('image', 'FAIL', 'drawn right; the decoded PNG gave no pixels');
  final wrong = <String>[];
  for (final (x, y, want) in [
    (0, 0, [255, 0, 0, 255]),
    (1, 0, [0, 255, 0, 255]),
    (0, 1, [0, 0, 255, 255]),
    (1, 1, [255, 255, 255, 255]),
  ]) {
    if (!near(back.at(x, y), want, 1)) wrong.add('($x,$y) ${rgba(back.at(x, y))}, want ${rgba(want)}');
  }
  return wrong.isEmpty
      ? Result('image', 'PASS', 'drawn 32x nearest, and back through PNG: every texel right')
      : Result('image', 'FAIL', 'drawn right; through PNG: ${wrong.join('; ')}');
}

/// Text, Latin and CJK (the system's fonts): dark glyphs on white, with edges in between (anti-aliased).
Future<Result> checkText() async {
  final painter = TextPainter(
    text: const TextSpan(text: 'Flutter 渲染', style: TextStyle(fontSize: 24, color: Color(0xFF000000))),
    textDirection: TextDirection.ltr,
  )..layout();
  final recorder = ui.PictureRecorder();
  final c = Canvas(recorder);
  c.drawRect(const Rect.fromLTWH(0, 0, 160, 40), Paint()..color = const Color(0xFFFFFFFF));
  painter.paint(c, const Offset(4, 4));
  final picture = recorder.endRecording();
  final image = await picture.toImage(160, 40);
  final px = await Pixels.of(image);
  image.dispose();
  picture.dispose();
  if (px == null) return Result('text', 'FAIL', 'no pixels came back');
  var dark = 0, between = 0;
  for (var y = 0; y < 40; y++) {
    for (var x = 0; x < 160; x++) {
      final v = px.at(x, y)[0];
      if (v < 64) {
        dark++;
      } else if (v < 192) {
        between++;
      }
    }
  }
  final said = '${painter.width.toStringAsFixed(0)} x ${painter.height.toStringAsFixed(0)} laid out; $dark dark '
      'pixels, $between in between';
  final ok = dark > 150 && dark < 3200 && between > 40;
  return Result('text', ok ? 'PASS' : 'FAIL', ok ? said : '$said (want glyphs: some hundreds dark, edges grey)');
}

class CheckApp extends StatelessWidget {
  const CheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Check',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const CheckPage(),
    );
  }
}

class CheckPage extends StatefulWidget {
  const CheckPage({super.key});

  @override
  State<CheckPage> createState() => _CheckPageState();
}

class _CheckPageState extends State<CheckPage> with SingleTickerProviderStateMixin {
  final _log = Log();
  final _results = <Result>[];
  final _boundary = GlobalKey();
  late final AnimationController _spin = AnimationController(vsync: this, duration: const Duration(seconds: 3));
  bool _live = true;
  String _state = 'starting';

  @override
  void initState() {
    super.initState();
    _log.say('run\t-\tFlutter Check 1.0 (Dart ${Platform.version.split(' ').first})');
    _spin.repeat();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  Future<void> _run(String name, Future<Result> Function() check) async {
    if (mounted) setState(() => _state = name);
    Result r;
    try {
      r = await check().timeout(const Duration(seconds: 30));
    } catch (e) {
      r = Result(name, 'FAIL', 'threw: $e');
    }
    _log.say('${r.verdict}\t${r.name}\t${r.detail}');
    if (mounted) setState(() => _results.add(r));
  }

  Future<void> _runAll() async {
    await _run('frames', _checkFrames);
    await _run('tree', _checkTree);
    await _run('shapes', checkShapes);
    await _run('layers', checkLayers);
    await _run('shader', checkShader);
    await _run('blur', checkBlur);
    await _run('image', checkImage);
    await _run('text', checkText);
    final pass = _results.where((r) => r.verdict == 'PASS').length;
    final fail = _results.length - pass;
    _log.say('done\t-\t$pass pass, $fail fail');
    _spin.stop();
    if (mounted) {
      setState(() {
        _live = false;
        _state = 'done: $pass pass, $fail fail';
      });
    }
  }

  /// Five seconds of the moving scene, timed by Flutter itself (FrameTiming: from vsync to the raster thread's end).
  Future<Result> _checkFrames() async {
    final timings = <ui.FrameTiming>[];
    void take(List<ui.FrameTiming> list) => timings.addAll(list);
    SchedulerBinding.instance.addTimingsCallback(take);
    await Future<void>.delayed(const Duration(seconds: 5));
    // (timings are handed over in batches, about once a second)
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    SchedulerBinding.instance.removeTimingsCallback(take);
    if (timings.length < 2) return Result('frames', 'FAIL', '${timings.length} frames timed in 5 s');
    double ms(Duration d) => d.inMicroseconds / 1000.0;
    final raster = timings.map((t) => ms(t.rasterDuration)).toList()..sort();
    final build = timings.map((t) => ms(t.buildDuration)).toList()..sort();
    final first = timings.first.timestampInMicroseconds(ui.FramePhase.vsyncStart);
    final last = timings.last.timestampInMicroseconds(ui.FramePhase.vsyncStart);
    final rate = last > first ? (timings.length - 1) * 1e6 / (last - first) : 0.0;
    final said = '${timings.length} frames, ${rate.toStringAsFixed(1)} a second; raster median '
        '${raster[raster.length ~/ 2].toStringAsFixed(2)} ms, slowest ${raster.last.toStringAsFixed(2)} ms; build '
        'median ${build[build.length ~/ 2].toStringAsFixed(2)} ms';
    return Result('frames', rate >= 20 ? 'PASS' : 'FAIL', said);
  }

  /// The live widget tree read back (RenderRepaintBoundary.toImage): stripes, and a BackdropFilter blurring the right
  /// half of them -- the left half's stripes as drawn, the right half's run together.
  Future<Result> _checkTree() async {
    final object = _boundary.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return Result('tree', 'FAIL', 'the boundary is not on the screen');
    final image = await object.toImage(pixelRatio: 1.0);
    final px = await Pixels.of(image);
    image.dispose();
    if (px == null) return Result('tree', 'FAIL', 'no pixels came back');
    if (px.width != 128 || px.height != 64) {
      return Result('tree', 'FAIL', 'the boundary came back ${px.width} x ${px.height}, want 128 x 64');
    }
    final dark = px.at(2, 32)[0], grey = px.at(6, 32)[0], b1 = px.at(98, 32)[0], b2 = px.at(102, 32)[0];
    final said = 'stripes $dark and $grey as drawn, $b1 and $b2 under the backdrop blur';
    final ok = dark < 8 && (grey - 0x90).abs() < 6 && b1 > 35 && b1 < 110 && b2 > 35 && b2 < 110 && (b1 - b2).abs() < 40;
    return Result('tree', ok ? 'PASS' : 'FAIL', ok ? said : '$said (want 0, 144, then both ~72)');
  }

  @override
  Widget build(BuildContext context) {
    const dim = Color(0xFF9E9E9E);
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Flutter Check: $_state', style: const TextStyle(color: dim, fontSize: 16)),
              const SizedBox(height: 8),
              if (_live)
                Row(
                  children: [
                    RepaintBoundary(
                      key: _boundary,
                      child: SizedBox(
                        width: 128,
                        height: 64,
                        child: Stack(
                          children: [
                            CustomPaint(size: const Size(128, 64), painter: _Stripes()),
                            Positioned(
                              left: 64,
                              top: 0,
                              width: 64,
                              height: 64,
                              child: ClipRect(
                                child: BackdropFilter(
                                  filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(width: 160, height: 160, child: CustomPaint(painter: _Swarm(_spin))),
                  ],
                ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    for (final r in _results)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Text(
                          '${r.verdict}  ${r.name}: ${r.detail}',
                          style: TextStyle(
                              fontSize: 12, color: r.verdict == 'PASS' ? const Color(0xFF6A9A6A) : const Color(0xFFB06060)),
                        ),
                      ),
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

/// Vertical stripes 4 points wide, black and grey (0x90).
class _Stripes extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dark = Paint()..color = const Color(0xFF000000);
    final grey = Paint()..color = const Color(0xFF909090);
    for (var x = 0.0; x < size.width; x += 8) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 4, size.height), dark);
      canvas.drawRect(Rect.fromLTWH(x + 4, 0, 4, size.height), grey);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 300 dots going round, a new picture every frame: what the frame check times.
class _Swarm extends CustomPainter {
  _Swarm(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF305070);
    final a0 = t.value * 2 * math.pi;
    for (var i = 0; i < 300; i++) {
      final r = 16.0 + (i % 40) * 1.5;
      final a = a0 * (1 + (i % 7) * 0.15) + i;
      canvas.drawCircle(Offset(size.width / 2 + r * math.cos(a), size.height / 2 + r * math.sin(a)), 2.5, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
