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

// interfaces
import {Steel} from "risc0/steel/Steel.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// contracts
import {IZkVerifier} from "src/verifier/ZkVerifier.sol";
import {mErc20Upgradable} from "src/mToken/mErc20Upgradable.sol";

import {mTokenProofDecoderLib} from "src/libraries/mTokenProofDecoderLib.sol";

import {IRoles} from "src/interfaces/IRoles.sol";
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import {IOperatorDefender} from "src/interfaces/IOperator.sol";
import {ImTokenOperationTypes} from "src/interfaces/ImToken.sol";

import {Migrator} from "src/migration/Migrator.sol";

contract mErc20Host is mErc20Upgradable, ImErc20Host, ImTokenOperationTypes {
    using SafeERC20 for IERC20;

    // Add flash mint callback success constant
    bytes4 private constant FLASH_MINT_CALLBACK_SUCCESS = 
        bytes4(keccak256("onFlashMint(address,uint256,bytes)"));

    // Add migrator address
    address public migrator;

    // Add modifier for migrator only
    modifier onlyMigrator() {
        require(msg.sender == migrator, mErc20Host_CallerNotAllowed());
        _;
    }

    // ----------- STORAGE ------------
    mapping(uint32 => mapping(address => uint256)) public accAmountInPerChain;
    mapping(uint32 => mapping(address => uint256)) public accAmountOutPerChain;
    mapping(address => mapping(address => bool)) public allowedCallers;
    mapping(uint32 => bool) public allowedChains;
    mapping(uint32 => uint256) public gasFees;
    IZkVerifier public verifier;

    /**
     * @notice Initializes the new money market
     * @param underlying_ The address of the underlying asset
     * @param operator_ The address of the Operator
     * @param interestRateModel_ The address of the interest rate model
     * @param initialExchangeRateMantissa_ The initial exchange rate, scaled by 1e18
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     * @param admin_ Address of the administrator of this token
     * @param zkVerifier_ The IZkVerifier address
     */
    function initialize(
        address underlying_,
        address operator_,
        address interestRateModel_,
        uint256 initialExchangeRateMantissa_,
        string memory name_,
        string memory symbol_,
        uint8 decimals_,
        address payable admin_,
        address zkVerifier_,
        address roles_
    ) external initializer {
        // Initialize the base contract
        _proxyInitialize(
            underlying_, operator_, interestRateModel_, initialExchangeRateMantissa_, name_, symbol_, decimals_, admin_
        );
        require(zkVerifier_ != address(0), mErc20Host_AddressNotValid());

        verifier = IZkVerifier(zkVerifier_);

        rolesOperator = IRoles(roles_);

        // Set the proper admin now that initialization is done
        admin = admin_;
    }

    // ----------- VIEW ------------
    /**
     * @inheritdoc ImErc20Host
     */
    function isCallerAllowed(address sender, address caller) external view returns (bool) {
        return allowedCallers[sender][caller];
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function getProofData(address user, uint32 dstId) external view returns (uint256, uint256) {
        return (accAmountInPerChain[dstId][user], accAmountOutPerChain[dstId][user]);
    }

    // ----------- OWNER ------------
    /**
     * @notice Updates an allowed chain status
     * @param _chainId the chain id
     * @param _status the new status
     */
    function updateAllowedChain(uint32 _chainId, bool _status) external {
        if (msg.sender != admin && !_isAllowedFor(msg.sender, rolesOperator.CHAINS_MANAGER())) {
            revert mErc20Host_CallerNotAllowed();
        }
        allowedChains[_chainId] = _status;
        emit mErc20Host_ChainStatusUpdated(_chainId, _status);
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function extractForRebalancing(uint256 amount) external {
        IOperatorDefender(operator).beforeRebalancing(address(this));

        if (!_isAllowedFor(msg.sender, rolesOperator.REBALANCER())) revert mErc20Host_NotRebalancer();
        IERC20(underlying).safeTransfer(msg.sender, amount);
    }

    /**
     * @notice Sets the migrator address
     * @param _migrator The new migrator address
     */
    function setMigrator(address _migrator) external onlyAdmin {
        require(_migrator != address(0), mErc20Host_AddressNotValid());
        migrator = _migrator;
    }

    /**
     * @notice Sets the gas fee
     * @param dstChainId the destination chain id
     * @param amount the gas fee amount
     */
    function setGasFee(uint32 dstChainId, uint256 amount) external onlyAdmin {
        gasFees[dstChainId] = amount;
        emit mErc20Host_GasFeeUpdated(dstChainId, amount);
    }

    /**
     * @notice Withdraw gas received so far
     * @param receiver the receiver address
     */
    function withdrawGasFees(address payable receiver) external {
        if (msg.sender != admin && !_isAllowedFor(msg.sender, _getSequencerRole())) {
            revert mErc20Host_CallerNotAllowed();
        }
        uint256 balance = address(this).balance;
        receiver.transfer(balance);
    }

    /**
     * @notice Updates IZkVerifier address
     * @param _zkVerifier the verifier address
     */
    function updateZkVerifier(address _zkVerifier) external onlyAdmin {
        require(_zkVerifier != address(0), mErc20Host_AddressNotValid());
        emit ZkVerifierUpdated(address(verifier), _zkVerifier);
        verifier = IZkVerifier(_zkVerifier);
    }

    // ----------- PUBLIC ------------
    /**
     * @inheritdoc ImErc20Host
     */
    function updateAllowedCallerStatus(address caller, bool status) external override {
        allowedCallers[msg.sender][caller] = status;
        emit AllowedCallerUpdated(msg.sender, caller, status);
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function liquidateExternal(
        bytes calldata journalData,
        bytes calldata seal,
        address[] calldata userToLiquidate,
        uint256[] calldata liquidateAmount,
        address[] calldata collateral,
        address receiver
    ) external override {
        // verify received data
        if (!_isAllowedFor(msg.sender, _getBatchProofForwarderRole())) {
            _verifyProof(journalData, seal);
        }

        bytes[] memory journals = abi.decode(journalData, (bytes[]));
        uint256 length = journals.length;
        require(length == liquidateAmount.length, mErc20Host_LengthMismatch());
        require(length == userToLiquidate.length, mErc20Host_LengthMismatch());
        require(length == collateral.length, mErc20Host_LengthMismatch());

        for (uint256 i; i < length;) {
            _liquidateExternal(journals[i], userToLiquidate[i], liquidateAmount[i], collateral[i], receiver);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function mintExternal(
        bytes calldata journalData,
        bytes calldata seal,
        uint256[] calldata mintAmount,
        uint256[] calldata minAmountsOut,
        address receiver
    ) external override {
        if (!_isAllowedFor(msg.sender, _getBatchProofForwarderRole())) {
            _verifyProof(journalData, seal);
        }

        _checkOutflow(_computeTotalOutflowAmount(mintAmount));

        bytes[] memory journals = abi.decode(journalData, (bytes[]));
        uint256 length = journals.length;
        require(length == mintAmount.length, mErc20Host_LengthMismatch());

        for (uint256 i; i < length;) {
            _mintExternal(journals[i], mintAmount[i], minAmountsOut[i], receiver);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function repayExternal(
        bytes calldata journalData,
        bytes calldata seal,
        uint256[] calldata repayAmount,
        address receiver
    ) external override {
        if (!_isAllowedFor(msg.sender, _getBatchProofForwarderRole())) {
            _verifyProof(journalData, seal);
        }

        _checkOutflow(_computeTotalOutflowAmount(repayAmount));

        bytes[] memory journals = abi.decode(journalData, (bytes[]));
        uint256 length = journals.length;
        require(length == repayAmount.length, mErc20Host_LengthMismatch());

        for (uint256 i; i < length;) {
            _repayExternal(journals[i], repayAmount[i], receiver);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @inheritdoc ImErc20Host
     * @dev amount represents the number of mTokens to redeem
     */
    function withdrawOnExtension(uint256 amount, uint32 dstChainId) external payable override {
        require(amount > 0, mErc20Host_AmountNotValid());
        require(msg.value >= gasFees[dstChainId], mErc20Host_NotEnoughGasFee());
        require(allowedChains[dstChainId], mErc20Host_ChainNotValid());

        _checkOutflow(amount);

        // actions
        uint256 underlyingAmount = _redeem(msg.sender, amount, false);
        accAmountOutPerChain[dstChainId][msg.sender] += underlyingAmount;

        emit mErc20Host_WithdrawOnExtensionChain(msg.sender, dstChainId, underlyingAmount);
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function borrowOnExtension(uint256 amount, uint32 dstChainId) external payable override {
        require(amount > 0, mErc20Host_AmountNotValid());
        require(msg.value >= gasFees[dstChainId], mErc20Host_NotEnoughGasFee());
        require(allowedChains[dstChainId], mErc20Host_ChainNotValid());

        _checkOutflow(amount);

        // actions
        accAmountOutPerChain[dstChainId][msg.sender] += amount;
        _borrow(msg.sender, amount, false);

        emit mErc20Host_BorrowOnExtensionChain(msg.sender, dstChainId, amount);
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function mintMigration(uint256 amount, uint256 minAmount, address receiver) external onlyMigrator {
        require(amount > 0, mErc20Host_AmountNotValid());
        _mint(receiver, receiver, amount, minAmount, false);
        emit mErc20Host_MintMigration(receiver, amount);
    }

    /**
     * @inheritdoc ImErc20Host
     */
    function borrowMigration(uint256 amount, address borrower, address receiver) external onlyMigrator {
        require(amount > 0, mErc20Host_AmountNotValid());
        _borrowWithReceiver(borrower, receiver, amount);
        emit mErc20Host_BorrowMigration(borrower, amount);
    }

    // ----------- PRIVATE ------------
    function _computeTotalOutflowAmount(uint256[] calldata amounts) private pure returns (uint256) {
        uint256 sum;
        uint256 length = amounts.length;
        for (uint256 i; i< length;) {
            sum += amounts[i];
            unchecked { ++i; }
        }
        return sum;
    }

    function _checkOutflow(uint256 amount) private {
        IOperatorDefender(operator).checkOutflowVolumeLimit(amount);
    }

    function _isAllowedFor(address _sender, bytes32 role) private view returns (bool) {
        return rolesOperator.isAllowedFor(_sender, role);
    }

    function _getProofForwarderRole() private view returns (bytes32) {
        return rolesOperator.PROOF_FORWARDER();
    }

    function _getBatchProofForwarderRole() private view returns (bytes32) {
        return rolesOperator.PROOF_BATCH_FORWARDER();
    }

    function _getSequencerRole() private view returns (bytes32) {
        return rolesOperator.SEQUENCER();
    }

    function _verifyProof(bytes calldata journalData, bytes calldata seal) private view {
        require(journalData.length > 0, mErc20Host_JournalNotValid());

        // Decode the dynamic array of journals.
        bytes[] memory journals = abi.decode(journalData, (bytes[]));

        // Check the L1Inclusion flag for each journal.
        bool isSequencer = _isAllowedFor(msg.sender, _getProofForwarderRole()) || 
                        _isAllowedFor(msg.sender, _getBatchProofForwarderRole());

        if (!isSequencer) {
            for (uint256 i = 0; i < journals.length; i++) {
                (, , , , , , bool L1Inclusion) = mTokenProofDecoderLib.decodeJournal(journals[i]);
                if (!L1Inclusion) {
                    revert mErc20Host_L1InclusionRequired();
                }
            }
        }

        // verify it using the IZkVerifier contract
        verifier.verifyInput(journalData, seal);
    }

    function _checkSender(address msgSender, address srcSender) private view {
        if (msgSender != srcSender) {
            require(
                allowedCallers[srcSender][msgSender] || msgSender == admin
                    || _isAllowedFor(msgSender, _getProofForwarderRole())
                    || _isAllowedFor(msgSender, _getBatchProofForwarderRole()),
                mErc20Host_CallerNotAllowed()
            );
        }
    }

    function _liquidateExternal(
        bytes memory singleJournal,
        address userToLiquidate,
        uint256 liquidateAmount,
        address collateral,
        address receiver
    ) internal {
        (address _sender, address _market, uint256 _accAmountIn,, uint32 _chainId, uint32 _dstChainId,) =
            mTokenProofDecoderLib.decodeJournal(singleJournal);

        // temporary overwrite; will be removed in future implementations
        receiver = _sender;

        // base checks
        {
            _checkSender(msg.sender, _sender);
            require(_dstChainId == uint32(block.chainid), mErc20Host_DstChainNotValid());
            require(_market == address(this), mErc20Host_AddressNotValid());
            require(allowedChains[_chainId], mErc20Host_ChainNotValid());
        }
        // operation checks
        {
            require(liquidateAmount > 0, mErc20Host_AmountNotValid());
            require(liquidateAmount <= _accAmountIn - accAmountInPerChain[_chainId][_sender], mErc20Host_AmountTooBig());
            require(userToLiquidate != msg.sender && userToLiquidate != _sender, mErc20Host_CallerNotAllowed());
        }
        collateral = collateral == address(0) ? address(this) : collateral;

        // actions
        accAmountInPerChain[_chainId][_sender] += liquidateAmount;
        _liquidate(receiver, userToLiquidate, liquidateAmount, collateral, false);

        emit mErc20Host_LiquidateExternal(
            msg.sender, _sender, userToLiquidate, receiver, collateral, _chainId, liquidateAmount
        );
    }

    function _mintExternal(bytes memory singleJournal, uint256 mintAmount, uint256 minAmountOut, address receiver)
        internal
    {
        (address _sender, address _market, uint256 _accAmountIn, , uint32 _chainId, uint32 _dstChainId,) =
            mTokenProofDecoderLib.decodeJournal(singleJournal);

        // temporary overwrite; will be removed in future implementations
        receiver = _sender;

        // base checks
        {
            _checkSender(msg.sender, _sender);
            require(_dstChainId == uint32(block.chainid), mErc20Host_DstChainNotValid());
            require(_market == address(this), mErc20Host_AddressNotValid());
            require(allowedChains[_chainId], mErc20Host_ChainNotValid());
        }
        // operation checks
        {
            require(mintAmount > 0, mErc20Host_AmountNotValid());
            require(mintAmount <= _accAmountIn - accAmountInPerChain[_chainId][_sender], mErc20Host_AmountTooBig());
        }

        // actions
        accAmountInPerChain[_chainId][_sender] += mintAmount;
        _mint(receiver, receiver, mintAmount, minAmountOut, false);

        emit mErc20Host_MintExternal(msg.sender, _sender, receiver, _chainId, mintAmount);
    }

    function _repayExternal(bytes memory singleJournal, uint256 repayAmount, address receiver) internal {
        (address _sender, address _market, uint256 _accAmountIn,, uint32 _chainId, uint32 _dstChainId,) =
            mTokenProofDecoderLib.decodeJournal(singleJournal);

        // temporary overwrite; will be removed in future implementations
        receiver = _sender;

        // base checks
        {
            _checkSender(msg.sender, _sender);
            require(_dstChainId == uint32(block.chainid), mErc20Host_DstChainNotValid());
            require(_market == address(this), mErc20Host_AddressNotValid());
            require(allowedChains[_chainId], mErc20Host_ChainNotValid());
            require(repayAmount > 0, mErc20Host_AmountNotValid());
        }

        uint256 actualRepayAmount = _repayBehalf(receiver, repayAmount, false);

        // operation checks
        {
            require(
                actualRepayAmount <= _accAmountIn - accAmountInPerChain[_chainId][_sender], mErc20Host_AmountTooBig()
            );
        }

        // actions
        accAmountInPerChain[_chainId][_sender] += actualRepayAmount;

        emit mErc20Host_RepayExternal(msg.sender, _sender, receiver, _chainId, actualRepayAmount);
    }
}
