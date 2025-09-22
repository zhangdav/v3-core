// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./TickMath.sol";

/* X = token 0
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
*/
library Tick {
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128) {
        int24 minTick = (TickMath.MIN_TICK / tickSpacing) * tickSpacing;
        int24 maxTick = (TickMath.MAX_TICK / tickSpacing) * tickSpacing;
        uint24 numTicks = uint24((maxTick - minTick) / tickSpacing + 1);
        // Distribute uint128.max evenly ti all ticks and calculate the upper limit of a single tick
        return type(uint128).max / numTicks;
    }
}