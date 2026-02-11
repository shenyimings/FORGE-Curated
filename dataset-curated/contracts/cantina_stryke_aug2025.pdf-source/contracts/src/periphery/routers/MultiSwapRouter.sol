// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.0 <0.9.0;

import {Multicall} from "openzeppelin-contracts/contracts/utils/Multicall.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "openzeppelin-contracts/contracts/token/ERC721/IERC721.sol";
import {IERC721Receiver} from "openzeppelin-contracts/contracts/token/ERC721/IERC721Receiver.sol";
import {IOptionMarketOTMFE} from "../../interfaces/apps/options/IOptionMarketOTMFE.sol";
import {ISwapper} from "../../interfaces/ISwapper.sol";
import {IWETH} from "../../interfaces/IWETH.sol";

/// @title MultiSwapRouter
/// @notice A router contract that facilitates token swaps and options minting
/// @dev Implements Multicall for batch transactions and IERC721Receiver for handling NFTs
contract MultiSwapRouter is Multicall, IERC721Receiver {
    using SafeERC20 for IERC20;

    /// @notice Emitted when an option is minted through this router
    /// @param user The address initiating the mint
    /// @param receiver The address receiving the minted option
    /// @param market The address of the option market
    /// @param optionId The ID of the minted option
    /// @param frontendId The identifier of the frontend used
    /// @param referralId The referral code used for the mint
    event MintOption(
        address user, address receiver, address market, uint256 optionId, bytes32 frontendId, bytes32 referralId
    );

    /// @notice Wraps ETH into WETH
    /// @param weth The address of the WETH contract
    /// @param amount The amount of ETH to wrap
    function wrap(address weth, uint256 amount) external payable {
        IWETH(weth).deposit{value: amount}();
        IERC20(weth).safeTransfer(msg.sender, amount);
    }

    /// @notice Executes multiple token swaps through specified swapper contracts
    /// @param swapper Array of swapper contract addresses
    /// @param tokensIn Array of input token addresses
    /// @param tokensOut Array of output token addresses
    /// @param amounts Array of input amounts
    /// @param swapData Array of encoded swap data for each swap
    function swap(
        address[] calldata swapper,
        address[] calldata tokensIn,
        address[] calldata tokensOut,
        uint256[] calldata amounts,
        bytes[] calldata swapData
    ) external {
        for (uint256 i; i < tokensIn.length; i++) {
            IERC20(tokensIn[i]).safeTransferFrom(msg.sender, swapper[i], amounts[i]);
            ISwapper(swapper[i]).onSwapReceived(tokensIn[i], tokensOut[i], amounts[i], swapData[i]);
        }
    }

    /// @notice Mints an option through the specified option market
    /// @param market The option market contract
    /// @param optionParams The parameters for the option to be minted
    /// @param optionRecipient The address that will receive the minted option
    /// @param self Whether to transfer tokens through this contract first
    /// @param frontendId The identifier of the frontend used
    /// @param referralId The referral code for the mint
    function mintOption(
        IOptionMarketOTMFE market,
        IOptionMarketOTMFE.OptionParams memory optionParams,
        address optionRecipient,
        bool self,
        bytes32 frontendId,
        bytes32 referralId
    ) external {
        address callAsset = market.callAsset();
        address putAsset = market.putAsset();

        if (!self) {
            if (optionParams.isCall) {
                IERC20(callAsset).safeTransferFrom(msg.sender, address(this), optionParams.maxCostAllowance);
                IERC20(callAsset).approve(address(market), optionParams.maxCostAllowance);
            } else {
                IERC20(putAsset).safeTransferFrom(msg.sender, address(this), optionParams.maxCostAllowance);
                IERC20(putAsset).approve(address(market), optionParams.maxCostAllowance);
            }
        } else {
            if (optionParams.isCall) {
                IERC20(callAsset).safeIncreaseAllowance(address(market), optionParams.maxCostAllowance);
            } else {
                IERC20(putAsset).safeIncreaseAllowance(address(market), optionParams.maxCostAllowance);
            }
        }

        market.mintOption(optionParams);

        uint256 tokenId = market.optionIds();

        IERC721(address(market)).transferFrom(address(this), optionRecipient, tokenId);

        emit MintOption(msg.sender, optionRecipient, address(market), tokenId, frontendId, referralId);
    }

    /// @notice Sweeps any remaining tokens from the contract to a specified address
    /// @param token The token address to sweep
    /// @param to The address to send the tokens to
    function sweep(address token, address to) external {
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }

    /// @notice Required implementation for IERC721Receiver
    /// @dev Allows this contract to receive ERC721 tokens
    /// @return bytes4 The function selector
    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
