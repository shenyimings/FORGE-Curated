// SPDX-License-Identifier: MIT
pragma solidity 0.8.27;

import {Test} from "forge-std/Test.sol";
import {FtsoV2PriceStore} from "../../../contracts/ftso/implementation/FtsoV2PriceStore.sol";
import {FtsoV2PriceStoreProxy} from "../../../contracts/ftso/implementation/FtsoV2PriceStoreProxy.sol";
import {IGovernanceSettings} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceSettings.sol";
import {FtsoV2PriceStoreHandler} from "./FtsoV2PriceStoreHandler.t.sol";

// solhint-disable func-name-mixedcase
contract FtsoV2PriceStoreInvariantTest is Test {

    FtsoV2PriceStore private ftsoV2PriceStoreImpl;
    FtsoV2PriceStoreProxy private ftsoV2PriceStoreProxy;
    FtsoV2PriceStore private ftsoV2PriceStore;
    FtsoV2PriceStoreHandler private handler;

    address private relayMock;

    address private governance;
    address private addressUpdater;

    bytes32[] private contractNameHashes;
    address[] private contractAddresses;

    uint64 private firstVotingRoundStartTs;
    uint8 private votingEpochDurationSeconds;
    uint8 private ftsoProtocolId;

    bytes32[] private leaves = new bytes21[](4);

    mapping(string => uint256) private previousTimestamps;
    mapping(string => uint256) private previousTrustedTimestamps;

    function setUp() public {
        relayMock = makeAddr("relayMock");
        governance = makeAddr("governance");
        addressUpdater = makeAddr("addressUpdater");

        firstVotingRoundStartTs = 12345;
        votingEpochDurationSeconds = 90;
        ftsoProtocolId = 30;
        vm.warp(firstVotingRoundStartTs + votingEpochDurationSeconds + 1);

        ftsoV2PriceStoreImpl = new FtsoV2PriceStore();
        ftsoV2PriceStoreProxy = new FtsoV2PriceStoreProxy(
            address(ftsoV2PriceStoreImpl),
            IGovernanceSettings(makeAddr("governanceSettings")),
            governance,
            addressUpdater,
            firstVotingRoundStartTs,
            votingEpochDurationSeconds,
            ftsoProtocolId
        );
        ftsoV2PriceStore = FtsoV2PriceStore(address(ftsoV2PriceStoreProxy));

        contractNameHashes = new bytes32[](2);
        contractAddresses = new address[](2);
        contractNameHashes[0] = keccak256(abi.encode("Relay"));
        contractAddresses[0] = address(relayMock);
        contractNameHashes[1] = keccak256(abi.encode("AddressUpdater"));
        contractAddresses[1] = addressUpdater;
        vm.prank(addressUpdater);
        ftsoV2PriceStore.updateContractAddresses(contractNameHashes, contractAddresses);

        handler = new FtsoV2PriceStoreHandler(
            ftsoV2PriceStore,
            governance,
            relayMock,
            firstVotingRoundStartTs,
            votingEpochDurationSeconds,
            ftsoProtocolId
        );

        address[] memory trustedProviders = new address[](1);
        trustedProviders[0] = address(handler);
        vm.prank(governance);
        ftsoV2PriceStore.setTrustedProviders(trustedProviders, 1);

        targetContract(address(handler));
        bytes4 [] memory selectors = new bytes4[](2);
        selectors[0] = handler.publishPrices.selector;
        selectors[1] = handler.submitTrustedPrices.selector;

        targetSelector(
            FuzzSelector({
                addr: address(handler),
                selectors: selectors
            })
        );
    }

    function invariant_priceStore() public {
        string[] memory symbols = ftsoV2PriceStore.getSymbols();
        for (uint256 i = 0; i < symbols.length; i++) {
            string memory symbol = symbols[i];
            (uint256 price, uint256 timestamp, uint256 decimals) = ftsoV2PriceStore.getPrice(symbol);
            (uint256 trustedPrice, uint256 trustedTimestamp, uint256 trustedDecimals) =
                ftsoV2PriceStore.getPriceFromTrustedProviders(symbol);

            // Check regular prices
            if (timestamp > 0) {
                assertGe(price, 0);
                assertGe(decimals, 0);
                assertLe(decimals, 18);

                // Check that timestamps are not decreasing (monotonicity)
                uint256 prevTimestamp = previousTimestamps[symbol];
                assertGe(timestamp, prevTimestamp, "Timestamp decreased for symbol");
                previousTimestamps[symbol] = timestamp;
            }

            //  check trusted prices
            if (trustedTimestamp > 0) {
                assertGe(trustedPrice, 0, "Negative trusted price detected");
                assertGe(trustedDecimals, -0, "Trusted decimals below minimum");
                assertLe(trustedDecimals, 18, "Trusted decimals above maximum");

                // Check that trusted timestamps are not decreasing
                uint256 prevTrustedTimestamp = previousTrustedTimestamps[symbol];
                assertGe(trustedTimestamp, prevTrustedTimestamp, "Trusted timestamp decreased for symbol");
                previousTrustedTimestamps[symbol] = trustedTimestamp;
            }
        }
    }
}
