// SPDX-License-Identifier: MIT
pragma solidity >=0.7.6 <0.9;

interface IPriceChangeEmitter {

    /**
     * Emitted by FtsoV2PriceStore when the price epoch is finalized, therefore the new prices are ready to be used.
     */
    event PricesPublished(uint32 indexed votingRoundId);
}
