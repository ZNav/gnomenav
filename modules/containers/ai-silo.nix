{ config, lib, pkgs, ... }:
# Central data silo + local RAG ("Jarvis"). Runs on msi (compute).
# Generation: llama.cpp Vulkan + Qwen3.5 (see llm.nix).
# Retrieval: Qdrant vector DB + a local embedding model; Open WebUI Knowledge
# and/or Khoj query it. A nightly job indexes the corpus.
let c = config.gnomenav; onCompute = c.role == "compute";
in lib.mkIf onCompute {
  virtualisation.oci-containers.containers = {
    # Vector database — the AI's long-term memory.
    qdrant = {
      image = "docker.io/qdrant/qdrant:latest";
      autoStart = true;
      extraOptions = [ "--network=proxy" ];
      volumes = [ "${c.dataRoot}/vectors/qdrant:/qdrant/storage" ];
    };

    # Khoj = personal-AI app over your notes/docs (Jarvis-style chat + search).
    # PARKED 2026-07-19: the khoj image requires its own postgres+pgvector DB
    # (it does NOT use qdrant) — as declared here it crash-loops on a missing
    # localhost:5432. Re-enable in the RAG lane with a khoj-db container, or
    # drop it entirely and use Open WebUI Knowledge → qdrant instead.
    # khoj = {
    #   image = "ghcr.io/khoj-ai/khoj:latest";
    #   autoStart = true;
    #   dependsOn = [ "qdrant" ];
    #   extraOptions = [ "--network=proxy" ];
    #   environment = {
    #     KHOJ_DEFAULT_CHAT_MODEL = "qwen3.5";
    #     KHOJ_OPENAI_API_BASE = "http://llamacpp:8080/v1";   # local LLM
    #     KHOJ_EMBEDDINGS_MODEL = "nomic-embed-text";
    #   };
    #   volumes = [
    #     "${c.configRoot}/khoj:/root/.khoj"
    #     "${c.dataRoot}/knowledge:/data/knowledge:ro"        # the corpus, read-only
    #   ];
    # };
  };

  # Nightly: refresh the corpus + re-index into Qdrant so the assistant "learns"
  # anything new in Nextcloud / wiki / books / notes.
  systemd.services.silo-index = {
    description = "aggregate + embed the knowledge corpus";
    serviceConfig.Type = "oneshot";
    path = [ pkgs.rsync pkgs.curl pkgs.coreutils ];
    script = "${../../scripts/silo-index.sh}";
  };
  systemd.timers.silo-index = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 04:00:00"; Persistent = true; };
  };
}
