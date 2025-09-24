// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.19;

import {BitMath} from "./BitMath.sol";

library TickBitmap {
    // Get the word and bit position of the tick
    function position(int24 tick) private pure returns (int16 wordPos, uint8 bitPos) {
        wordPos = int16(tick >> 8);
        bitPos = uint8(uint24(tick % 256));
    }

    // Flip the tick to the left or right of the next initialized tick
    function flipTick(mapping(int16 => uint256) storage self, int24 tick, int24 tickSpacing) internal {
        require(tick % tickSpacing == 0);
        (int16 wordPos, uint8 bitPos) = position(tick);
        uint256 mask = 1 << bitPos;
        // XOR 0 -> 1, XOR 1 -> 0
        self[wordPos] ^= mask;
    }

    // Search to the left or right of the next initialized tick
    function nextInitializedTickWithinOneWord(
        mapping(int16 => uint256) storage self,
        int24 tick,
        int24 tickSpacing,
        // true = seatch to the lef
        bool lte
    ) internal view returns (int24 next, bool initialized) {
        int24 compressed = tick / tickSpacing;
        // Round down to negative infinity
        if (tick < 0 && tick % tickSpacing != 0) {
            compressed--;
        }

        if (lte) {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            // All 1s at or to the right of bitPos
            uint256 mask = (1 << bitPos) -1 + (1 << bitPos);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;

            // next = (compressed - remove bit pos + right most bit of masked) * tickSpacing
            //      = (compressed - bit pos        + msb(masked)) * tick spacing
            next = initialized
                ? (compressed - int24(uint24(bitPos - BitMath.mostSignificantBit(masked)))) * tickSpacing
                : (compressed - int24(uint24(bitPos))) * tickSpacing;
        } else {
            (int16 wordPos, uint8 bitPos) = position(compressed);
            uint256 mask = ~((1 << bitPos) -1);
            uint256 masked = self[wordPos] & mask;

            initialized = masked != 0;

            // next = (next compressed tick + left most bit of masked - remove bit pos) * tick spacing
            next = initialized
                ? (compressed + 1 + int24(uint24(BitMath.leastSignificantBit(masked))) - int24(uint24(bitPos))) * tickSpacing
                : (compressed + 1 + int24(uint24(type(uint8).max - bitPos))) * tickSpacing;
        }
    }
}