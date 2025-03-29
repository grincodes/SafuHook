// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SafuPool {
    using PoolIdLibrary for PoolId;

    struct PoolInfo {
        uint256 totalShares;
        uint256 totalCoverage0;
        uint256 totalCoverage1;
        bool isCompromised;
    }

    mapping(PoolId => PoolInfo) public pools;
    mapping(PoolId => mapping(address => uint256)) public shares;
    mapping(PoolId => address) public currency0;
    mapping(PoolId => address) public currency1;

    address public hook;
    address public owner;

    event CoverageAdded(PoolId poolId, uint256 amount0, uint256 amount1);
    event PoolFlaggedCompromised(PoolId poolId);
    event ClaimExecuted(PoolId poolId, address user, uint256 payout0, uint256 payout1);
    event HookAddressUpdated(address newHook);

    modifier onlyHook() {
        require(msg.sender == hook, "Unauthorized");
        _;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    function setHookAddress(address _hook) external onlyOwner {
        require(_hook != address(0), "Invalid hook address");
        hook = _hook;
        emit HookAddressUpdated(_hook);
    }

    function registerCurrencies(PoolId poolId, address _currency0, address _currency1) external onlyHook {
        require(currency0[poolId] == address(0), "Currencies already set");
        currency0[poolId] = _currency0;
        currency1[poolId] = _currency1;
    }


    function getShares(PoolId poolId, address user) external view returns (uint256) {
    return shares[poolId][user];
}

    function updateShares(PoolId poolId, address user, uint256 amount, bool isAdd) external onlyHook {
        if (isAdd) {
            shares[poolId][user] += amount;
            pools[poolId].totalShares += amount;
        } else {
            require(shares[poolId][user] >= amount, "Insufficient shares");
            shares[poolId][user] -= amount;
            pools[poolId].totalShares -= amount;
        }
    }

    function addCoverage(PoolId poolId, uint256 amount0, uint256 amount1) external onlyHook {
        pools[poolId].totalCoverage0 += amount0;
        pools[poolId].totalCoverage1 += amount1;
        emit CoverageAdded(poolId, amount0, amount1);
    }

    function flagCompromised(PoolId poolId) external onlyHook {
        pools[poolId].isCompromised = true;
        emit PoolFlaggedCompromised(poolId);
    }

    function getPoolInfo(PoolId poolId) external view returns (PoolInfo memory) {
        return pools[poolId];
    }

    function claim(PoolId poolId)  external {
        PoolInfo storage pool = pools[poolId];
        require(pool.isCompromised, "Pool not compromised");

        uint256 userShares = shares[poolId][msg.sender];
        require(userShares > 0, "No shares to claim");

        uint256 payout0 = (userShares * pool.totalCoverage0) / pool.totalShares;
        uint256 payout1 = (userShares * pool.totalCoverage1) / pool.totalShares;

        pool.totalShares -= userShares;
        pool.totalCoverage0 -= payout0;
        pool.totalCoverage1 -= payout1;
        shares[poolId][msg.sender] = 0;

        IERC20(currency0[poolId]).transfer(msg.sender, payout0);
        IERC20(currency1[poolId]).transfer(msg.sender, payout1);

        emit ClaimExecuted(poolId, msg.sender, payout0, payout1);
    }
}
