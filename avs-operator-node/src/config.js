import safuHookAbi from "../abis/SafuHook.json" assert { type: "json" };

export default {
  RPC_URL: process.env.RPC_URL,
  SAFU_HOOK_ADDRESS: process.env.SAFU_HOOK_ADDRESS,
  SAFU_HOOK_ABI: safuHookAbi,
  OPERATOR_PRIVATE_KEY: process.env.OPERATOR_PRIVATE_KEY,
  OPERATOR_WALLET: process.env.OPERATOR_WALLET,
  MONITOR_INTERVAL_MS: 60000, // Run every 60 seconds
};
