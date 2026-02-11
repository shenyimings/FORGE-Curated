// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.22;

import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {IMultiTokenMerkleDistributor} from "./interfaces/IMerkleDistributor.sol";

error AlreadyClaimed();
error InvalidProof();
error TokensAmountsMismatch();
error OnlyAdmin();
error WithdrawTooEarly();

contract MerkleDistributor is IMultiTokenMerkleDistributor {
    using SafeERC20 for IERC20;

    mapping(address => bool) public supportedTokens;
    address[] public tokenList;
    bytes32 public immutable override merkleRoot;

    // This is a packed array of booleans.
    mapping(uint256 => uint256) private claimedBitMap;

    address public immutable admin;
    uint256 public immutable withdrawableAt;

    constructor(bytes32 merkleRoot_, address[] memory tokens_, uint256 withdrawableAt_, address admin_) {
        merkleRoot = merkleRoot_;

        for (uint256 i = 0; i < tokens_.length; i++) {
            if (!supportedTokens[tokens_[i]]) {
                supportedTokens[tokens_[i]] = true;
                tokenList.push(tokens_[i]);
            }
        }

        admin = admin_;
        withdrawableAt = withdrawableAt_;
    }

    function isClaimed(uint256 index) public view override returns (bool) {
        unchecked {
            uint256 claimedWordIndex = index / 256;
            uint256 claimedBitIndex = index % 256;
            uint256 claimedWord = claimedBitMap[claimedWordIndex];
            uint256 mask = (1 << claimedBitIndex);
            return claimedWord & mask == mask;
        }
    }

    function _setClaimed(uint256 index) private {
        unchecked {
            uint256 claimedWordIndex = index / 256;
            uint256 claimedBitIndex = index % 256;
            claimedBitMap[claimedWordIndex] = claimedBitMap[claimedWordIndex] | (1 << claimedBitIndex);
        }
    }

    function claim(
        uint256 index,
        address account,
        address[] calldata tokens,
        uint256[] calldata amounts,
        bytes32[] calldata merkleProof
    ) public virtual override {
        if (isClaimed(index)) revert AlreadyClaimed();
        if (tokens.length != amounts.length) revert TokensAmountsMismatch();
        require(msg.sender == account, "Only the claim owner may execute their claim");

        // Verify the merkle proof with the new leaf structure
        bytes32 node = keccak256(abi.encodePacked(index, account, tokens, amounts));
        if (!MerkleProof.verifyCalldata(merkleProof, merkleRoot, node)) revert InvalidProof();

        // Mark it claimed and send the token.
        _setClaimed(index);
        for (uint256 i = 0; i < tokens.length; i++) {
            // No need to check for presence in supportedTokens - this is done implicitly in the MerkleProof.verify,
            // so long as the supported tokens supplied to the constructor correctly included all tokens found in each claim
            // require(supportedTokens[tokens[i]], "Token not supported");
            if (amounts[i] > 0) {
                IERC20(tokens[i]).safeTransfer(account, amounts[i]);
            }
        }

        emit Claimed(index, account, tokens, amounts);
    }

    function withdrawUnclaimed(address[] calldata tokens, address to) external {
        if (msg.sender != admin) revert OnlyAdmin();
        if (block.number < withdrawableAt) revert WithdrawTooEarly();

        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20 token = IERC20(tokens[i]);
            uint256 balance = token.balanceOf(address(this));
            if (balance > 0) {
                token.safeTransfer(to, balance);
            }
        }
    }
}
