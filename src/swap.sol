// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./lib/Tick.sol";

contract Swap {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint128 public immutable maxLiquidityPerTick;

    // Each slot can store 32 bytes
    // 20 + 3 + 1 < 32 bytes
    struct Slot0 {
        // 20 bytes
        // the current price
        uint160 sqrtPriceX96;
        // 3 bytes
        // the current tick
        int24 tick;
        // 1 bytes
        // whether the pool is locked
        bool unlocked;
    }

    Slot0 public slot0;

    event Initialize(uint160 sqrtPriceX96, int24 tick);

    constructor(
        address _token0,
        address _token1,
        uint24 _fee,
        int24 _tickSpacing
    ) {
        token0 = _token0;
        token1 = _token1;
        fee = _fee;
        tickSpacing = _tickSpacing;

        maxLiquidityPerTick = Tick.tickSpacingToMaxLiquidityPerTick(_tickSpacing);
    }

    function initialize(uint160 sqrtPriceX96) external {
        require(slot0.sqrtPriceX96 == 0, "Swap: already initialized");

        int24 tick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        slot0 = Slot0({
            sqrtPriceX96: sqrtPriceX96,
            tick: tick,
            unlocked: true
        });

        emit Initialize(sqrtPriceX96, tick);
    }
}