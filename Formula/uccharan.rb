class Uccharan < Formula
  desc "Phonemiser, text normaliser and transliterator for speech engines"
  homepage "https://cb-sigma.github.io/uccharan/"
  url "https://github.com/cB-Sigma/uccharan/archive/refs/tags/v0.6.3.tar.gz"
  sha256 "d4b09eb08646f2da01a566f4aaf87b53202dc71d4f310ce8548c67fe87260279"
  license "Apache-2.0"
  head "https://github.com/cB-Sigma/uccharan.git", branch: "main"

  livecheck do
    url :stable
    strategy :github_latest
  end

  depends_on "rust" => :build

  def install
    # The command-line tool, with the `download` feature: the word tables of the
    # languages other than English and Hindi are fetched on first use.
    system "cargo", "install", "--features", "download", *std_cargo_args(path: "crates/uccharan")

    # The C library (shared and static) and its header, as attached to each release.
    system "cargo", "build", "--lib", "--release", "--locked", "--package", "uccharan-capi"
    lib.install "target/release/#{shared_library("libuccharan")}", "target/release/libuccharan.a"
    include.install "crates/uccharan-capi/include/uccharan.h"
    pkgshare.install "crates/uccharan-capi/examples/hello.c"
  end

  def caveats
    <<~EOS
      English and Hindi are built in. The word tables of the other languages
      (de, fr, nl, it, pt, pl, tr, cs, sv, ca, ro, hu, fi, nb, da, ur, sd, ...)
      are small packs that `uccharan` downloads from the GitHub release the first
      time a language is used, checks against SHA-256 sums and caches in:
        ~/.cache/uccharan/<version>/   ($XDG_CACHE_HOME/uccharan/<version>/ if set)

      To see the packs and download them ahead of time:
        uccharan --packs
        uccharan --download de fr ur

      libuccharan reads packs from the same cache, or from $UCCHARAN_DATA_DIR.
      For a machine without network access, put the .ucd files in a directory,
      set UCCHARAN_DATA_DIR to it and set UCCHARAN_OFFLINE=1.
    EOS
  end

  test do
    ENV["UCCHARAN_OFFLINE"] = "1"
    ENV["XDG_CACHE_HOME"] = testpath/"cache"

    assert_match "uccharan #{version}", shell_output("#{bin}/uccharan --version")
    assert_equal "həlˈoʊ, wˈɜːld.", shell_output("#{bin}/uccharan 'Hello, world.'").strip
    assert_match "nəmˈʌsteː dˈʊnɪjˌaː", shell_output("#{bin}/uccharan -l hi 'नमस्ते दुनिया'")

    (testpath/"test.c").write <<~C
      #include <stdio.h>
      #include <uccharan.h>

      int main(void) {
        UccharanPhonemizer *p = uccharan_new();
        char *en = uccharan_phonemize(p, "Hello, world.", "en-us", "espeak-ipa", 0);
        char *hi = uccharan_phonemize(p, "नमस्ते दुनिया", "hi", "espeak-ipa", 0);
        if (!en || !hi) {
          fprintf(stderr, "%s\\n", uccharan_last_error());
          return 1;
        }
        printf("%s\\n%s\\n%s\\n", uccharan_version(), en, hi);
        uccharan_string_free(en);
        uccharan_string_free(hi);
        uccharan_free(p);
        return 0;
      }
    C
    flags = ["-I#{include}", "-L#{lib}", "-luccharan"]
    flags << "-Wl,-rpath,#{lib}" if OS.linux?
    system ENV.cc, "test.c", *flags, "-o", "test"
    output = shell_output("./test")
    assert_match version.to_s, output
    assert_match "həlˈoʊ, wˈɜːld.", output
    assert_match "nəmˈʌsteː", output
  end
end
