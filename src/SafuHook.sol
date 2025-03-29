// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {BaseHook} from "v4-periphery/src/utils/BaseHook.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {BeforeSwapDelta} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {SafuPool} from "./SafuPool.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract SafuHook is BaseHook, ReentrancyGuard {
    using PoolIdLibrary for PoolKey;
    using PoolIdLibrary for PoolId;
    using SafeERC20 for IERC20;
    using CurrencyLibrary for Currency;

    SafuPool public immutable safuPool;

    uint256 public INITIAL_INSURANCE_BPS = 200;
    uint256 public SWAP_FEE_BPS = 50;
    uint256 public emergencyWithdrawPenaltyBPS = 5000;
    uint256 public rugPullThresholdBPS = 8000;
    uint256 public highWithdrawalPenaltyBPS = 3000;
    uint256 public constant LOCK_DURATION = 90 days;

    address public governance;

    uint256 public constant UNFREEZE_DELAY = 7 days; // Cool-off period
    mapping(PoolId => uint256) public poolFreezeTimestamps;
    mapping(PoolId => PoolKey) public poolKeys;
    mapping(PoolId => bool) public frozenPools;

    struct LiquidityLock {
        uint256 lockedAmount0;
        uint256 lockedAmount1;
        uint256 unlockTime;
        bool unlocked;
        address creator;
    }

    mapping(PoolId => LiquidityLock) public liquidityLocks;

    event FeesCollected(PoolId poolId, uint256 fee0, uint256 fee1);
    event PoolFrozen(PoolId poolId, uint256 freezeTimestamp);
    event PoolUnfrozen(PoolId poolId);
    event RugPullThresholdUpdated(uint256 newThreshold);
    event HighWithdrawalPenaltyUpdated(uint256 newPenalty);
    event LiquidityLocked(PoolId poolId, uint256 amount0, uint256 amount1, uint256 unlockTime);
    event LiquidityUnlocked(PoolId poolId, address creator);

    event ConsoleMessage(string msg);



    modifier onlyGovernance() {
        require(msg.sender == governance, "Only governance");
        _;
    }

    constructor(IPoolManager _poolManager, SafuPool _safuPool)
        BaseHook(_poolManager)
    {
        safuPool = _safuPool;
        governance = msg.sender;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: true,
            beforeAddLiquidity: true,
            beforeSwap: true,
            afterInitialize: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function setRugPullThreshold(uint256 newThresholdBPS) external onlyGovernance {
        require(newThresholdBPS <= 10000, "Invalid threshold");
        rugPullThresholdBPS = newThresholdBPS;
        emit RugPullThresholdUpdated(newThresholdBPS);
    }

    function setHighWithdrawalPenalty(uint256 newPenaltyBPS) external onlyGovernance {
        require(newPenaltyBPS <= 10000, "Invalid penalty");
        highWithdrawalPenaltyBPS = newPenaltyBPS;
        emit HighWithdrawalPenaltyUpdated(newPenaltyBPS);
    }

    function setInitialInsuranceBPS(uint256 newBPS) external onlyGovernance {
        require(newBPS <= 10000, "Invalid BPS");
        INITIAL_INSURANCE_BPS = newBPS;
    }


    function flagAndFreezePool(PoolId poolId) external onlyGovernance {
        require(!frozenPools[poolId], "Already frozen");

        safuPool.flagCompromised(poolId);
        frozenPools[poolId] = true;
        poolFreezeTimestamps[poolId] = block.timestamp; 

        emit PoolFrozen(poolId, block.timestamp);
    }

     function isPoolOperational(PoolId poolId) public view returns (bool) {
        if (!frozenPools[poolId]) {
            return true;
        }

        // Automatically allow pool operations after cooldown unless governance extends freeze
        if (block.timestamp >= poolFreezeTimestamps[poolId] + UNFREEZE_DELAY) {
            return true;
        }

        return false;
    }

    function unfreezePool(PoolId poolId) external onlyGovernance {
        require(frozenPools[poolId], "Pool is not frozen");
        frozenPools[poolId] = false;

        emit PoolUnfrozen(poolId);
    }

    function _beforeInitialize(address , PoolKey calldata key, uint160)
        internal override returns (bytes4)
    {
        
        PoolId poolId = key.toId();
        poolKeys[poolId] = key;
        safuPool.registerCurrencies(poolId,Currency.unwrap(key.currency0), address(Currency.unwrap(key.currency1)));
        return this.beforeInitialize.selector;
    }

    function _beforeAddLiquidity(
        address ,
        PoolKey calldata key,
        IPoolManager.ModifyLiquidityParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4) {

      (address senderAddr) = abi.decode(hookData, (address));
        PoolId poolId = key.toId();
        require(isPoolOperational(poolId), "Pool operations paused");


        if (params.liquidityDelta > 0) {
            safuPool.updateShares(poolId, senderAddr, uint256(params.liquidityDelta), true);
            _takeInsuranceFee(key, senderAddr, INITIAL_INSURANCE_BPS);
        }

        return this.beforeAddLiquidity.selector;
    }

    function getHookData(address sender) public pure returns (bytes memory) {
        return abi.encode(sender);
    }

    function _beforeSwap(
        address ,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        bytes calldata hookData
    ) internal override returns (bytes4, BeforeSwapDelta, uint24) {
        PoolId poolId = key.toId();

       (address senderAddr) = abi.decode(hookData, (address));
       require(isPoolOperational(poolId), "Pool operations paused");

        uint256 amountIn = uint256(params.amountSpecified > 0 ? params.amountSpecified : -params.amountSpecified);

        emit ConsoleMessage("amountIn");
        emit ConsoleMessage(Strings.toString(amountIn));

        if (safuPool.getPoolInfo(poolId).isCompromised) {
            uint256 emergencyFee = (amountIn * emergencyWithdrawPenaltyBPS) / 10000;
            _transferFees(key, senderAddr, emergencyFee, emergencyFee);
        } else {
            _processSwapFee(key, senderAddr, amountIn);
        }

        return (this.beforeSwap.selector, BeforeSwapDelta.wrap(params.amountSpecified), 0);
    }


    function _takeInsuranceFee(PoolKey calldata key, address sender, uint256 bps) internal {

        require(bps <= 10000, "BPS too high");  
        uint256 insuranceAmount0 = (bps * 1e18) / 10000;
        uint256 insuranceAmount1 = (bps * 1e18) / 10000;
   
        _transferFees(key, sender, insuranceAmount0, insuranceAmount1);
    }

    function _processSwapFee(PoolKey calldata key, address sender, uint256 amountIn) internal {
    
        uint256 fee0 = (amountIn * SWAP_FEE_BPS) / 20000;
        uint256 fee1 = (amountIn * SWAP_FEE_BPS) / 20000;

        _transferFees(key, sender, fee0, fee1);
    }

    function _transferFees(PoolKey calldata key, address sender, uint256 fee0, uint256 fee1) internal {
        PoolId poolId = key.toId();

        emit ConsoleMessage("fee0");
        emit ConsoleMessage(Strings.toString(fee0));

         emit ConsoleMessage("fee1");
        emit ConsoleMessage(Strings.toString(fee1));
        
        if (fee0 > 0) {
            IERC20(Currency.unwrap(key.currency0)).safeTransferFrom(address(sender), address(safuPool), fee0);
        }

        if (fee1 > 1) {
            IERC20(Currency.unwrap(key.currency1)).safeTransferFrom(address(sender), address(safuPool), fee1);
        }

        safuPool.addCoverage(poolId, fee0, fee1);

        emit FeesCollected(poolId, fee0, fee1);
    }
} 


