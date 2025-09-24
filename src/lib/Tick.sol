// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./TickMath.sol";

/* 
*  X = token 0
*  Y = token 1
*  P = Price of X in terms of Y = Y/X
*  P = 1.0001 ** tick
*  for example, if tick = -200697
*  p = 1.0001 ** tick
*  token 0 = ETH
*  decimals_0 = 1e18
*  token 1 = USDC
*  decimals_1 = 1e6
*  p * decimals_0 / decimals_1 = 1.0001 ** tick * 1e18 / 1e6
*  Tick spacing = Number of ticks to skip when the price moves
*  for example, tick spacing = 2
*    |     |     |     |     |   
*  --|--|--|--|--|--|--|--|--|--
*   -4 -3 -2 -1  0  1  2  3  4
*
*  sqrtPriceX96  = √P Q96
*  Q96 = 2 ** 96
*  sqrt price = (sqrtPriceX96 / Q96) ** 2
*  tick = 2log(sqrtPriceX96 / Q96) / log(1.0001)
*/
library Tick {
    struct Info {
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
        bool initialized;
    }

    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing + 1);
        // Distribute uint128.max evenly ti all ticks and calculate the upper limit of a single tick
        return type(uint128).max / numTicks;
    }

    function update(
        mapping(int24 => Info) storage self,
        int24 tick,
        int24 currentTick,
        int128 liquidityDelta,
        uint256 feeGrowthOutside0X128,
        uint256 feeGrowthOutside1X128,
        bool upper,
        uint128 maxLiquidity
    ) internal returns (bool flipped) {
        Info memory info = self[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        uint128 liquidityGrossAfter = liquidityDelta < 0 
            ? liquidityGrossBefore - uint128(-liquidityDelta)
            : liquidityGrossBefore + uint128(liquidityDelta);

        require(liquidityGrossAfter <= maxLiquidity, "Tick: liquidity overflow");

        // flipped = true
        // non zero -> 0 (after == 0, before > 0)
        //  0  -> non zero (after > 0, before == 0)
        // flipped = false
        // zero -> zero (after == 0, before == 0)
        // non zero -> non zero (after > 0, before > 0)

        // flipped = (liquidityGrossBefore == 0 && liquidityGrossAfter > 0) || (liquidityGrossBefore > 0 && liquidityGrossAfter == 0)
        flipped = (liquidityGrossAfter == 0) != (liquidityGrossBefore == 0);

        /// TODO
        if (liquidityGrossBefore == 0) {
            info.initialized = true;
        }

        info.liquidityGross = liquidityGrossAfter;

        // lower   upper
        //   |       |
        //   +       -
        //   ----> one for zero +
        //   <---- zero for one -
        info.liquidityNet = upper
            ? info.liquidityNet - liquidityDelta
            : info.liquidityNet + liquidityDelta;
    }

    function clear(mapping(int24 => Info) storage self, int24 tick) internal {
        delete self[tick];
    }

    function cross(
        mapping(int24 => Info) storage self,
        int24 tick,
        uint256 feeGrowthGlobal0X128,
        uint256 feeGrowthGlobal1X128
    ) internal returns (int128 liquidityNet) {
        Info storage info = self[tick];
        info.feeGrowthOutside0X128 = feeGrowthGlobal0X128 - info.feeGrowthOutside0X128;
        info.feeGrowthOutside1X128 = feeGrowthGlobal1X128 - info.feeGrowthOutside1X128;
        return info.liquidityNet;
    }
}