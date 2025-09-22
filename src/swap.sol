// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import "./lib/Tick.sol";
import "./lib/TickMath.sol";
import "./lib/Position.sol";
import "./lib/SafaCast.sol";
import "./interfaces/IERC20.sol";

using SafeCast for int256;
using Position for mapping(bytes32 => Position.Info);
using Position for Position.Info;

contract Swap {
    address public immutable token0;
    address public immutable token1;
    uint24 public immutable fee;
    int24 public immutable tickSpacing;
    uint128 public immutable maxLiquidityPerTick;

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

    function _modifyPosition(ModifyPositionParams memory params) 
        private 
        returns (Position.Info memory position, int256 amount0, int256 amount1) 
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

        return (positions[bytes32(0)], 0, 0);
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

        /// TODO: fees
        position.update(liquidityDelta, 0, 0);
    }

    function checkTicks(int24 tickLower, int24 tickUpper) 
        private pure 
    {
        require(tickLower < tickUpper);
        require(tickLower >= TickMath.MIN_TICK);
        require(tickUpper <= TickMath.MAX_TICK);
    }
}