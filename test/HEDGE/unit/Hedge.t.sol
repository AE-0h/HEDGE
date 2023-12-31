// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {HookTest} from "../utils/HookTest.sol";
import {Hooks} from "@uniswap/v4-core/contracts/libraries/Hooks.sol";
import {IHooks} from "@uniswap/v4-core/contracts/interfaces/IHooks.sol";
import {PoolManager} from "@uniswap/v4-core/contracts/PoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/contracts/types/PoolKey.sol";
import {IPoolManager} from "@uniswap/v4-core/contracts/interfaces/IPoolManager.sol";
import {PoolId} from "@uniswap/v4-core/contracts/types/PoolId.sol";
import {Deployers} from "@uniswap/v4-core/test/foundry-tests/utils/Deployers.sol";
import {Hedge, Trigger} from "../../../src/HEDGE/Hedge.sol";
import {HedgeImplementation} from "../utils/HedgeImplementation.sol";
import {TickMath} from "@uniswap/v4-core/contracts/libraries/TickMath.sol";
import {Currency} from "@uniswap/v4-core/contracts/types/Currency.sol";
import {TestERC20} from "@uniswap/v4-core/contracts/test/TestERC20.sol";
import {PoolSwapTest} from "@uniswap/v4-core/contracts/test/PoolSwapTest.sol";

contract HedgeTest is HookTest, Deployers {
    Hedge hedge = Hedge(address(uint160(Hooks.AFTER_SWAP_FLAG)));

    uint160 constant SQRT_RATIO_10_1 = 250541448375047931186413801569;

    PoolKey key;
    bytes32 id;

    uint256 internal mintAmount = 12e18;
        address(0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266);
    address internal thomas =
        address(0x14dC79964da2C08b23698B3D3cc7Ca32193d9955);

    function setUp() public {
        // creates the pool manager, test tokens, and other utility routers
        HookTest.initHookTestEnv();
        vm.record();

        HedgeImplementation impl = new HedgeImplementation(manager, hedge);
        (, bytes32[] memory writes) = vm.accesses(address(impl));
        vm.etch(address(hedge), address(impl).code);
        // for each storage key that was written during the hook implementation, copy the value over
        unchecked {
            for (uint256 i = 0; i < writes.length; i++) {
                bytes32 slot = writes[i];
                vm.store(address(hedge), slot, vm.load(address(impl), slot));
            }
        }

        key = PoolKey(
            Currency.wrap(address(token0)),
            Currency.wrap(address(token1)),
            3000,
            60,
            hedge
        );
        manager.initialize(key, SQRT_RATIO_1_1, abi.encode(""));

        swapRouter = new PoolSwapTest(manager);

        token0.approve(address(hedge), type(uint256).max);
        token1.approve(address(hedge), type(uint256).max);
    }

    function test_setTrigger() public {
        vm.prank(alice);
        uint128 priceLimit = 513 * 10 ** 16;
        uint128 maxAmount = 100 * 10 ** 18;
        hedge.setTrigger(
            Currency.wrap(address(token0)),
            priceLimit,
            maxAmount,
            true
        );
        (
            ,
            ,
            Currency currency0,
            ,
            uint256 minPriceLimit,
            ,
            ,
            uint256 maxAmountSwap,
            address owner
        ) = hedge.triggersByCurrency(
                Currency.wrap(address(token0)),
                priceLimit,
                0
            );
        assertEq(Currency.unwrap(currency0), address(token0));
        assertEq(owner, alice);
        assertEq(minPriceLimit, priceLimit);
        assertEq(maxAmountSwap, maxAmount);

        vm.prank(thomas);
        uint128 priceLimitThomas = 413 * 10 ** 16;
        uint128 maxAmountThomas = 90 * 10 ** 18;
        hedge.setTrigger(
            Currency.wrap(address(token1)),
            priceLimitThomas,
            maxAmountThomas,
            true
        );
        (, , currency0, , minPriceLimit, , , maxAmountSwap, owner) = hedge
            .triggersByCurrency(Currency.wrap(address(token0)), priceLimit, 0);
        assertEq(Currency.unwrap(currency0), address(token0));
        assertEq(owner, alice);
        assertEq(minPriceLimit, priceLimit);
        assertEq(maxAmountSwap, maxAmount);

        //
        (, , currency0, , minPriceLimit, , , maxAmountSwap, owner) = hedge
            .triggersByCurrency(
                Currency.wrap(address(token1)),
                priceLimitThomas,
                0
            );
        assertEq(Currency.unwrap(currency0), address(token1));
        assertEq(owner, thomas);
        assertEq(minPriceLimit, priceLimitThomas);
        assertEq(maxAmountSwap, maxAmountThomas);
    }

    function test_orderedPriceByCurrency() public {
        vm.prank(alice);
        uint128 priceLimit = 613 * 10 ** 16;
        uint128 priceLimit1 = 513 * 10 ** 16;
        uint128 priceLimit2 = 713 * 10 ** 16;
        uint128 priceLimit3 = 913 * 10 ** 16;
        uint128 priceLimit4 = 413 * 10 ** 16;
        uint128 priceLimit5 = 813 * 10 ** 16;
        uint128 maxAmount = 100 * 10 ** 18;
        hedge.setTrigger(
            Currency.wrap(address(token0)),
            priceLimit,
            maxAmount,
            true
        );
        hedge.setTrigger(
            Currency.wrap(address(token0)),
            priceLimit1,
            maxAmount,
            true
        );
        hedge.setTrigger(
            Currency.wrap(address(token0)),
            priceLimit2,
            maxAmount,
            true
        );

        uint256 savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            0
        );
        assertEq(savedPrice, priceLimit1);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            1
        );
        assertEq(savedPrice, priceLimit);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            2
        );
        assertEq(savedPrice, priceLimit2);

        hedge.setTrigger(
            Currency.wrap(address(token0)),
            priceLimit3,
            maxAmount,
            true
        );
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            3
        );
        assertEq(savedPrice, priceLimit3);

        hedge.setTrigger(
            Currency.wrap(address(token0)),
            priceLimit4,
            maxAmount,
            true
        );
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            0
        );
        assertEq(savedPrice, priceLimit4);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            1
        );
        assertEq(savedPrice, priceLimit1);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            2
        );
        assertEq(savedPrice, priceLimit);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            3
        );
        assertEq(savedPrice, priceLimit2);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            4
        );
        assertEq(savedPrice, priceLimit3);

        hedge.setTrigger(
            Currency.wrap(address(token0)),
            priceLimit5,
            maxAmount,
            true
        );
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            3
        );
        assertEq(savedPrice, priceLimit2);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            4
        );
        assertEq(savedPrice, priceLimit5);
        savedPrice = hedge.orderedPriceByCurrency(
            Currency.wrap(address(token0)),
            5
        );
        assertEq(savedPrice, priceLimit3);
    }
}
