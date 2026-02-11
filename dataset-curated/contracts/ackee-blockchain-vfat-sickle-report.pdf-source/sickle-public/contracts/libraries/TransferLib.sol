// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { MsgValueModule } from "contracts/modules/MsgValueModule.sol";
import { WETH } from "lib/solmate/src/tokens/WETH.sol";
import { Sickle } from "contracts/Sickle.sol";
import { SafeTransferLib } from "lib/solmate/src/utils/SafeTransferLib.sol";
import { IERC20 } from
    "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import { IFeesLib } from "contracts/interfaces/libraries/IFeesLib.sol";
import { DelegateModule } from "contracts/modules/DelegateModule.sol";
import { ITransferLib } from "contracts/interfaces/libraries/ITransferLib.sol";

contract TransferLib is MsgValueModule, DelegateModule, ITransferLib {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    WETH public immutable weth;

    IFeesLib public immutable feesLib;

    constructor(IFeesLib feesLib_, WETH weth_) {
        feesLib = feesLib_;
        weth = weth_;
    }

    /// @dev Transfers the balance of {token} from the contract to the
    /// sickle owner
    /// @param token Address of the token to transfer
    function transferTokenToUser(
        address token
    ) public payable checkTransferTo(token) {
        address recipient = Sickle(payable(address(this))).owner();
        if (token == ETH) {
            uint256 wethBalance = weth.balanceOf(address(this));
            if (wethBalance > 0) {
                weth.withdraw(wethBalance);
            }
            if (address(this).balance > 0) {
                SafeTransferLib.safeTransferETH(
                    recipient, address(this).balance
                );
            }
        } else {
            uint256 balance = IERC20(token).balanceOf(address(this));
            if (balance > 0) {
                SafeTransferLib.safeTransfer(token, recipient, balance);
            }
        }
    }

    /// @dev Transfers all balances of {tokens} and/or ETH from the contract
    /// to the sickle owner
    /// @param tokens An array of token addresses
    function transferTokensToUser(
        address[] memory tokens
    ) external payable checkTransfersTo(tokens) {
        for (uint256 i; i != tokens.length;) {
            transferTokenToUser(tokens[i]);

            unchecked {
                i++;
            }
        }
    }

    /// @dev Transfers {amountIn} of {tokenIn} from the user to the Sickle
    /// contract, charging the fees and converting the amount to WETH if
    /// necessary
    /// @param tokenIn Address of the token to transfer
    /// @param amountIn Amount of the token to transfer
    /// @param strategy Address of the caller strategy
    /// @param feeSelector Selector of the caller function
    function transferTokenFromUser(
        address tokenIn,
        uint256 amountIn,
        address strategy,
        bytes4 feeSelector
    ) public payable checkTransferFrom(tokenIn, amountIn) {
        _checkMsgValue(amountIn, tokenIn == ETH);

        _transferTokenFromUser(tokenIn, amountIn, strategy, feeSelector);
    }

    /// @dev Transfers {amountIn} of {tokenIn} from the user to the Sickle
    /// contract, charging the fees and converting the amount to WETH if
    /// necessary
    /// @param tokensIn Addresses of the tokens to transfer
    /// @param amountsIn Amounts of the tokens to transfer
    /// @param strategy Address of the caller strategy
    /// @param feeSelector Selector of the caller function
    function transferTokensFromUser(
        address[] memory tokensIn,
        uint256[] memory amountsIn,
        address strategy,
        bytes4 feeSelector
    ) external payable checkTransfersFrom(tokensIn, amountsIn) {
        bool hasEth = false;

        for (uint256 i; i < tokensIn.length; i++) {
            if (tokensIn[i] == ETH) {
                _checkMsgValue(amountsIn[i], true);
                hasEth = true;
            }
            _transferTokenFromUser(
                tokensIn[i], amountsIn[i], strategy, feeSelector
            );
        }

        if (!hasEth) {
            // Revert if ETH was sent but not used
            _checkMsgValue(0, false);
        }
    }

    /* Internal functions */

    function _transferTokenFromUser(
        address tokenIn,
        uint256 amountIn,
        address strategy,
        bytes4 feeSelector
    ) internal {
        if (tokenIn != ETH) {
            SafeTransferLib.safeTransferFrom(
                tokenIn,
                Sickle(payable(address(this))).owner(),
                address(this),
                amountIn
            );
        }

        bytes memory result = _delegateTo(
            address(feesLib),
            abi.encodeCall(
                IFeesLib.chargeFee, (strategy, feeSelector, tokenIn, 0)
            )
        );
        uint256 remainder = abi.decode(result, (uint256));

        if (tokenIn == ETH) {
            weth.deposit{ value: remainder }();
        }
    }

    modifier checkTransferFrom(address tokenIn, uint256 amountIn) {
        if (tokenIn == address(0)) {
            revert TokenInRequired();
        }
        if (amountIn == 0) {
            revert AmountInRequired();
        }
        _;
    }

    modifier checkTransfersFrom(
        address[] memory tokensIn,
        uint256[] memory amountsIn
    ) {
        uint256 tokenLength = tokensIn.length;
        if (tokenLength != amountsIn.length) {
            revert ArrayLengthMismatch();
        }
        if (tokenLength == 0) {
            revert TokenInRequired();
        }
        for (uint256 i; i < tokenLength; i++) {
            if (tokensIn[i] == address(0)) {
                revert TokenInRequired();
            }
            if (amountsIn[i] == 0) {
                revert AmountInRequired();
            }
        }
        if (tokenLength == 2 && tokensIn[0] == tokensIn[1]) {
            revert SameTokenIn();
        }
        if (tokenLength > 2) {
            revert TwoTokenMaximum();
        }
        _;
    }

    modifier checkTransferTo(
        address tokenOut
    ) {
        if (tokenOut == address(0)) {
            revert TokenOutRequired();
        }
        _;
    }

    modifier checkTransfersTo(
        address[] memory tokensOut
    ) {
        uint256 tokenLength = tokensOut.length;
        if (tokenLength == 0) {
            revert TokenOutRequired();
        }
        for (uint256 i; i < tokenLength; i++) {
            if (tokensOut[i] == address(0)) {
                revert TokenOutRequired();
            }
        }
        _;
    }
}
