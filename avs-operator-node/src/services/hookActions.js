import { ethers } from "ethers";
import config from "../config.js";

const provider = new ethers.providers.JsonRpcProvider(config.RPC_URL);
const wallet = new ethers.Wallet(config.OPERATOR_PRIVATE_KEY, provider);

/**
 * Call performAutoMonitoring() on the SafuHook contract.
 * @param {ethers.Contract} safuHook
 * @param {string} operatorWallet
 * @returns {Promise<ethers.Transaction>}
 */
export async function performAutoMonitoring(safuHook, operatorWallet) {
  const safuHookWithSigner = safuHook.connect(wallet);

  console.log(`[AVS Operator] Calling performAutoMonitoring() from ${operatorWallet}...`);

  const tx = await safuHookWithSigner.performAutoMonitoring();
  await tx.wait(); // Wait for transaction confirmation

  return tx;
}
