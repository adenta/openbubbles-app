// Synthetic test images authored for this project; no private photographs.
// Writes quadrant patterns through the system HEVC encoder for decoder tests.
#include <libheif/heif.h>
#include <cstdio>
#include <cstdlib>
#include <string>

void check(heif_error e) {
  if (e.code != heif_error_Ok) { std::fprintf(stderr, "%s\n", e.message); std::exit(1); }
}

void fixture(const std::string& path, int bits, heif_orientation orientation, bool alpha, bool multiple) {
  auto* ctx = heif_context_alloc();
  heif_encoder* encoder = nullptr;
  check(heif_context_get_encoder_for_format(ctx, heif_compression_HEVC, &encoder));
  check(heif_encoder_set_lossy_quality(encoder, 100));
  heif_image* image = nullptr;
  const int channels = alpha ? 4 : 3;
  const auto chroma = bits == 10 ? heif_chroma_interleaved_RRGGBB_LE :
      (alpha ? heif_chroma_interleaved_RGBA : heif_chroma_interleaved_RGB);
  check(heif_image_create(64, 32, heif_colorspace_RGB, chroma, &image));
  check(heif_image_add_plane(image, heif_channel_interleaved, 64, 32, bits));
  int stride;
  auto* data = heif_image_get_plane(image, heif_channel_interleaved, &stride);
  for (int y = 0; y < 32; ++y) {
    for (int x = 0; x < 64; ++x) {
      const int pixel[] = {x < 32 ? 220 : 30, y < 16 ? 40 : 210, 80, x < 32 ? 255 : 80};
      for (int c = 0; c < channels; ++c) {
        if (bits == 10) {
          const int v = pixel[c] * 4;
          data[y * stride + x * 6 + c * 2] = v & 255;
          data[y * stride + x * 6 + c * 2 + 1] = v >> 8;
        } else data[y * stride + x * channels + c] = pixel[c];
      }
    }
  }
  auto* options = heif_encoding_options_alloc();
  options->image_orientation = orientation;
  heif_image_handle* handle = nullptr;
  check(heif_context_encode_image(ctx, image, encoder, options, &handle));
  if (multiple) {
    heif_image_handle* second = nullptr;
    options->image_orientation = heif_orientation_rotate_90_cw;
    check(heif_context_encode_image(ctx, image, encoder, options, &second));
    check(heif_context_set_primary_image(ctx, second));
    heif_image_handle_release(second);
  }
  check(heif_context_write_to_file(ctx, path.c_str()));
  heif_image_handle_release(handle);
  heif_encoding_options_free(options);
  heif_image_release(image);
  heif_encoder_release(encoder);
  heif_context_free(ctx);
}

int main(int argc, char** argv) {
  if (argc != 2) return 1;
  check(heif_init(nullptr));
  const std::string root = argv[1];
  fixture(root + "/ordinary.heic", 8, heif_orientation_normal, false, false);
  fixture(root + "/rotated.heic", 8, heif_orientation_rotate_90_cw, false, false);
  fixture(root + "/mirrored.heic", 8, heif_orientation_flip_horizontally, false, false);
  fixture(root + "/ten-bit.heic", 10, heif_orientation_normal, false, false);
  fixture(root + "/alpha.heic", 8, heif_orientation_normal, true, false);
  fixture(root + "/multiple.heic", 8, heif_orientation_normal, false, true);
  heif_deinit();
}
