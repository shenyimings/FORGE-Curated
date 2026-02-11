// Copyright (c) 2025 Merge Layers Inc.
//
// This source code is licensed under the Business Source License 1.1
// (the "License"); you may not use this file except in compliance with the
// License. You may obtain a copy of the License at
//
//     https://github.com/malda-protocol/malda-lending/blob/main/LICENSE-BSL
//
// See the License for the specific language governing permissions and
// limitations under the License.
//
// This file contains code derived from or inspired by Compound V2,
// originally licensed under the BSD 3-Clause License. See LICENSE-COMPOUND-V2
// for original license terms and attributions.

// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// contracts
import {IRoles} from "src/interfaces/IRoles.sol";
import {ImTokenGateway} from "src/interfaces/ImTokenGateway.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

import {mTokenProofDecoderLib} from "src/libraries/mTokenProofDecoderLib.sol";

import {IZkVerifier} from "src/verifier/ZkVerifier.sol";

contract mTokenGateway is OwnableUpgradeable, ImTokenGateway, ImTokenOperationTypes {
    using SafeERC20 for IERC20;

    // ----------- STORAGE -----------
    /**
     * @inheritdoc ImTokenGateway
     */
    IRoles public rolesOperator;

    IZkVerifier public verifier;

    mapping(OperationType => bool) public paused;

    /**
     * @inheritdoc ImTokenGateway
     */
    address public underlying;

    mapping(address => uint256) public accAmountIn;
    mapping(address => uint256) public accAmountOut;
    mapping(address => mapping(address => bool)) public allowedCallers;
    mapping(address => bool) public userWhitelisted;
    bool public whitelistEnabled;

    uint32 private constant LINEA_CHAIN_ID = 59144;

    ///@dev gas fee for `supplyOnHost`
    uint256 public gasFee;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address payable _owner, address _underlying, address _roles, address zkVerifier_)
        external
        initializer
    {
        __Ownable_init(_owner);
        require(zkVerifier_ != address(0), mTokenGateway_AddressNotValid());

        underlying = _underlying;
        rolesOperator = IRoles(_roles);

        verifier = IZkVerifier(zkVerifier_);
    }

    modifier notPaused(OperationType _type) {
        require(!paused[_type], mTokenGateway_Paused(_type));
        _;
    }

    modifier onlyAllowedUser(address user) {
        if (whitelistEnabled) {
            require(userWhitelisted[user], mTokenGateway_UserNotWhitelisted());
        }
        _;
    }

    // ----------- VIEW ------------
    /**
     * @inheritdoc ImTokenGateway
     */
    function isPaused(OperationType _type) external view returns (bool) {
        return paused[_type];
    }

    /**
     * @inheritdoc ImTokenGateway
     */
    function isCallerAllowed(address sender, address caller) external view returns (bool) {
        return allowedCallers[sender][caller];
    }

    /**
     * @inheritdoc ImTokenGateway
     */
    function getProofData(address user, uint32) external view returns (uint256, uint256) {
        return (accAmountIn[user], accAmountOut[user]);
    }

    // ----------- OWNER ------------
    /**
     * @notice Sets user whitelist status
     * @param user The user address
     * @param state The new staate
     */
    function setWhitelistedUser(address user, bool state) external onlyOwner {
        userWhitelisted[user] = state;
        emit mTokenGateway_UserWhitelisted(user, state);
    }

    /**
     * @notice Enable user whitelist
     */
    function enableWhitelist() external onlyOwner {
        whitelistEnabled = true;
        emit mTokenGateway_WhitelistEnabled();
    }

    /**
     * @notice Disable user whitelist
     */
    function disableWhitelist() external onlyOwner {
        whitelistEnabled = false;
        emit mTokenGateway_WhitelistDisabled();
    }

    /**
     * @inheritdoc ImTokenGateway
     */
    function setPaused(OperationType _type, bool state) external override {
        if (state) {
            require(
                msg.sender == owner() || rolesOperator.isAllowedFor(msg.sender, rolesOperator.GUARDIAN_PAUSE()),
                mTokenGateway_CallerNotAllowed()
            );
        } else {
            require(msg.sender == owner(), mTokenGateway_CallerNotAllowed());
        }

        emit mTokenGateway_PausedState(_type, state);
        paused[_type] = state;
    }

    /**
     * @inheritdoc ImTokenGateway
     */
    function extractForRebalancing(uint256 amount) external notPaused(OperationType.Rebalancing) {
        if (!rolesOperator.isAllowedFor(msg.sender, rolesOperator.REBALANCER())) revert mTokenGateway_NotRebalancer();
        IERC20(underlying).safeTransfer(msg.sender, amount);
    }

    // temporary. V1.0.1
    function setUnderlying(address _addr) external onlyOwner {
        underlying = _addr;
    }
    
    /**
     * @notice Sets the gas fee
     * @param amount the new gas fee
     */
    function setGasFee(uint256 amount) external onlyOwner {
        gasFee = amount;
        emit mTokenGateway_GasFeeUpdated(amount);
    }

    /**
     * @notice Withdraw gas received so far
     * @param receiver the receiver address
     */
    function withdrawGasFees(address payable receiver) external {
        if (msg.sender != owner() && !_isAllowedFor(msg.sender, _getSequencerRole())) {
            revert mTokenGateway_CallerNotAllowed();
        }
        uint256 balance = address(this).balance;
        receiver.transfer(balance);
    }

    /**
     * @notice Updates IZkVerifier address
     * @param _zkVerifier the verifier address
     */
    function updateZkVerifier(address _zkVerifier) external onlyOwner {
        require(_zkVerifier != address(0), mTokenGateway_AddressNotValid());
        emit ZkVerifierUpdated(address(verifier), _zkVerifier);
        verifier = IZkVerifier(_zkVerifier);
    }

    // ----------- PUBLIC ------------
    /**
     * @inheritdoc ImTokenGateway
     */
    function updateAllowedCallerStatus(address caller, bool status) external override {
        allowedCallers[msg.sender][caller] = status;
        emit AllowedCallerUpdated(msg.sender, caller, status);
    }

    /**
     * @inheritdoc ImTokenGateway
     */
    function supplyOnHost(uint256 amount, address receiver, bytes4 lineaSelector)
        external
        payable
        override
        notPaused(OperationType.AmountIn)
        onlyAllowedUser(msg.sender)
    {
        // checks
        require(amount > 0, mTokenGateway_AmountNotValid());
        require(msg.value >= gasFee, mTokenGateway_NotEnoughGasFee());

        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);

        // effects
        accAmountIn[receiver] += amount;

        emit mTokenGateway_Supplied(
            msg.sender,
            receiver,
            accAmountIn[receiver],
            accAmountOut[receiver],
            amount,
            uint32(block.chainid),
            LINEA_CHAIN_ID,
            lineaSelector
        );
    }

    /**
     * @inheritdoc ImTokenGateway
     */
    function outHere(bytes calldata journalData, bytes calldata seal, uint256[] calldata amounts, address receiver)
        external
        notPaused(OperationType.AmountOutHere)
    {
        // verify received data
        if (!rolesOperator.isAllowedFor(msg.sender, rolesOperator.PROOF_BATCH_FORWARDER())) {
            _verifyProof(journalData, seal);
        }

        bytes[] memory journals = abi.decode(journalData, (bytes[]));
        uint256 length = journals.length;
        require(length == amounts.length, mTokenGateway_LengthNotValid());

        for (uint256 i; i < journals.length;) {
            _outHere(journals[i], amounts[i], receiver);

            unchecked {
                ++i;
            }
        }
    }

    function _outHere(bytes memory journalData, uint256 amount, address receiver) internal {
        (address _sender, address _market,, uint256 _accAmountOut, uint32 _chainId, uint32 _dstChainId,) =
            mTokenProofDecoderLib.decodeJournal(journalData);

        // temporary overwrite; will be removed in future implementations
        receiver = _sender;

        // checks
        _checkSender(msg.sender, _sender);
        require(_market == address(this), mTokenGateway_AddressNotValid());
        require(_chainId == LINEA_CHAIN_ID, mTokenGateway_ChainNotValid()); // allow only Host
        require(_dstChainId == uint32(block.chainid), mTokenGateway_ChainNotValid());
        require(amount > 0, mTokenGateway_AmountNotValid());
        require(_accAmountOut - accAmountOut[_sender] >= amount, mTokenGateway_AmountTooBig());
        require(IERC20(underlying).balanceOf(address(this)) >= amount, mTokenGateway_ReleaseCashNotAvailable());

        // effects
        accAmountOut[_sender] += amount;

        // interactions
        IERC20(underlying).safeTransfer(_sender, amount);

        emit mTokenGateway_Extracted(
            msg.sender,
            _sender,
            receiver,
            accAmountIn[_sender],
            accAmountOut[_sender],
            amount,
            uint32(_chainId),
            uint32(block.chainid)
        );
    }

    // ----------- PRIVATE ------------
    function _verifyProof(bytes calldata journalData, bytes calldata seal) private view {
        require(journalData.length > 0, mTokenGateway_JournalNotValid());


        // Decode the dynamic array of journals.
        bytes[] memory journals = abi.decode(journalData, (bytes[]));

        // Check the L1Inclusion flag for each journal.
        bool isSequencer = _isAllowedFor(msg.sender, _getProofForwarderRole()) || 
                        _isAllowedFor(msg.sender, _getBatchProofForwarderRole());

        if (!isSequencer) {
            for (uint256 i = 0; i < journals.length; i++) {
                (, , , , , , bool L1Inclusion) = mTokenProofDecoderLib.decodeJournal(journals[i]);
                if (!L1Inclusion) {
                    revert mTokenGateway_L1InclusionRequired();
                }
            }
        }

        // verify it using the ZkVerifier contract
        verifier.verifyInput(journalData, seal);
    }

    function _checkSender(address msgSender, address srcSender) private view {
        if (msgSender != srcSender) {
            require(
                allowedCallers[srcSender][msgSender] || msgSender == owner()
                    || _isAllowedFor(msgSender, _getProofForwarderRole())
                    || _isAllowedFor(msgSender, _getBatchProofForwarderRole()),
                mTokenGateway_CallerNotAllowed()
            );
        }
    }

    function _getSequencerRole() private view returns (bytes32) {
        return rolesOperator.SEQUENCER();
    }

    function _getBatchProofForwarderRole() private view returns (bytes32) {
        return rolesOperator.PROOF_BATCH_FORWARDER();
    }

    function _getProofForwarderRole() private view returns (bytes32) {
        return rolesOperator.PROOF_FORWARDER();
    }

    function _isAllowedFor(address _sender, bytes32 role) private view returns (bool) {
        return rolesOperator.isAllowedFor(_sender, role);
    }
}
