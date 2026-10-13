{ config, lib, pkgs, ... }:
let c = config.gnomenav; onCompute = c.role == "compute";
in lib.mkIf onCompute {
  virtualisation.oci-containers.containers = {
    llamacpp = {
      image = "ghcr.io/ggml-org/llama.cpp:server-vulkan";   # AMD RX 6700M via Vulkan
      autoStart = true;
      extraOptions = [ "--network=proxy" "--device=/dev/dri:/dev/dri" ];
      cmd = [ "-m" "/models/Qwen3.5-9B-Q4_K_M.gguf" "--host" "0.0.0.0" "--port" "8080"
              "-ngl" "99" "-c" "32768" "--jinja" ];
      volumes = [ "${c.configRoot}/llm/models:/models" ];
    };
    open-webui = {
      image = "ghcr.io/open-webui/open-webui:main";
      autoStart = true;
      dependsOn = [ "llamacpp" ];
      extraOptions = [ "--network=proxy" ];
      environment = { OPENAI_API_BASE_URL = "http://llamacpp:8080/v1"; WEBUI_URL = "https://llm.gnomenav.com"; };
      volumes = [ "${c.configRoot}/open-webui:/app/backend/data" ];
    };
  };
}
