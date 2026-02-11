// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21;

import {AggregatorV3Interface} from "../AggregatorV3Interface.sol";
import {ILevelReserveLens} from "./ILevelReserveLens.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

/**
 *                                     .-==+=======+:
 *                                      :---=-::-==:
 *                                      .-:-==-:-==:
 *                    .:::--::::::.     .--:-=--:--.       .:--:::--..
 *                   .=++=++:::::..     .:::---::--.    ....::...:::.
 *                    :::-::..::..      .::::-:::::.     ...::...:::.
 *                    ...::..::::..     .::::--::-:.    ....::...:::..
 *                    ............      ....:::..::.    ------:......
 *    ...........     ........:....     .....::..:..    ======-......      ...........
 *    :------:.:...   ...:+***++*#+     .------:---.    ...::::.:::...   .....:-----::.
 *    .::::::::-:..   .::--..:-::..    .-=+===++=-==:   ...:::..:--:..   .:==+=++++++*:
 *
 * @title ILevelReserveLensChainlinkOracle
 * @author Level (https://level.money)
 * @notice Interface for a Chainlink-compatible oracle wrapper around LevelReserveLens that provides lvlUSD price data
 */
interface ILevelReserveLensChainlinkOracle is AggregatorV3Interface {
    /**
     * @notice Sets the paused state of the contract
     * @param _paused True to pause, false to unpause
     */
    function setPaused(bool _paused) external;

    /**
     * @notice Returns a default price of $1
     * @dev Intended to be used when the oracle cannot fetch the price from the lens contract, or if the contract is paused
     * @return roundId non-meaningful value
     * @return answer The default price (1 USD)
     * @return startedAt The current block timestamp
     * @return updatedAt The current block timestamp
     * @return answeredInRound non-meaningful value
     */
    function defaultRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
