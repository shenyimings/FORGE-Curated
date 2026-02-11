/* -*- c-basic-offset: 4 -*- */
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {OnchainCrossChainOrder, ResolvedCrossChainOrder, GaslessCrossChainOrder, Output, FillInstruction} from "./types/ERC7683.sol";
import {IOriginSettler} from "./interfaces/ERC7683/IOriginSettler.sol";
import {Intent, Reward, Route, Call, TokenAmount} from "./types/Intent.sol";
import {OnchainCrosschainOrderData, GaslessCrosschainOrderData, ONCHAIN_CROSSCHAIN_ORDER_DATA_TYPEHASH, GASLESS_CROSSCHAIN_ORDER_DATA_TYPEHASH} from "./types/EcoERC7683.sol";
import {IntentSource} from "./IntentSource.sol";
import {Semver} from "./libs/Semver.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Eco7683OriginSettler
 * @notice Entry point to Eco Protocol via EIP-7683
 * @dev functionality is somewhat limited compared to interacting with Eco Protocol directly
 */
contract Eco7683OriginSettler is IOriginSettler, Semver, EIP712 {
    using ECDSA for bytes32;
    using SafeERC20 for IERC20;

    /// @notice typehash for gasless crosschain _order
    bytes32 public GASLESS_CROSSCHAIN_ORDER_TYPEHASH =
        keccak256(
            "GaslessCrossChainOrder(address originSettler,address user,uint256 nonce,uint256 originChainId,uint32 openDeadline,uint32 fillDeadline,bytes32 orderDataType,bytes32 orderDataHash)"
        );

    /// @notice address of IntentSource contract where intents are actually published
    address public immutable INTENT_SOURCE;

    /**
     * @notice Initializes the Eco7683OriginSettler
     * @param _name the name of the contract for EIP712
     * @param _version the version of the contract for EIP712
     * @param _intentSource the address of the IntentSource contract
     */
    constructor(
        string memory _name,
        string memory _version,
        address _intentSource
    ) EIP712(_name, _version) {
        INTENT_SOURCE = _intentSource;
    }

    /**
     * @notice Opens an Eco intent directly on chain
     * @dev to be called by the user
     * @dev assumes user has erc20 funds approved for the intent, and includes any reward native token in msg.value
     * @dev transfers the reward tokens at time of open
     * @param _order the OnchainCrossChainOrder that will be opened as an eco intent
     */
    function open(
        OnchainCrossChainOrder calldata _order
    ) external payable override {
        if (_order.orderDataType != ONCHAIN_CROSSCHAIN_ORDER_DATA_TYPEHASH) {
            revert TypeSignatureMismatch();
        }

        OnchainCrosschainOrderData memory onchainCrosschainOrderData = abi
            .decode(_order.orderData, (OnchainCrosschainOrderData));

        if (onchainCrosschainOrderData.route.source != block.chainid) {
            revert OriginChainIDMismatch();
        }

        Intent memory intent = Intent(
            onchainCrosschainOrderData.route,
            Reward(
                onchainCrosschainOrderData.creator,
                onchainCrosschainOrderData.prover,
                _order.fillDeadline,
                onchainCrosschainOrderData.nativeValue,
                onchainCrosschainOrderData.rewardTokens
            )
        );

        bytes32 orderId = _openEcoIntent(intent, msg.sender);

        emit Open(orderId, resolve(_order));
    }

    /**
     * @notice Opens an Eco intent on behalf of a user
     * @notice This method is made payable in the event that the caller of this method (a solver) wants to open
     * an intent that has native token as a reward. In this case, the solver would need to send the native
     * token as part of the transaction. How the intent's creator pays the solver is not covered by this method.
     * @dev to be called by the intent's solver
     * @dev assumes user has erc20 funds approved for the intent, and includes any reward native token in msg.value
     * @dev transfers the reward tokens at time of open
     * @param _order the GaslessCrossChainOrder that will be opened as an eco intent
     * @param _signature the signature of the user authorizing the intent to be opened
     * @param _originFillerData filler data for the origin chain (vestigial, not used)
     */
    function openFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata _signature,
        bytes calldata _originFillerData
    ) external payable override {
        if (block.timestamp > _order.openDeadline) {
            revert OpenDeadlinePassed();
        }
        if (!_verifyOpenFor(_order, _signature)) {
            revert BadSignature();
        }

        if (_order.orderDataType != GASLESS_CROSSCHAIN_ORDER_DATA_TYPEHASH) {
            revert TypeSignatureMismatch();
        }

        GaslessCrosschainOrderData memory gaslessCrosschainOrderData = abi
            .decode(_order.orderData, (GaslessCrosschainOrderData));

        if (_order.originChainId != block.chainid) {
            revert OriginChainIDMismatch();
        }

        Intent memory intent = Intent(
            Route(
                bytes32(_order.nonce),
                _order.originChainId,
                gaslessCrosschainOrderData.destination,
                gaslessCrosschainOrderData.inbox,
                gaslessCrosschainOrderData.routeTokens,
                gaslessCrosschainOrderData.calls
            ),
            Reward(
                _order.user,
                gaslessCrosschainOrderData.prover,
                _order.fillDeadline,
                gaslessCrosschainOrderData.nativeValue,
                gaslessCrosschainOrderData.rewardTokens
            )
        );

        bytes32 orderId = _openEcoIntent(intent, _order.user);

        emit Open(orderId, resolveFor(_order, _originFillerData));
    }

    /**
     * @notice resolves an OnchainCrossChainOrder to a ResolvedCrossChainOrder
     * @param _order the OnchainCrossChainOrder to be resolved
     */
    function resolve(
        OnchainCrossChainOrder calldata _order
    ) public view override returns (ResolvedCrossChainOrder memory) {
        OnchainCrosschainOrderData memory onchainCrosschainOrderData = abi
            .decode(_order.orderData, (OnchainCrosschainOrderData));
        uint256 routeTokenCount = onchainCrosschainOrderData
            .route
            .tokens
            .length;
        Output[] memory maxSpent = new Output[](routeTokenCount);
        for (uint256 i = 0; i < routeTokenCount; ++i) {
            TokenAmount memory approval = onchainCrosschainOrderData
                .route
                .tokens[i];
            maxSpent[i] = Output(
                bytes32(uint256(uint160(approval.token))),
                approval.amount,
                bytes32(uint256(uint160(address(0)))), //filler is not known
                onchainCrosschainOrderData.route.destination
            );
        }
        uint256 rewardTokenCount = onchainCrosschainOrderData
            .rewardTokens
            .length;
        Output[] memory minReceived = new Output[](
            rewardTokenCount +
                (onchainCrosschainOrderData.nativeValue > 0 ? 1 : 0)
        ); //rewards are fixed

        for (uint256 i = 0; i < rewardTokenCount; ++i) {
            minReceived[i] = Output(
                bytes32(
                    uint256(
                        uint160(
                            onchainCrosschainOrderData.rewardTokens[i].token
                        )
                    )
                ),
                onchainCrosschainOrderData.rewardTokens[i].amount,
                bytes32(uint256(uint160(address(0)))), //filler is not known
                onchainCrosschainOrderData.route.destination
            );
        }
        if (onchainCrosschainOrderData.nativeValue > 0) {
            minReceived[rewardTokenCount] = Output(
                bytes32(uint256(uint160(address(0)))),
                onchainCrosschainOrderData.nativeValue,
                bytes32(uint256(uint160(address(0)))),
                onchainCrosschainOrderData.route.destination
            );
        }

        Intent memory intent = Intent(
            onchainCrosschainOrderData.route,
            Reward(
                onchainCrosschainOrderData.creator,
                onchainCrosschainOrderData.prover,
                _order.fillDeadline,
                onchainCrosschainOrderData.nativeValue,
                onchainCrosschainOrderData.rewardTokens
            )
        );

        FillInstruction[] memory fillInstructions = new FillInstruction[](1);
        fillInstructions[0] = FillInstruction(
            uint64(onchainCrosschainOrderData.route.destination),
            bytes32(uint256(uint160(onchainCrosschainOrderData.route.inbox))),
            abi.encode(intent)
        );

        (bytes32 intentHash, , ) = IntentSource(INTENT_SOURCE).getIntentHash(
            intent
        );
        return
            ResolvedCrossChainOrder(
                onchainCrosschainOrderData.creator,
                onchainCrosschainOrderData.route.source,
                _order.fillDeadline,
                _order.fillDeadline,
                intentHash,
                maxSpent,
                minReceived,
                fillInstructions
            );
    }

    /**
     * @notice resolves GaslessCrossChainOrder to a ResolvedCrossChainOrder
     * @param _order the GaslessCrossChainOrder to be resolved
     * param _originFillerData filler data for the origin chain (not used)
     */
    function resolveFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata // _originFillerData keeping it for purpose of interface
    ) public view override returns (ResolvedCrossChainOrder memory) {
        GaslessCrosschainOrderData memory gaslessCrosschainOrderData = abi
            .decode(_order.orderData, (GaslessCrosschainOrderData));
        uint256 routeTokenCount = gaslessCrosschainOrderData.routeTokens.length;
        Output[] memory maxSpent = new Output[](routeTokenCount);
        for (uint256 i = 0; i < routeTokenCount; ++i) {
            TokenAmount memory requirement = gaslessCrosschainOrderData
                .routeTokens[i];
            maxSpent[i] = Output(
                bytes32(uint256(uint160(requirement.token))),
                requirement.amount,
                bytes32(uint256(uint160(address(0)))), //filler is not known
                gaslessCrosschainOrderData.destination
            );
        }
        uint256 rewardTokenCount = gaslessCrosschainOrderData
            .rewardTokens
            .length;
        Output[] memory minReceived = new Output[](
            rewardTokenCount +
                (gaslessCrosschainOrderData.nativeValue > 0 ? 1 : 0)
        ); //rewards are fixed

        for (uint256 i = 0; i < rewardTokenCount; ++i) {
            minReceived[i] = Output(
                bytes32(
                    uint256(
                        uint160(
                            gaslessCrosschainOrderData.rewardTokens[i].token
                        )
                    )
                ),
                gaslessCrosschainOrderData.rewardTokens[i].amount,
                bytes32(uint256(uint160(address(0)))), //filler is not known
                gaslessCrosschainOrderData.destination
            );
        }
        if (gaslessCrosschainOrderData.nativeValue > 0) {
            minReceived[rewardTokenCount] = Output(
                bytes32(uint256(uint160(address(0)))),
                gaslessCrosschainOrderData.nativeValue,
                bytes32(uint256(uint160(address(0)))),
                gaslessCrosschainOrderData.destination
            );
        }

        Intent memory intent = Intent(
            Route(
                bytes32(_order.nonce),
                _order.originChainId,
                gaslessCrosschainOrderData.destination,
                gaslessCrosschainOrderData.inbox,
                gaslessCrosschainOrderData.routeTokens,
                gaslessCrosschainOrderData.calls
            ),
            Reward(
                _order.user,
                gaslessCrosschainOrderData.prover,
                _order.fillDeadline,
                gaslessCrosschainOrderData.nativeValue,
                gaslessCrosschainOrderData.rewardTokens
            )
        );

        FillInstruction[] memory fillInstructions = new FillInstruction[](1);
        fillInstructions[0] = FillInstruction(
            uint64(gaslessCrosschainOrderData.destination),
            bytes32(uint256(uint160(gaslessCrosschainOrderData.inbox))),
            abi.encode(intent)
        );

        (bytes32 intentHash, , ) = IntentSource(INTENT_SOURCE).getIntentHash(
            intent
        );
        return
            ResolvedCrossChainOrder(
                _order.user,
                _order.originChainId,
                _order.openDeadline,
                _order.fillDeadline,
                intentHash,
                maxSpent,
                minReceived,
                fillInstructions
            );
    }

    /// @notice helper method for signature verification
    function _verifyOpenFor(
        GaslessCrossChainOrder calldata _order,
        bytes calldata _signature
    ) internal view returns (bool) {
        if (_order.originSettler != address(this)) {
            return false;
        }
        bytes32 structHash = keccak256(
            abi.encode(
                GASLESS_CROSSCHAIN_ORDER_TYPEHASH,
                _order.originSettler,
                _order.user,
                _order.nonce,
                _order.originChainId,
                _order.openDeadline,
                _order.fillDeadline,
                _order.orderDataType,
                keccak256(_order.orderData)
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(_signature);

        return signer == _order.user;
    }

    /// @notice helper method that actually opens the intent
    function _openEcoIntent(
        Intent memory _intent,
        address _user
    ) internal returns (bytes32 intentHash) {
        if (!IntentSource(INTENT_SOURCE).isIntentFunded(_intent)) {
            address vault = IntentSource(INTENT_SOURCE).intentVaultAddress(
                _intent
            );

            if (_intent.reward.nativeValue > 0) {
                if (msg.value < _intent.reward.nativeValue) {
                    revert InsufficientNativeReward();
                }

                payable(vault).transfer(_intent.reward.nativeValue);
            }
            uint256 rewardsLength = _intent.reward.tokens.length;
            for (uint256 i = 0; i < rewardsLength; ++i) {
                address token = _intent.reward.tokens[i].token;
                uint256 amount = _intent.reward.tokens[i].amount;

                IERC20(token).safeTransferFrom(_user, vault, amount);
            }
        }

        payable(msg.sender).transfer(address(this).balance);

        return IntentSource(INTENT_SOURCE).publish(_intent);
    }

    /// @notice EIP712 domain separator
    function domainSeparatorV4() public view returns (bytes32) {
        return _domainSeparatorV4();
    }
}
