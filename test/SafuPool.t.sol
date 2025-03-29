// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SafuPool.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";

contract SafuPoolTest is Test {
    SafuPool public safuPool;
    address public hook;

    PoolId public poolId;

    address user1 = address(1);

    function setUp() public {
        hook = address(this);
        safuPool = new SafuPool();
        safuPool.setHookAddress(hook);
        poolId = PoolId.wrap(bytes32("POOL_ID"));
    }

    function testUpdateShares_Add() public {
        safuPool.updateShares(poolId, user1, 1000, true);

        assertEq(safuPool.shares(poolId, user1), 1000);
        assertEq(safuPool.getPoolInfo(poolId).totalShares, 1000);
    }

    function testUpdateShares_Remove() public {
        safuPool.updateShares(poolId, user1, 1000, true);
        safuPool.updateShares(poolId, user1, 500, false);

        assertEq(safuPool.shares(poolId, user1), 500);
        assertEq(safuPool.getPoolInfo(poolId).totalShares, 500);
    }

    function testAddCoverage() public {
        safuPool.addCoverage(poolId, 500, 1000);

        SafuPool.PoolInfo memory pool = safuPool.getPoolInfo(poolId);
        assertEq(pool.totalCoverage0, 500);
        assertEq(pool.totalCoverage1, 1000);
    }

    function testFlagCompromised() public {
        safuPool.flagCompromised(poolId);

        assertTrue(safuPool.getPoolInfo(poolId).isCompromised);
    }
}
