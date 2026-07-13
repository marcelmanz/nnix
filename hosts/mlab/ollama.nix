{...}: {
  services.ollama = {
    enable = true;
    loadModels = ["dolphin3:8b"];
  };
}
