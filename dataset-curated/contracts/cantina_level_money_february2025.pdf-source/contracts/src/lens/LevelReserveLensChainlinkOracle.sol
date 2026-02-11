// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21;

import {ILevelReserveLensChainlinkOracle} from "../interfaces/lens/ILevelReserveLensChainlinkOracle.sol";
import {ILevelReserveLens} from "../interfaces/lens/ILevelReserveLens.sol";
import {SingleAdminAccessControl} from "../auth/v5/SingleAdminAccessControl.sol";

import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

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
 * @title LevelReserveLensChainlinkOracle
 * @author Level (https://level.money)
 * @notice The LevelReserveLensChainlinkOracle contract is a thin wrapper around LevelReserveLens that implements the Chainlink AggregatorV3Interface.
 */
contract LevelReserveLensChainlinkOracle is ILevelReserveLensChainlinkOracle, SingleAdminAccessControl, Pausable {
    using Math for uint256;
    using SafeCast for uint256;

    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    ILevelReserveLens public immutable lens;

    /**
     * @param _lens The address of the LevelReserveLens contract.
     * @param _admin The address of the admin.
     * @param _pauser The address of the pauser.
     */
    constructor(address _admin, address _pauser, address _lens) {
        if (_lens == address(0) || _admin == address(0)) revert("Address cannot be zero");

        lens = ILevelReserveLens(_lens);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        if (_pauser != address(0)) {
            _grantRole(PAUSER_ROLE, _pauser);
        }
    }

    /**
     * @dev Returns the number of decimals; use Chainlink's default for USD pairs.
     * @return decimals The number of decimals.
     */
    function decimals() public pure override returns (uint8) {
        return 8;
    }

    /**
     * @dev Returns a short description of the aggregator.
     * @return description A description of the aggregator.
     */
    function description() external pure override returns (string memory) {
        return "Chainlink interface compliant oracle for Level USD";
    }

    /**
     * @dev Returns the version of the interface; hard-coded to 0.
     * @return version The version of the interface.
     */
    function version() external pure override returns (uint256) {
        return 0;
    }

    /**
     * @inheritdoc ILevelReserveLensChainlinkOracle
     */
    function setPaused(bool _paused) external onlyRole(PAUSER_ROLE) {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    /**
     * @dev Returns a default price of $1 (1e18). Intended to be used when the oracle cannot fetch the price from the lens contract, or if the contract is paused.
     */
    function defaultRoundData()
        public
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (0, int256(10 ** decimals()), block.timestamp, block.timestamp, 0);
    }

    /**
     * @dev Returns the latest round data (since this oracle does not require data to be pushed). See latestRoundData for more details.
     */
    function getRoundData(uint80 /* _roundId */ )
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return this.latestRoundData();
    }

    /**
     * @dev Returns the price of lvlUSD. This function should always return some value.
     * @dev Invariants: answer > 0, answer <= this.decimals()
     * @return roundId non-meaningful value
     * @return answer The price of lvlUSD, where 1e18 means 1 USD. Returns $1 (1e18) if the reserves are overcollateralized, if the contract is paused, or the underlying lens contract reverts. Otherwise, returns the ratio of USD reserves to lvlUSD supply.
     * @return startedAt non-meaningful value
     * @return updatedAt the timestamp of the current block
     * @return answeredInRound non-meaningful value
     */
    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        if (paused()) {
            return defaultRoundData();
        }

        (bool reservePriceSuccess, bytes memory reservePriceData) =
            address(lens).staticcall(abi.encodeWithSignature("getReservePrice()"));
        (bool reserveDecimalsSuccess, bytes memory reserveDecimalsData) =
            address(lens).staticcall(abi.encodeWithSignature("getReservePriceDecimals()"));

        if (!reservePriceSuccess || !reserveDecimalsSuccess) {
            return defaultRoundData();
        }

        // Decode the returned value
        uint256 reservePrice = abi.decode(reservePriceData, (uint256));
        uint8 reserveDecimals = abi.decode(reserveDecimalsData, (uint8));

        answer = int256(reservePrice.mulDiv(10 ** decimals(), 10 ** reserveDecimals, Math.Rounding.Ceil));
        return (0, answer, block.timestamp, block.timestamp, 0);
    }
}
