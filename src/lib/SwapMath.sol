// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {FullMath} from './FullMath.sol';
import {SqrtPriceMath} from './SqrtPriceMath.sol';

library SwapMath {
    function computeSwapStep(
        uint160 sqrtRatioCurrentX96,
        uint160 sqrtRatioTargetX96,
        uint128 liquidity,
        int256 amountRemaining,
        // 1 bip = 1/100 * 1* = 1/1e4
        // 1e6 = 100%, 1/100 of a bip
        uint24 feePips
    ) internal pure returns (
            uint160 sqrtRatioNextX96,
            uint256 amountIn, 
            uint256 amountOut,
            uint256 feeAmount
    ) {
        // token1 | token0
        //  current tick
        //  <--- 0 for 1 decreasing price
        //       1 for 0 ---> increasing price
        bool zeroForOne = sqrtRatioCurrentX96 >= sqrtRatioTargetX96;
        bool exactIn = amountRemaining >= 0;

        // Calculate max amount in or out and next sqrt ratio
        if (exactIn) {
            uint amountRemainingLessFee = FullMath.mulDiv(uint256(amountRemaining), 1e6 - feePips, 1e6);
            // Calculate max amount in, round up amount in
            amountIn = zeroForOne 
                ? SqrtPriceMath.getAmount0Delta(
                    sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, true
                )
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, true
                );
            // Calculate next sqrt ratio
            if (amountRemainingLessFee > amountIn) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            } else {
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromInput(
                    sqrtRatioCurrentX96, liquidity, amountRemainingLessFee, zeroForOne
                );
            }
        } else {
            // Calculate max amount out, round down amount out
            amountOut = zeroForOne 
                ? SqrtPriceMath.getAmount1Delta(
                    sqrtRatioTargetX96, sqrtRatioCurrentX96, liquidity, false
                )
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioCurrentX96, sqrtRatioTargetX96, liquidity, false
                );
            // Calculate next sqrt ratio
            if (uint256(-amountRemaining) > amountOut) {
                sqrtRatioNextX96 = sqrtRatioTargetX96;
            } else {
                sqrtRatioNextX96 = SqrtPriceMath.getNextSqrtPriceFromOutput(
                    sqrtRatioCurrentX96, liquidity, uint256(-amountRemaining), zeroForOne
                );
            }
        }
        // Calculate amount in and out between sqrt current and next ratio
        bool max = sqrtRatioTargetX96 == sqrtRatioNextX96;
        // max and exactIn   --> in = amountIn
        //                      out = need to calculate
        // max and !exactIn  --> in = need to calculate
        //                      out = amountOut
        // !max and exactIn  --> in = need to calculate
        //                      out = need to calculate
        // !max and !exactIn --> in = need to calculate
        //                      out = need to calculate
        if (zeroForOne) {
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, true
                );
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioNextX96, sqrtRatioCurrentX96, liquidity, false
                );
        } else {
            amountIn = max && exactIn
                ? amountIn
                : SqrtPriceMath.getAmount1Delta(
                    sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, true
                );
            amountOut = max && !exactIn
                ? amountOut
                : SqrtPriceMath.getAmount0Delta(
                    sqrtRatioCurrentX96, sqrtRatioNextX96, liquidity, false
                );
        }

        // Cap the output amount to not exceed the remaining output amount
        if (!exactIn && amountOut > uint256(-amountRemaining)) {
            amountOut = uint256(-amountRemaining);
        }
        
        // Calculate fee on amount in
        if (exactIn && sqrtRatioNextX96 != sqrtRatioTargetX96) {
            feeAmount = uint256(amountRemaining) - amountIn;
        } else {
            // Not exact in or sqrt ratio next = target
            // - Not    exact input
            // - Exact input and sqrt ratio next = target

            // a = amountIn
            // f = feePips
            // x = Amount in needed to put amountIn + fee
            // fee = x * f

            // Solve for x
            // x = a + fee = a + x * f
            // x * (1 - f) = a
            // x = a / (1 - f)

            // Calculate fee
            // fee = x * f = a / (1 - f) * f
            feeAmount = FullMath.mulDivRoundingUp(amountIn, feePips, 1e6 - feePips);
        }
    }
}