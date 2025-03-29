// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SafuHook.sol";
import "../src/SafuPool.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {Deployers} from "v4-core/test/utils/Deployers.sol";
import {Currency, CurrencyLibrary} from "v4-core/src/types/Currency.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

contract SafuHookTest is Test,Deployers{

     // Use the libraries
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;


    SafuHook public safuHook;
    SafuPool public safuPool;

    // The two currencies (tokens) from the pool
    Currency token0;
    Currency token1;

 



    address public poolCreator = address(1);
    address public liquidityProvider = address(2);
    address public swapper = address(3);


    PoolKey public poolKey;
    PoolId public poolId;

  

    function setUp() public {

        // Deploy v4 core contracts
        deployFreshManagerAndRouters();

        safuPool = new SafuPool();

        // Deploy our hook
        uint160 flags = uint160(
           Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_INITIALIZE_FLAG | Hooks.BEFORE_SWAP_FLAG
        );
        address hookAddress = address(flags);
        deployCodeTo(
            "SafuHook.sol",
            abi.encode(manager, address(safuPool)),
            hookAddress
        );
        safuHook = SafuHook(hookAddress);

        safuPool.setHookAddress(address(safuHook));

        //Mint TOkens

        (token0, token1) = deployMintAndApprove2Currencies();

        // Mint a bunch of TOKEN to ourselves and to address(1)
         MockERC20(Currency.unwrap(token0)).mint(address(this), 1000 ether);
         MockERC20(Currency.unwrap(token1)).mint(address(this), 1000 ether);
        _approveTokens();

    }

    function _approveTokens() internal{

        // Approve our hook address to spend these tokens as well
        MockERC20(Currency.unwrap(token0)).approve(
            address(safuHook),
            type(uint256).max
        );
        MockERC20(Currency.unwrap(token1)).approve(
            address(safuHook),
            type(uint256).max
        );

        //approve pool to spend
         MockERC20(Currency.unwrap(token0)).approve(
            address(safuPool),
            type(uint256).max
        );
        MockERC20(Currency.unwrap(token1)).approve(
            address(safuPool),
            type(uint256).max
        );

        
        MockERC20(Currency.unwrap(token0)).approve(address(modifyLiquidityRouter), type(uint256).max);
        MockERC20(Currency.unwrap(token1)).approve(address(modifyLiquidityRouter), type(uint256).max);
        

    }

    function _fundAndApproveSwapper() internal{
        // Mint a bunch of TOKEN to ourselves and to address(1)
         MockERC20(Currency.unwrap(token0)).mint(swapper, 1000 ether);
         MockERC20(Currency.unwrap(token1)).mint(swapper, 1000 ether);
        _approveTokens();
    }

    function testBeforeInitialize_RegisterCurrencies() public {

        (poolKey, poolId) =
            initPool(token0,token1, safuHook, 1000, SQRT_PRICE_1_1);
   

        bytes memory hookData = safuHook.getHookData(address(this));

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );

        // check if liquidity currencies are added on SafuPool
        address currency0Addr = safuPool.currency0(poolId);
        address currency1Addr = safuPool.currency1(poolId);

        assertEq( currency0Addr, address(Currency.unwrap(token0)) );
        assertEq( currency1Addr, address(Currency.unwrap(token1)) );
    }
    

    function testBeforeAddLiquity_toUpdatePoolShares() public {

        (poolKey, poolId) =
            initPool(token0,token1, safuHook, 1000, SQRT_PRICE_1_1);
   

        bytes memory hookData = safuHook.getHookData(address(this));

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );

        uint256 shares = safuPool.shares(poolKey.toId(), address(this));


        assertEq(shares, 1 ether);

      
    }


    function testBeforeAddLiquity_toTakeInsuranceShares() public {

        (poolKey, poolId) =
            initPool(token0,token1, safuHook, 1000, SQRT_PRICE_1_1);
   

        bytes memory hookData = safuHook.getHookData(address(this));

        // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );


        assertEq(safuPool.getPoolInfo(poolId).totalCoverage0, 0.02 ether);

    }

    function testSwapAdd_toTakeSwapFees() public {

        (poolKey, poolId) =
            initPool(token0,token1, safuHook, 1000, SQRT_PRICE_1_1);
   

        bytes memory hookData = safuHook.getHookData(address(this));

        // // Some liquidity from -60 to +60 tick range
        modifyLiquidityRouter.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: -60,
                tickUpper: 60,
                liquidityDelta: 1 ether,
                salt: bytes32(0)
            }),
            hookData
        );

       uint256 balanceBeforeSwap = MockERC20(Currency.unwrap(token0)).balanceOf(address(safuPool));

        
       _fundAndApproveSwapper();


        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(0.5 ether),
            sqrtPriceLimitX96: 0
        });


       uint256 balanceAfterSwap = MockERC20(Currency.unwrap(token0)).balanceOf(address(safuPool));


       uint256 diff = (balanceAfterSwap + balanceBeforeSwap) - balanceBeforeSwap ;

        assertEq(diff, 0.02 ether);

    }
  
   
  


}