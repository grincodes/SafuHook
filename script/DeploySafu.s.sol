// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/SafuHook.sol";
import "../src/SafuPool.sol";
import {PoolCreationHelper} from "../src/PoolCreationHelper.sol";

import "forge-std/console.sol";
// Uniswap libraries
import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {PoolManager} from "v4-core/src/PoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolModifyLiquidityTest} from "v4-core/src/test/PoolModifyLiquidityTest.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";
import {HookMiner} from "v4-periphery/src/utils/HookMiner.sol";

contract DeploySafu is Script {
    
    SafuHook public safuHook;
    SafuPool public safuPool;

    MockERC20 token0;
    MockERC20 token1;

    PoolManager public manager;
    PoolModifyLiquidityTest public modifyLiquidityRouter;
    PoolSwapTest public poolSwapTest;
    PoolCreationHelper public poolCreationHelper;
   
    uint256 public COLLATERAL_AMOUNT = 100 * 1e6; // 100 USDC

    function run() public {
        address deployerAddress = vm.envAddress("DEPLOYER_ADDRESS");
        address poolMangerAddress = vm.envAddress("POOL_MANAGER_ADDRESS");

        vm.startBroadcast(deployerAddress);


        safuPool = new SafuPool();

        // Deploy Uniswap infrastructure
        manager = new PoolManager(address(this));
        console.log("Deployed PoolManager at", address(manager));
        
        // Deploy test routers
        modifyLiquidityRouter = new PoolModifyLiquidityTest(manager);
        poolSwapTest = new PoolSwapTest(manager);
        
        // Deploy PoolCreationHelper
        poolCreationHelper = new PoolCreationHelper(address(manager));
        console.log("Deployed PoolCreationHelper at", address(poolCreationHelper));

        // Deploy hook with proper flags
        vm.stopBroadcast();
        uint160 flags = uint160(
           Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.AFTER_SWAP_FLAG
        );

        // Use HookMiner to find a salt that will produce a hook address with the needed flags
        (address hookAddress, bytes32 salt) = HookMiner.find(
            deployerAddress,
            flags, 
            type(SafuHook).creationCode,
            abi.encode(IPoolManager(poolMangerAddress), address(safuPool))
        );

        console.log("Computed hook address:", hookAddress);
        console.log("Using salt:", vm.toString(salt));

        SafuHook hook = new SafuHook{salt: salt}(
            IPoolManager(poolMangerAddress),
            safuPool
        );
        
        safuPool.setHookAddress(address(hook));
        console.log("Hook deployed at:", address(hook));
        console.log("Hook flags (should include 0xC0 for before/after swap):", uint160(address(hook)) & 0xFF);

        
        // Deploy mock collateral token
        token0 = new MockERC20("TestX", "MTokx", 18);
        token1 = new MockERC20("TestY", "MToky", 18);
        console.log("TestX", address(token0));
        console.log("TestY", address(token1));
        
        // Mint tokens to deployer
        token0.mint(deployerAddress, 100 ether);
        token1.mint(deployerAddress, 100 ether);
        console.log("Minted 100 TestX and 100 TestY to deployer");
        // Approve hook to spend tokens
        token0.approve(address(hook), type(uint256).max);
        token1.approve(address(hook), type(uint256).max);
        
        vm.stopBroadcast();
        console.log("Deployment complete!");
    }
}
