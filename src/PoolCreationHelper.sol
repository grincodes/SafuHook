// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {Currency} from "v4-core/src/types/Currency.sol";

import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {console} from "forge-std/console.sol";

contract PoolCreationHelper {
    using PoolIdLibrary for PoolKey;
    
    IPoolManager public immutable poolManager;

    constructor(address _poolManager) {
        poolManager = IPoolManager(_poolManager);
    }

    function createSepoliaPool(
        PoolKey memory pool
    ) external returns (PoolKey memory) {
        uint160 pricePoolQ = TickMath.getSqrtPriceAtTick(0);

        console.log("Pool price SQRTX96: %d", pricePoolQ);

        poolManager.initialize(pool, pricePoolQ);

        console.log("Pool created");

        return pool;
    }

}