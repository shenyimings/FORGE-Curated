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

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IRoles} from "src/interfaces/IRoles.sol";
import {ImTokenGateway} from "src/interfaces/ImTokenGateway.sol";
import {ImErc20Host} from "src/interfaces/ImErc20Host.sol";
import {IZkVerifier} from "src/verifier/ZkVerifier.sol";

contract BatchSubmitter is Ownable {
    error BatchSubmitter_CallerNotAllowed();
    error BatchSubmitter_JournalNotValid();
    error BatchSubmitter_InvalidSelector();
    error BatchSubmitter_AddressNotValid();

    event BatchProcessFailed(
        bytes32 initHash,
        address receiver,
        address mToken,
        uint256 amount,
        uint256 minAmountOut,
        bytes4 selector,
        bytes reason
    );
    event BatchProcessSuccess(
        bytes32 initHash, address receiver, address mToken, uint256 amount, uint256 minAmountOut, bytes4 selector
    );
    event ZkVerifierUpdated(address indexed oldVerifier, address indexed newVerifier);

    /**
     * @notice The roles contract for access control
     */
    IRoles public immutable rolesOperator;

    IZkVerifier public verifier;

    /**
     * receiver Funds receiver/performed on
     * journalData The encoded journal data
     * seal The seal data for verification
     * mTokens Array of mToken addresses
     * amounts Array of amounts for each operation
     * selectors Array of function selectors for each operation
     * startIndex Start index for processing journals
     * endIndex End index for processing journals (exclusive)
     */
    struct BatchProcessMsg {
        address[] receivers;
        bytes journalData;
        bytes seal;
        address[] mTokens;
        uint256[] amounts;
        uint256[] minAmountsOut;
        bytes4[] selectors;
        bytes32[] initHashes;
        uint256 startIndex;
    }

    // Function selectors for supported operations
    bytes4 internal constant MINT_SELECTOR = ImErc20Host.mintExternal.selector;
    bytes4 internal constant REPAY_SELECTOR = ImErc20Host.repayExternal.selector;
    bytes4 internal constant OUT_HERE_SELECTOR = ImTokenGateway.outHere.selector;

    constructor(address _roles, address _zkVerifier, address _owner) Ownable(_owner) {
        require(_roles != address(0), BatchSubmitter_AddressNotValid());
        require(_zkVerifier != address(0), BatchSubmitter_AddressNotValid());
        rolesOperator = IRoles(_roles);
        verifier = IZkVerifier(_zkVerifier);
    }

    // ----------- OWNER ------------
    /**
     * @notice Updates IZkVerifier address
     * @param _zkVerifier the verifier address
     */
    function updateZkVerifier(address _zkVerifier) external onlyOwner {
        require(_zkVerifier != address(0), BatchSubmitter_AddressNotValid());
        emit ZkVerifierUpdated(address(verifier), _zkVerifier);
        verifier = IZkVerifier(_zkVerifier);
    }

    // ----------- PUBLIC ------------
    /**
     * @notice Execute multiple operations in a single transaction
     */
    function batchProcess(BatchProcessMsg calldata data) external {
        if (!rolesOperator.isAllowedFor(msg.sender, rolesOperator.PROOF_FORWARDER())) {
            revert BatchSubmitter_CallerNotAllowed();
        }

        _verifyProof(data.journalData, data.seal);

        bytes[] memory journals = abi.decode(data.journalData, (bytes[]));

        uint256 length = data.initHashes.length;

        for (uint256 i = 0; i < length;) {
            bytes[] memory singleJournal = new bytes[](1);
            singleJournal[0] = journals[data.startIndex + i];

            uint256[] memory singleAmount = new uint256[](1);
            singleAmount[0] = data.amounts[i];

            bytes4 selector = data.selectors[i];
            bytes memory encodedJournal = abi.encode(singleJournal);
            if (selector == MINT_SELECTOR) {
                uint256[] memory singleMinAmounts = new uint256[](1);
                singleMinAmounts[0] = data.minAmountsOut[i];
                try ImErc20Host(data.mTokens[i]).mintExternal(
                    encodedJournal, "", singleAmount, singleMinAmounts, data.receivers[i]
                ) {
                    emit BatchProcessSuccess(
                        data.initHashes[i],
                        data.receivers[i],
                        data.mTokens[i],
                        data.amounts[i],
                        data.minAmountsOut[i],
                        selector
                    );
                } catch (bytes memory reason) {
                    emit BatchProcessFailed(
                        data.initHashes[i],
                        data.receivers[i],
                        data.mTokens[i],
                        data.amounts[i],
                        data.minAmountsOut[i],
                        selector,
                        reason
                    );
                }
            } else if (selector == REPAY_SELECTOR) {
                try ImErc20Host(data.mTokens[i]).repayExternal(encodedJournal, "", singleAmount, data.receivers[i]) {
                    emit BatchProcessSuccess(
                        data.initHashes[i],
                        data.receivers[i],
                        data.mTokens[i],
                        data.amounts[i],
                        data.minAmountsOut[i],
                        selector
                    );
                } catch (bytes memory reason) {
                    emit BatchProcessFailed(
                        data.initHashes[i],
                        data.receivers[i],
                        data.mTokens[i],
                        data.amounts[i],
                        data.minAmountsOut[i],
                        selector,
                        reason
                    );
                }
            } else if (selector == OUT_HERE_SELECTOR) {
                try ImTokenGateway(data.mTokens[i]).outHere(encodedJournal, "", singleAmount, data.receivers[i]) {
                    emit BatchProcessSuccess(
                        data.initHashes[i],
                        data.receivers[i],
                        data.mTokens[i],
                        data.amounts[i],
                        data.minAmountsOut[i],
                        selector
                    );
                } catch (bytes memory reason) {
                    emit BatchProcessFailed(
                        data.initHashes[i],
                        data.receivers[i],
                        data.mTokens[i],
                        data.amounts[i],
                        data.minAmountsOut[i],
                        selector,
                        reason
                    );
                }
            } else {
                revert BatchSubmitter_InvalidSelector();
            }

            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Verifies the proof using ZkVerifier
     * @param journalData The journal data to verify
     * @param seal The seal data for verification
     */
    function _verifyProof(bytes calldata journalData, bytes calldata seal) private view {
        if (journalData.length == 0) {
            revert BatchSubmitter_JournalNotValid();
        }

        verifier.verifyInput(journalData, seal);
    }
}
