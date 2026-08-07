/// Offline map tile manager.
/// Downloads OpenStreetMap tiles for oblasts or routes.
library;

import 'dart:io';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:fourg_alert/services/routing_service.dart';

class Oblast {
  final String name;
  final String nameUk;
  final double minLat, maxLat, minLon, maxLon;
  const Oblast({
    required this.name, required this.nameUk,
    required this.minLat, required this.maxLat,
    required this.minLon, required this.maxLon,
  });
}

const oblasts = [
  Oblast(name: 'Kyiv Oblast', nameUk: 'Київська', minLat: 49.0, maxLat: 51.5, minLon: 29.0, maxLon: 32.0),
  Oblast(name: 'Kyiv City', nameUk: 'Київ', minLat: 50.2, maxLat: 50.6, minLon: 30.2, maxLon: 30.9),
  Oblast(name: 'Lviv Oblast', nameUk: 'Львівська', minLat: 48.7, maxLat: 50.7, minLon: 22.5, maxLon: 25.5),
  Oblast(name: 'Odesa Oblast', nameUk: 'Одеська', minLat: 45.0, maxLat: 48.0, minLon: 28.0, maxLon: 31.5),
  Oblast(name: 'Kharkiv Oblast', nameUk: 'Харківська', minLat: 48.5, maxLat: 50.5, minLon: 34.5, maxLon: 38.0),
  Oblast(name: 'Dnipro Oblast', nameUk: 'Дніпропетровська', minLat: 47.5, maxLat: 49.5, minLon: 33.0, maxLon: 36.5),
  Oblast(name: 'Zaporizhzhia Oblast', nameUk: 'Запорізька', minLat: 46.0, maxLat: 48.0, minLon: 34.0, maxLon: 37.5),
  Oblast(name: 'Poltava Oblast', nameUk: 'Полтавська', minLat: 48.5, maxLat: 50.5, minLon: 32.0, maxLon: 35.5),
  Oblast(name: 'Vinnytsia Oblast', nameUk: 'Вінницька', minLat: 48.0, maxLat: 49.8, minLon: 27.0, maxLon: 30.0),
  Oblast(name: 'Zhytomyr Oblast', nameUk: 'Житомирська', minLat: 49.5, maxLat: 51.5, minLon: 27.0, maxLon: 30.0),
  Oblast(name: 'Cherkasy Oblast', nameUk: 'Черкаська', minLat: 48.5, maxLat: 50.0, minLon: 29.5, maxLon: 33.0),
  Oblast(name: 'Chernihiv Oblast', nameUk: 'Чернігівська', minLat: 50.0, maxLat: 52.5, minLon: 30.0, maxLon: 34.0),
  Oblast(name: 'Sumy Oblast', nameUk: 'Сумська', minLat: 50.0, maxLat: 52.3, minLon: 33.0, maxLon: 36.0),
  Oblast(name: 'Mykolaiv Oblast', nameUk: 'Миколаївська', minLat: 46.5, maxLat: 48.5, minLon: 30.0, maxLon: 33.5),
  Oblast(name: 'Kherson Oblast', nameUk: 'Херсонська', minLat: 45.5, maxLat: 47.5, minLon: 32.0, maxLon: 35.5),
  Oblast(name: 'Ivano-Frankivsk Oblast', nameUk: 'Івано-Франківська', minLat: 47.8, maxLat: 49.0, minLon: 23.5, maxLon: 26.0),
  Oblast(name: 'Ternopil Oblast', nameUk: 'Тернопільська', minLat: 48.5, maxLat: 50.0, minLon: 24.5, maxLon: 26.5),
  Oblast(name: 'Khmelnytskyi Oblast', nameUk: 'Хмельницька', minLat: 48.4, maxLat: 50.5, minLon: 26.0, maxLon: 28.0),
  Oblast(name: 'Rivne Oblast', nameUk: 'Рівненська', minLat: 50.0, maxLat: 52.0, minLon: 25.0, maxLon: 27.5),
  Oblast(name: 'Volyn Oblast', nameUk: 'Волинська', minLat: 50.3, maxLat: 52.0, minLon: 23.5, maxLon: 26.0),
  Oblast(name: 'Zakarpattia Oblast', nameUk: 'Закарпатська', minLat: 47.8, maxLat: 49.0, minLon: 22.0, maxLon: 24.5),
  Oblast(name: 'Chernivtsi Oblast', nameUk: 'Чернівецька', minLat: 47.7, maxLat: 48.8, minLon: 24.5, maxLon: 27.5),
  Oblast(name: 'Kirovohrad Oblast', nameUk: 'Кіровоградська', minLat: 47.8, maxLat: 49.5, minLon: 31.0, maxLon: 34.0),
];

class DownloadProgress {
  final String id;
  final String label;
  final int totalTiles;
  final int downloadedTiles;
  final bool isComplete;
  final bool isError;
  final String? error;

  const DownloadProgress({
    required this.id, required this.label,
    required this.totalTiles, required this.downloadedTiles,
    this.isComplete = false, this.isError = false, this.error,
  });

  double get progress => totalTiles > 0 ? downloadedTiles / totalTiles : 0;
}

class OfflineTileManager {
  static const _tileUrl = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
  static const maxZoom = 14;
  static const minZoom = 7;

  String? _cacheDir;
  final _active = <String, DownloadProgress>{};

  Future<String> get cacheDir async {
    _cacheDir ??= await _computeCacheDir();
    return _cacheDir!;
  }

  Future<String> _computeCacheDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final d = Directory('${dir.path}/map_tiles');
    await d.create(recursive: true);
    return d.path;
  }

  int estimateOblastSize(Oblast oblast) {
    int total = 0;
    for (int z = minZoom; z <= maxZoom; z++) {
      total += _tileCount(oblast.minLat, oblast.maxLat, oblast.minLon, oblast.maxLon, z);
    }
    return (total * 10) ~/ 1024; // MB
  }

  Future<DownloadProgress> downloadOblast(Oblast oblast) async {
    return _download(
      'oblast_${oblast.name}', oblast.name,
      oblast.minLat, oblast.maxLat, oblast.minLon, oblast.maxLon,
    );
  }

  Future<DownloadProgress> downloadRoute(List<RoutePoint> points, String label) async {
    if (points.isEmpty) {
      return DownloadProgress(
        id: 'route_empty', label: label, totalTiles: 0, downloadedTiles: 0, isComplete: true,
      );
    }
    double minLat = points.first.lat, maxLat = points.first.lat;
    double minLon = points.first.lon, maxLon = points.first.lon;
    for (final p in points) {
      if (p.lat < minLat) minLat = p.lat;
      if (p.lat > maxLat) maxLat = p.lat;
      if (p.lon < minLon) minLon = p.lon;
      if (p.lon > maxLon) maxLon = p.lon;
    }
    minLat -= 0.03; maxLat += 0.03; minLon -= 0.03; maxLon += 0.03;
    return _download('route_${DateTime.now().millisecondsSinceEpoch}', label,
        minLat, maxLat, minLon, maxLon);
  }

  Future<DownloadProgress> _download(
    String id, String label,
    double minLat, double maxLat, double minLon, double maxLon,
  ) async {
    final dir = await cacheDir;

    // Count total tiles
    final allTiles = <(int, int, int)>[];
    for (int z = minZoom; z <= maxZoom; z++) {
      final nw = _latLonToTile(maxLat, minLon, z);
      final se = _latLonToTile(minLat, maxLon, z);
      final xMin = math.min(nw.$1, se.$1);
      final xMax = math.max(nw.$1, se.$1);
      final yMin = math.min(nw.$2, se.$2);
      final yMax = math.max(nw.$2, se.$2);
      final count = (xMax - xMin + 1) * (yMax - yMin + 1);
      if (count > 15000) continue; // skip too-large zoom levels
      for (int x = xMin; x <= xMax; x++) {
        for (int y = yMin; y <= yMax; y++) {
          allTiles.add((z, x, y));
        }
      }
    }

    final total = allTiles.length;
    _active[id] = DownloadProgress(id: id, label: label, totalTiles: total, downloadedTiles: 0);

    int done = 0, errors = 0;
    for (final (z, x, y) in allTiles) {
      try {
        final path = '$dir/$z/$x/$y.png';
        if (File(path).existsSync()) { done++; continue; }

        final url = _tileUrl
            .replaceFirst('{z}', z.toString())
            .replaceFirst('{x}', x.toString())
            .replaceFirst('{y}', y.toString());
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
        if (resp.statusCode == 200) {
          final f = File(path);
          await f.parent.create(recursive: true);
          await f.writeAsBytes(resp.bodyBytes);
        }
        done++;
      } catch (_) {
        errors++;
        if (errors > total * 0.3) {
          _active[id] = DownloadProgress(id: id, label: label, totalTiles: total, downloadedTiles: done, isError: true, error: 'Too many errors');
          return _active[id]!;
        }
      }
      _active[id] = DownloadProgress(id: id, label: label, totalTiles: total, downloadedTiles: done);
      await Future.delayed(const Duration(milliseconds: 50));
    }

    _active[id] = DownloadProgress(id: id, label: label, totalTiles: total, downloadedTiles: done, isComplete: true);
    return _active[id]!;
  }

  DownloadProgress? getProgress(String id) => _active[id];
  void cancel(String id) => _active.remove(id);

  int _tileCount(double minLat, double maxLat, double minLon, double maxLon, int z) {
    final nw = _latLonToTile(maxLat, minLon, z);
    final se = _latLonToTile(minLat, maxLon, z);
    return ((math.max(nw.$1, se.$1) - math.min(nw.$1, se.$1) + 1) *
            (math.max(nw.$2, se.$2) - math.min(nw.$2, se.$2) + 1)).toInt();
  }

  static (int, int) _latLonToTile(double lat, double lon, int z) {
    final n = math.pow(2, z).toDouble();
    final x = ((lon + 180) / 360 * n).floor();
    final y = ((1 - math.log(math.tan(lat * math.pi / 180) +
            1 / math.cos(lat * math.pi / 180)) / math.pi) / 2 * n).floor();
    return (x, y);
  }
}
