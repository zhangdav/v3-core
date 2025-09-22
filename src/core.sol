// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {Tick} from './lib/Tick.sol';
import {TickMath} from './lib/TickMath.sol';
import {Position} from './lib/Position.sol';
import {SafeCast} from './lib/SafeCast.sol';
import {SqrtPriceMath} from './lib/SqrtPriceMath.sol';
import {TransferHelper} from './lib/TransferHelper.sol';
import {IERC20} from './interfaces/IERC20.sol';

using SafeCast for uint256;
using SafeCast for int256;
using Position for Position.Info;
using Tick for mapping(int24 => Tick.Info);
using Tick for Tick.Info;

contract Core {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint128 public immutable maxLiquidityPerTick;
    uint128 public liquidity;

    struct ModifyPositionParams {
        address owner;
        int24 tickLower;
        int24 tickUpper;
        int128 liquidityDelta;
    }

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

    // ID => position
    mapping(bytes32 => Position.Info) public positions;

    // tick => tick info
    mapping(int24 => Tick.Info) public ticks;

    // Reentrancy guard
    modifier lock() {
        require(slot0.unlocked, "Swap: locked");
        slot0.unlocked = false;
        _;
        slot0.unlocked = true;
    }

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

    function mint(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external lock returns (uint256 amount0, uint256 amount1) {
        require(amount > 0, "Swap: should be greater than 0");

        (, int256 amount0Int, int256 amount1Int) =
            _modifyPosition(
                ModifyPositionParams({
                    owner: recipient,
                    tickLower: tickLower,
                    tickUpper: tickUpper,
                    liquidityDelta: int256(uint256(amount)).toInt128()
                })
            );

        amount0 = uint256(amount0Int);
        amount1 = uint256(amount1Int);

        if (amount0 > 0) {
            IERC20(token0).transferFrom(msg.sender, address(this), amount0);
        }

        if (amount1 > 0) {
            IERC20(token1).transferFrom(msg.sender, address(this), amount1);
        }
    }

    function collect(
        address recipient,
        int24 tickLower,
        int24 tickUpper,
        uint128 amount0Requested,
        uint128 amount1Requested
    ) external lock returns (uint128 amount0, uint128 amount1) {
        Position.Info storage position = Position.get(positions, msg.sender, tickLower, tickUpper);

        amount0 = amount0Requested > position.tokensOwed0 ? position.tokensOwed0 : amount0Requested;
        amount1 = amount1Requested > position.tokensOwed1 ? position.tokensOwed1 : amount1Requested;

        if (amount0 > 0) {
            position.tokensOwed0 -= amount0;
            // USDC and USDT doesn't return a boolean
            TransferHelper.safeTransfer(token0, recipient, amount0);
        }
        if (amount1 > 0) {
            position.tokensOwed1 -= amount1;
            TransferHelper.safeTransfer(token1, recipient, amount1);
        }
    }

    // Burn liquidity from a position
    function burn(
        int24 tickLower,
        int24 tickUpper,
        uint128 amount
    ) external lock returns (uint256 amount0, uint256 amount1) {
        (Position.Info storage position, int256 amount0Int, int256 amount1Int) =
        _modifyPosition(
            ModifyPositionParams({
                owner: msg.sender,
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -int256(uint256(amount)).toInt128()
            })
        );

        amount0 = uint256(-amount0Int);
        amount1 = uint256(-amount1Int);

        if (amount0 > 0 || amount1 > 0) {
            // no transfer of tokens
            (position.tokensOwed0, position.tokensOwed1) = (
                position.tokensOwed0 + uint128(amount0),
                position.tokensOwed1 + uint128(amount1)
            );
        }
    }

    function _modifyPosition(ModifyPositionParams memory params) 
        private 
        returns (Position.Info storage position, int256 amount0, int256 amount1) 
    {
        checkTicks(params.tickLower, params.tickUpper);

        Slot0 memory _slot0 = slot0;

        position = _updatePosition(
            params.owner,
            params.tickLower,
            params.tickUpper,
            params.liquidityDelta,
            _slot0.tick
        );

        if (params.liquidityDelta != 0) {
            // Condition: P < P_lower
            if (_slot0.tick < params.tickLower) {
            // delta x = delta L * (1/√P_A - 1/√P_B)
            amount0 = SqrtPriceMath.getAmount0Delta(
                TickMath.getSqrtRatioAtTick(params.tickLower),  // √P_A
                TickMath.getSqrtRatioAtTick(params.tickUpper),  // √P_B
                params.liquidityDelta                           // delta L
            );
            // Condition: P_lower < P < P_upper
            } else if (_slot0.tick > params.tickUpper) {
                // delta L = (delta x / 1/√P - 1/√P_B = delta y / √P - 1/√P_B
                amount0 = SqrtPriceMath.getAmount0Delta(
                    _slot0.sqrtPriceX96,                            // √P
                    TickMath.getSqrtRatioAtTick(params.tickUpper),  // √P_B
                    params.liquidityDelta                           // delta L
                );
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),  // √P_A
                    _slot0.sqrtPriceX96,                            // √P
                    params.liquidityDelta                           // delta L
                );

                liquidity = params.liquidityDelta < 0
                    ? liquidity - uint128(-params.liquidityDelta)
                    : liquidity + uint128(params.liquidityDelta);
            // Condition: P > P_upper
            } else {
                // delta y = delta L * (√P_B - √P_A)
                amount1 = SqrtPriceMath.getAmount1Delta(
                    TickMath.getSqrtRatioAtTick(params.tickLower),  // √P_A
                    TickMath.getSqrtRatioAtTick(params.tickUpper),  // √P_B
                    params.liquidityDelta                           // delta L
                );
            }
        }
    }

    function _updatePosition(
        address owner,
        int24 tickLower,
        int24 tickUpper,
        int128 liquidityDelta,
        int24 tick
    ) private returns (Position.Info storage position) {
        position = Position.get(positions, owner, tickLower, tickUpper);

        /// TODO: fees
        uint256 _feeGrowthGlobal0X128 = 0;
        uint256 _feeGrowthGlobal1X128 = 0;

        bool flippedLower;
        bool flippedUpper;
        if (liquidityDelta != 0) {
            flippedLower = ticks.update(
                tickLower,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                false,
                maxLiquidityPerTick
            );
            flippedUpper = ticks.update(
                tickUpper,
                tick,
                liquidityDelta,
                _feeGrowthGlobal0X128,
                _feeGrowthGlobal1X128,
                true,
                maxLiquidityPerTick
            );
        }

        /// TODO: fees
        position.update(liquidityDelta, 0, 0);

        // When decreasing liquidity, clear the tick
        if (liquidityDelta < 0) {
            if (flippedLower) {
                ticks.clear(tickLower);
            }
            if (flippedUpper) {
                ticks.clear(tickUpper);
            }
        }
    }

    function checkTicks(int24 tickLower, int24 tickUpper) 
        private pure 
    {
        require(tickLower < tickUpper);
        require(tickLower >= TickMath.MIN_TICK);
        require(tickUpper <= TickMath.MAX_TICK);
    }
}