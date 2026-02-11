// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.22;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";


/// @notice Simple Wrapped Ether implementation.
/// @author Solady (https://github.com/vectorized/solady/blob/main/src/tokens/WETH.sol)
/// @author Solmate (https://github.com/transmissions11/solmate/blob/main/src/tokens/WETH.sol)
/// @author Inspired by WETH9 (https://github.com/dapphub/ds-weth/blob/master/src/weth9.sol)
/// @author Opentensor Technologies - @camfairchild (https://github.com/opentensor/)

contract WTAO is ERC20, ERC20Permit {
    // ============================ CUSTOM ERRORS ============================

    /// @dev The TAO transfer has failed.
    error TAOTransferFailed();

    constructor()
        ERC20("Wrapped TAO", "WTAO")
        ERC20Permit("WTAO")
    {}

    // ============================ WTAO FUNCTIONS ============================

    /// @dev Deposits `amount` TAO of the caller and mints `amount` WTAO to the caller.
    function deposit() public payable virtual {
        _mint(msg.sender, msg.value);
    }

    /// @dev Burns `amount` WTAO of the caller and sends `amount` TAO to the caller.
    function withdraw(uint256 amount) public virtual {
        _burn(msg.sender, amount);
        /// @solidity memory-safe-assembly
        assembly {
            // Transfer the TAO and check if it succeeded or not.
            if iszero(call(gas(), caller(), amount, codesize(), 0x00, codesize(), 0x00)) {
                mstore(0x00, 0xb12d13eb) // `TAOTransferFailed()`.
                revert(0x1c, 0x04)
            }
        }
    }

    /// @dev Equivalent to `deposit()`.
    receive() external payable virtual {
        deposit();
    }
}
