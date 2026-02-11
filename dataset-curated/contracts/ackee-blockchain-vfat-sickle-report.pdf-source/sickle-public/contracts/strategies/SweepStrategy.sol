// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { NftTransferLib } from "contracts/libraries/NftTransferLib.sol";
import { TransferLib } from "contracts/libraries/TransferLib.sol";
import {
    Sickle,
    SickleFactory,
    StrategyModule,
    ConnectorRegistry
} from "contracts/modules/StrategyModule.sol";
import { IERC721 } from
    "lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import { IERC1155 } from
    "lib/openzeppelin-contracts/contracts/interfaces/IERC1155.sol";

contract SweepStrategy is StrategyModule {
    error InvalidInputLength(); //0x7db491eb

    NftTransferLib public immutable nftTransferLib;
    TransferLib public immutable transferLib;

    constructor(
        SickleFactory factory,
        NftTransferLib nftTransferLib_,
        TransferLib transferLib_
    ) StrategyModule(factory, ConnectorRegistry(address(0))) {
        nftTransferLib = nftTransferLib_;
        transferLib = transferLib_;
    }

    function sweepTokens(address[] memory tokens) public {
        Sickle sickle = getSickle(msg.sender);

        address[] memory targets = new address[](1);
        bytes[] memory data = new bytes[](1);

        targets[0] = address(transferLib);
        data[0] = abi.encodeCall(TransferLib.transferTokensToUser, (tokens));

        sickle.multicall(targets, data);
    }

    function sweepErc721(
        IERC721[] memory tokens,
        uint256[] memory tokenIds
    ) public {
        Sickle sickle = getSickle(msg.sender);

        if (tokens.length != tokenIds.length) {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](tokens.length);
        bytes[] memory data = new bytes[](tokens.length);

        uint256 length = tokens.length;
        for (uint256 i; i < length;) {
            targets[i] = address(nftTransferLib);
            data[i] = abi.encodeCall(
                NftTransferLib.transferErc721ToUser, (tokens[i], tokenIds[i])
            );

            unchecked {
                i++;
            }
        }

        sickle.multicall(targets, data);
    }

    function sweepErc1155(
        IERC1155[] memory tokens,
        uint256[] memory tokenIds,
        uint256[] memory amounts
    ) public {
        Sickle sickle = getSickle(msg.sender);

        if (tokens.length != tokenIds.length || tokens.length != amounts.length)
        {
            revert InvalidInputLength();
        }

        address[] memory targets = new address[](tokens.length);
        bytes[] memory data = new bytes[](tokens.length);

        uint256 length = tokens.length;
        for (uint256 i; i < length;) {
            targets[i] = address(nftTransferLib);
            data[i] = abi.encodeCall(
                NftTransferLib.transferErc1155ToUser,
                (tokens[i], tokenIds[i], amounts[i])
            );

            unchecked {
                i++;
            }
        }

        sickle.multicall(targets, data);
    }
}
