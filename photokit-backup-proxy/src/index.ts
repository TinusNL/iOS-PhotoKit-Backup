import { createApp } from "./server.ts";
import { loadConfig, resolveConfigPath } from "./config.ts";

const configPath = resolveConfigPath();
const config = loadConfig(configPath);
const server = createApp(config);

server.listen(config.port, "0.0.0.0", () => {
  console.log(`PhotoKit backup proxy listening on ${config.port}`);
  console.log(`Config: ${configPath}`);
  for (const key of config.keys) {
    console.log(`Key ${key.name} -> ${key.directory}`);
  }
});
