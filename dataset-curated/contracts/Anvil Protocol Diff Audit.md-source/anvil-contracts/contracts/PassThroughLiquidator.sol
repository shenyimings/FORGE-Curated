// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "./interfaces/ILiquidator.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice ILiquidator implementation that liquidates by determining the contract to call as well as
 * the data to call it with from calldata. This is meant to be generic, allowing liquidation logic
 * to change without redeploying.
 */
contract PassThroughLiquidator is ILiquidator, Ownable2Step {
    using SafeERC20 for IERC20;

    // NB: Immutable to save gas. If, for some reason, this needs to change, redeploy.
    address private immutable authorizedCaller;

    error Unauthorized();

    constructor(address _owner, address _authorizedCaller) Ownable(_owner) {
        authorizedCaller = _authorizedCaller;
    }

    /**
     * Encodes the provided data so that it may be passed as the last argument of liquidate(...).
     * @param _addressToApprove The address that will be ERC-20 approved to transfer assets being liquidated.
     * @param _targetContract The contract to be called with `_data` to accomplish the liquidation.
     * @param _data The data being passed to `_targetContract` to accomplish the liquidation.
     * @return The encoded bytes.
     */
    function encodeParameters(
        address _addressToApprove,
        address _targetContract,
        bytes memory _data
    ) external pure returns (bytes memory) {
        return abi.encode(_addressToApprove, _targetContract, _data);
    }

    /**
     * Liquidates via the contract and data provided in the last parameter (`_liquidationParams`).
     * It is assumed that this contract call will result in the required output token amount being sent to
     * the `authorizedCaller`, though it is up to the `authorizedCaller` to verify that.
     * @dev Note: _liquidatorParams must be encoded in the format outlined by `encodeParameters(...)` above.
     *
     * @inheritdoc ILiquidator
     */
    function liquidate(
        address,
        address _inputTokenAddress,
        uint256 _maxInputTokenAmount,
        address,
        uint256,
        bytes calldata // _liquidatorParams
    ) external {
        if (msg.sender != authorizedCaller) revert Unauthorized();

        {
            IERC20 inputToken = IERC20(_inputTokenAddress);

            // The next two calls may return `false` on failure. Instead of asserting `true`, we'll save gas in the
            // happy path at the expense of gas in the failure path, which will revert in the swap below.

            /*** Obtain collateral tokens from msg.sender ***/
            // NB: This will fail without sufficient allowance provided by msg.sender
            inputToken.safeTransferFrom(msg.sender, address(this), _maxInputTokenAmount);

            address addressToApprove;
            assembly ("memory-safe") {
                // Calldata words 0-5 (ignoring method ID) are the parameters
                // [skipped] word 6 is the length of the _liquidatorParams bytes, but we know the structure of it so we can ignore it
                // word 7: 7*32 + 4 for method ID = 228 — this is the addressToApprove
                addressToApprove := calldataload(228)
            }

            // NB: Allowance will likely remain. If we're comfortable with it all being transferred right now,
            // we are comfortable with less being transferred and some approval amount remaining.
            inputToken.forceApprove(addressToApprove, _maxInputTokenAmount);
        }

        assembly ("memory-safe") {
            // word 8: 8*32 + 4 = 260 for method ID — this is the targetContract
            let targetContract := calldataload(260)
            // [skipped] word 9 of calldata is the byte index in the _liquidationParams where the encoded "data" starts (we know that is 96)

            // Set targetCalldata equal to the free memory pointer location. NB: we are not "allocating" memory.
            // We're just using unallocated memory as scratch space since we know that nothing will overwrite it while we use it.
            let targetCalldata := mload(0x40)
            // word 10: 10*32 + 4 for method ID = 324 — this is the size of the "data" array from _liquidatorParams
            let targetCalldataSize := calldataload(324)
            // word 11: 11*32 + 4 for method ID = 356 — this is the start byte of the bytes that make up "data"
            calldatacopy(targetCalldata, 356, targetCalldataSize) // populate data for the call below

            // call the targetContract with the provided data to execute the liquidation.
            let ok := call(gas(), targetContract, 0, targetCalldata, targetCalldataSize, 0, 0)
            if iszero(ok) {
                // NB: Just reuse the targetCalldata pointer since it's done being used.
                returndatacopy(targetCalldata, 0, returndatasize())
                revert(targetCalldata, returndatasize())
            }
        }
    }

    /**
     * @notice Transfers the entire balance of the specified token to the owner.
     * @dev Note that only the owner address may call this function.
     * @param _tokens The tokens to transfer to the owner.
     */
    function retrieveTokens(IERC20[] calldata _tokens) external onlyOwner {
        for (uint256 i = 0; i < _tokens.length; ++i) {
            uint256 balance = IERC20(_tokens[i]).balanceOf(address(this));
            if (balance > 0) {
                IERC20(_tokens[i]).safeTransfer(owner(), balance);
            }
        }
    }
}
