// SPDX-License-Identifier: BUSL-1.1
pragma solidity >=0.8.21;

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
 * @title ILevelReserveLens
 * @author Level (https://level.money)
 * @notice Interface for querying the reserves backing lvlUSD per underlying collateral token address.
 */
interface ILevelReserveLens {
    /**
     * @notice Returns the reserves of the given token, including any lending derivatives. For example, if the token is USDC, we will return the balance of all ReserveManagers' USDC and wrapped Aave tokens. Also includes reserves in LevelMinting.
     * @dev Note: waUSDC/T and USDC/T are used interchangeably because the wrapped Aave tokens are withdrawable 1:1 for the underlying token
     * @dev Note: the reserves returned may include deposits from non-Level participants, which may cause the total reserves to be higher than expected. This should not affect the lvlUSD/USD price (which is capped at 1 if the reserves are overcollateralized).
     * @param collateral The address of the collateral token
     * @return The reserves of the given token, in lvlUSD's decimals (18)
     */
    function getReserves(address collateral) external view returns (uint256);

    /**
     * @notice Returns the USD-value reserves of the given token. See getReserves for more details.
     * @param collateral The address of the collateral token
     * @return usdReserves The USD-value reserves of the given token, in lvlUSD's decimals (18)
     */
    function getReserveValue(address collateral) external view returns (uint256 usdReserves);

    /**
     * @notice Returns the total dollar value of reserves backing lvlUSD, including all collateral tokens.
     * @return usdReserves The total dollar value of reserves backing lvlUSD, in lvlUSD's decimals
     */
    function getReserveValue() external view returns (uint256 usdReserves);

    /**
     * @notice Returns the reserve price of lvlUSD. If the reserves are overcollateralized, return $1 (1e18). Otherwise, return the ratio of USD reserves to lvlUSD supply.
     * @return reservePrice The reserve price of lvlUSD, with lvlUSD's decimals (18).
     */
    function getReservePrice() external view returns (uint256);

    /**
     * @notice Returns the number of decimals used for the reserve price.
     * @return reservePriceDecimals The number of decimals used for the reserve price
     */
    function getReservePriceDecimals() external view returns (uint8);

    /**
     * @notice Returns the price of minting lvlUSD using the same logic as LevelMinting
     * @param collateral The address of the collateral token
     * @return mintPrice The price of lvlUSD for 1 unit of the collateral token, with lvlUSD's decimals (18)
     */
    function getMintPrice(IERC20Metadata collateral) external view returns (uint256);

    /**
     * @notice Returns the price of redeeming lvlUSD using the same logic as LevelMinting
     * @param collateral The address of the collateral token
     * @return redeemPrice The price of collateral for 1 unit of lvlUSD, with the same decimals as the collateral token
     */
    function getRedeemPrice(IERC20Metadata collateral) external view returns (uint256);
}
