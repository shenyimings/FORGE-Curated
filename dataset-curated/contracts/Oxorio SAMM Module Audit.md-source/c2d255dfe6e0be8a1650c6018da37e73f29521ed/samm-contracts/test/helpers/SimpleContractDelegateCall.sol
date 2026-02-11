// SPDX-License-Identifier: GPL-3
pragma solidity 0.8.23;

contract SimpleContractDelegateCall {
    // uint256(keccak256("MAGIC_SLOT"))
    uint256 public constant MAGIC_SLOT = 94974743322102077237964283079579489083370958841029978203610717170300998050309;

    function call(uint256 value) external {
        assembly {
            sstore(MAGIC_SLOT, value)
        }
    }

    function getMagicValue() external view returns (uint256 value) {
        assembly {
            value := sload(MAGIC_SLOT)
        }
    }
}
