// Standalone so a malformed attachment or a slow codec cannot block Flutter.
#include <libheif/heif.h>
#include <png.h>

#include <cstdio>
#include <memory>

namespace {
int fail(const char* stage) {
  // Deliberately omit attachment paths and decoder-provided input text.
  std::fprintf(stderr, "HEIC conversion failed: %s\n", stage);
  return 1;
}
}

int main(int argc, char** argv) {
  if (argc != 3) return fail("expected source and destination");
  if (heif_init(nullptr).code != heif_error_Ok) return fail("initialization");
  const auto cleanup = std::unique_ptr<void, void (*)(void*)>(
      reinterpret_cast<void*>(1), [](void*) { heif_deinit(); });
  const auto context = std::unique_ptr<heif_context, decltype(&heif_context_free)>(
      heif_context_alloc(), heif_context_free);
  if (!context) return fail("context allocation");
  // Keep libheif's default security limits and use its software HEVC decoder.
  if (heif_context_read_from_file(context.get(), argv[1], nullptr).code != heif_error_Ok)
    return fail("reading source");
  heif_image_handle* raw_handle = nullptr;
  if (heif_context_get_primary_image_handle(context.get(), &raw_handle).code != heif_error_Ok)
    return fail("primary image");
  const auto handle = std::unique_ptr<heif_image_handle, decltype(&heif_image_handle_release)>(
      raw_handle, heif_image_handle_release);
  const auto options = std::unique_ptr<heif_decoding_options, decltype(&heif_decoding_options_free)>(
      heif_decoding_options_alloc(), heif_decoding_options_free);
  if (!options) return fail("options allocation");
  options->ignore_transformations = false;
  options->convert_hdr_to_8bit = true;
  options->strict_decoding = true;
  options->decoder_id = "libde265";
  // libheif >= 1.23 converts NCLX input to sRGB by default. HDR gain maps and
  // auxiliary images are not requested: this is the primary SDR still only.
  heif_image* raw_image = nullptr;
  const bool alpha = heif_image_handle_has_alpha_channel(handle.get());
  if (heif_decode_image(handle.get(), &raw_image, heif_colorspace_RGB,
                        alpha ? heif_chroma_interleaved_RGBA : heif_chroma_interleaved_RGB,
                        options.get()).code != heif_error_Ok)
    return fail("decoding primary image");
  const auto image = std::unique_ptr<heif_image, decltype(&heif_image_release)>(raw_image, heif_image_release);
  int stride = 0;
  const auto pixels = heif_image_get_plane_readonly(image.get(), heif_channel_interleaved, &stride);
  const int width = heif_image_get_width(image.get(), heif_channel_interleaved);
  const int height = heif_image_get_height(image.get(), heif_channel_interleaved);
  if (!pixels || width <= 0 || height <= 0 || stride <= 0) return fail("pixel data");

  png_image output{};
  output.version = PNG_IMAGE_VERSION;
  output.width = width;
  output.height = height;
  output.format = alpha ? PNG_FORMAT_RGBA : PNG_FORMAT_RGB;
  const bool written = png_image_write_to_file(&output, argv[2], 0, pixels, stride, nullptr);
  png_image_free(&output);
  if (!written) {
    std::remove(argv[2]);
    return fail("writing PNG");
  }
  return 0;
}
