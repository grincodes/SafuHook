import { ethers } from "ethers";
import config from "../config.js";

const provider = new ethers.providers.JsonRpcProvider(config.RPC_URL);
const wallet = new ethers.Wallet(config.OPERATOR_PRIVATE_KEY, provider);

export async function signMessage(hash) {
  return wallet.signMessage(ethers.utils.arrayify(hash));
}
