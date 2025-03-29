# AVS Operator Node (SafuHook)

## Description
Off-chain AVS Operator Node for Uniswap V4 SafuHook monitoring. Continuously calls `performAutoMonitoring()` to flag compromised pools and trigger insurance payouts.

## Requirements
- Node.js v18+
- RPC URL (Infura, Alchemy, or local)
- SafuHook contract deployed on-chain
- Operator's Private Key for signing transactions

## Installation
1. Clone the repository:
