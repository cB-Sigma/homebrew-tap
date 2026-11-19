class Bolo < Formula
  include Language::Python::Virtualenv

  desc "Self-hosted speech server: speech-to-text, text-to-speech and voice agents"
  homepage "https://github.com/cB-Sigma/bolo-speech"
  url "https://files.pythonhosted.org/packages/d8/b0/637655144a248f89513b11e9ed7139c19fbb4e604d68e441ae5a47846804/bolo_speech-1.0.0-py3-none-any.whl", using: :nounzip
  sha256 "d60d33fd0f6552978cc128db02c5bb481251f5139373ee954bf435ff93486f48"
  license "Apache-2.0"

  livecheck do
    url "https://pypi.org/pypi/bolo-speech/json"
    strategy :json do |json|
      json.dig("info", "version")
    end
  end

  depends_on "python@3.13"

  on_macos do
    # onnxruntime and PyAV publish Apple Silicon wheels for Sonoma (14) and later only.
    depends_on macos: :sonoma
  end

  # The wheels' extension modules keep their @rpath install names: rewriting them
  # to absolute paths does not fit in the Mach-O headers of some of them.
  preserve_rpath

  # pip for the virtualenv, so that it does not depend on the pip of python@3.13.
  resource "pip" do
    url "https://files.pythonhosted.org/packages/3f/06/3e4420302363fbb71be3c7f35ce042f54bfca330e3e66b3a2e3c4cca579f/pip-26.2.2-py3-none-any.whl", using: :nounzip
    sha256 "fd7f4dfa8190e014013b9f08f3e973f4e4c26ffd179a204895533a7254813a70"
  end

  def install
    venv = virtualenv_create(libexec, "python3.13")
    python = venv.root/"bin/python"
    resource("pip").stage do
      wheel = Pathname.pwd/"pip-#{resource("pip").version}-py3-none-any.whl"
      system python, wheel/"pip", "install", "--no-cache-dir", "--no-deps", "--ignore-installed", wheel
    end

    # bolo-speech[all] and its dependencies are installed from PyPI wheels at these
    # versions, so that every build gets the same set. Written by .github/scripts/bump.py
    # from a full install; do not edit by hand.
    (buildpath/"constraints.txt").write <<~EOS
      annotated-doc==0.0.7
      annotated-types==0.8.0
      anyio==4.16.0
      av==19.0.2
      certifi==2026.10.23
      cffi==2.1.1
      click==8.5.1
      ctranslate2==4.9.0
      fastapi==0.165.0
      faster-whisper==1.2.1
      filelock==4.2.12
      flatbuffers==25.12.19
      fsspec==2026.9.0
      h11==0.16.0
      hf-xet==1.8.0
      httpcore2==2.16.2
      httpcore==1.0.9
      httptools==0.9.0
      httpx2==2.16.2
      httpx==0.28.1
      huggingface_hub==2.4.0
      idna==3.20
      numpy==2.5.5
      onnxruntime==1.32.0; sys_platform != "darwin" or platform_machine == "arm64"
      onnxruntime==1.23.2; sys_platform == "darwin" and platform_machine == "x86_64"
      opentelemetry-api==1.45.2
      packaging==26.3
      protobuf==7.36.2
      psutil==7.2.2
      pycparser==3.12
      pydantic==2.14.3
      pydantic_core==2.50.4
      python-dotenv==1.2.4
      python-multipart==0.0.34
      PyYAML==6.0.3
      sherpa-onnx-core==2.0.2
      sherpa_onnx==2.0.2
      soundfile==0.14.0
      soxr==1.1.0
      starlette==1.10.0
      tokenizers==0.23.3
      tqdm==4.70.1
      truststore==0.10.5
      typing-inspection==0.4.5
      typing_extensions==4.16.0
      uccharan==0.6.6
      uvicorn==0.54.0
      uvloop==0.23.0
      watchfiles==1.3.0
      websockets==17.4
      wyoming==1.11.0
    EOS
    # On Apple silicon also the engines that run on its GPU (MLX models, whisper.cpp with Metal), which bolo
    # places there by default. Their own dependencies are not in the pins above: bump.py resolves on Linux,
    # where these extras install nothing; the macOS tests install and run them.
    extras = (OS.mac? && Hardware::CPU.arm?) ? "all,mlx,whispercpp" : "all"
    system python, "-m", "pip", "install", "--no-cache-dir", "--disable-pip-version-check",
           "--ignore-installed", "--only-binary=:all:", "--constraint", buildpath/"constraints.txt",
           "bolo-speech[#{extras}] @ file://#{buildpath}/bolo_speech-#{version}-py3-none-any.whl"
    libexec.install buildpath/"constraints.txt"

    # Some Intel macOS wheels (PyAV's bundled libraries) carry absolute dylib IDs too
    # long for Homebrew to rewrite in place; @rpath IDs are kept as they are.
    if OS.mac? && Hardware::CPU.intel?
      # (find, not glob: the libraries are in hidden .dylibs directories)
      (libexec/"lib").find do |file|
        next if file.symlink? || !file.file? || [".dylib", ".so"].exclude?(file.extname)
        next if !file.dylib? || file.dylib_id.nil? || file.dylib_id.start_with?("@")

        file.change_dylib_id("@rpath/#{File.basename(file.dylib_id)}")
      end
    end
    bin.install_symlink libexec/"bin/bolo"
  end

  def caveats
    <<~EOS
      The service (`brew services start bolo`) serves the web console at
      http://127.0.0.1:8000/ and the API at http://127.0.0.1:8000/v1/, keeps its
      models in #{var}/bolo and logs to #{var}/log/bolo.log.
      `bolo serve` run by hand keeps models in ~/.cache/bolo instead. Settings go
      into ~/.config/bolo/config.toml or BOLO_* environment variables.

      On a Mac with Apple silicon this formula also installs the MLX and
      whisper.cpp engines, and their models run on the GPU (Metal) by default;
      everything else runs on the CPU. On Linux with an NVIDIA GPU, set
      device = "cuda" (and install onnxruntime-gpu as below).

      This formula installs bolo-speech[all]: sherpa-onnx, faster-whisper,
      uccharan, PyAV and Wyoming. The other extras are opt-in. Add one to the
      formula's virtualenv, within the pinned versions, with:
        $(brew --prefix bolo)/libexec/bin/pip install -c $(brew --prefix bolo)/libexec/constraints.txt \\
          'bolo-speech[espeak]==#{version}'
      espeak       eSpeak NG for languages uccharan does not cover (GPL-3.0-or-later)
      kokoro-onnx  the kokoro-onnx engine (pulls in GPL code)
      moonshine, s2s, turn, lid, align, wake, pii, itn, orpheus, sip, webrtc
      PyTorch models: the bolo-torch plugin, the same way:
        $(brew --prefix bolo)/libexec/bin/pip install 'bolo-torch[parler,sepformer]'
      For NVIDIA GPUs on Linux, install onnxruntime-gpu the same way.
      Extras added like this are gone after `brew upgrade bolo`; add them again.
    EOS
  end

  service do
    run [opt_bin/"bolo", "serve"]
    environment_variables BOLO_DATA_DIR: var/"bolo", PATH: std_service_path_env
    keep_alive true
    working_dir var/"bolo"
    log_path var/"log/bolo.log"
    error_log_path var/"log/bolo.log"
  end

  test do
    assert_match "bolo #{version}", shell_output("#{bin}/bolo --version")

    data = testpath/"data"
    doctor = shell_output("#{bin}/bolo doctor --data-dir #{data}")
    assert_match "ok sherpa-onnx", doctor
    assert_match "ok faster-whisper", doctor
    assert_match "uccharan: found", doctor

    port = free_port
    pid = spawn bin/"bolo", "serve", "--host", "127.0.0.1", "--port", port.to_s,
                "--data-dir", data.to_s, "--no-auto-pull"
    begin
      health = ""
      60.times do
        sleep 1
        health = Utils.popen_read("curl", "-s", "http://127.0.0.1:#{port}/healthz")
        break if health.include?("ok")
      end
      assert_match '"status":"ok"', health
    ensure
      Process.kill("TERM", pid)
      Process.wait(pid)
    end
  end
end
