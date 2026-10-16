import 'package:flutter_test/flutter_test.dart';
import 'package:vrlizate_home/src/ecosystem/vr_home_ecosystem_room.dart';
import 'package:vrlizate_home/src/spatial/virtual_home_world_builder.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('room signs use a high-contrast pair independent of wall lighting', () {
    final text = VirtualHomeWorldBuilder.roomSignForeground.computeLuminance();
    final backing = VirtualHomeWorldBuilder.roomSignBackground
        .computeLuminance();
    expect((text + .05) / (backing + .05), greaterThan(14));
  });

  for (final id in ['social', 'emxi', 'cinema']) {
    test(
      '$id proposal raster has opaque backing and bright readable ink',
      () async {
        final room = VrHomeEcosystemRoom.defaults.singleWhere(
          (r) => r.id == id,
        );
        final bitmap = await VirtualHomeWorldBuilder.rasterizeRoomSign(
          room.description,
          maxLines: 3,
          maxWidthPx: 1500,
        );
        expect(bitmap.pixels.take(4), [17, 28, 38, 255]);
        expect(bitmap.width, lessThanOrEqualTo(1548));
        var brightInk = 0;
        var translucentPixels = 0;
        for (var pixel = 0; pixel < bitmap.pixels.length; pixel += 4) {
          if (bitmap.pixels[pixel + 3] != 255) translucentPixels++;
          if (bitmap.pixels[pixel] > 240 &&
              bitmap.pixels[pixel + 1] > 245 &&
              bitmap.pixels[pixel + 2] > 250) {
            brightInk++;
          }
        }
        expect(
          translucentPixels,
          0,
          reason: 'The wall must never bleed through the sign backing.',
        );
        expect(brightInk, greaterThan(100));
      },
    );
  }
}
