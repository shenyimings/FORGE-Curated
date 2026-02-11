// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/**
 * @title MonUSD - Tadle Rebase Stablecoin
 * @author Tadle Team (https://tadle.com)
 * @notice A rebase stablecoin using diverse solid assets as collateral
 * @dev Supports multiple stablecoins ($USDT, $USDC and more) as backing assets
 *
 * ███╗   ███╗ ██████╗ ███╗   ██╗██╗   ██╗███████╗██████╗
 * ████╗ ████║██╔═══██╗████╗  ██║██║   ██║██╔════╝██╔══██╗
 * ██╔████╔██║██║   ██║██╔██╗ ██║██║   ██║███████╗██║  ██║
 * ██║╚██╔╝██║██║   ██║██║╚██╗██║██║   ██║╚════██║██║  ██║
 * ██║ ╚═╝ ██║╚██████╔╝██║ ╚████║╚██████╔╝███████║██████╔╝
 * ╚═╝     ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚══════╝╚═════╝
 */
contract MonUSD is Ownable2Step, ERC20 {
    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Mapping of supported stablecoin addresses to their decimal places
    /// @dev Zero value indicates the stablecoin is not supported
    mapping(address => uint8) public supportedStablecoins;

    /// @notice Array containing all supported stablecoin addresses
    /// @dev Used for enumeration and batch operations
    address[] public stablecoinsList;

    /// @notice Initialization flag to prevent multiple initialization calls
    /// @dev Set to true after successful initialization
    bool private initialized;

    /// @notice Token name storage
    /// @dev Set during initialization, overrides ERC20 default
    string private _name;

    /// @notice Token symbol storage
    /// @dev Set during initialization, overrides ERC20 default
    string private _symbol;

    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new stablecoin is added to the supported list
    /// @param stablecoin Address of the added stablecoin contract
    /// @param decimals Number of decimal places for the stablecoin
    event StablecoinAdded(address indexed stablecoin, uint8 decimals);

    /// @notice Emitted when a stablecoin is removed from the supported list
    /// @param stablecoin Address of the removed stablecoin contract
    event StablecoinRemoved(address indexed stablecoin);

    /// @notice Emitted when a user deposits stablecoins and receives MonUSD
    /// @param user Address of the user making the deposit
    /// @param stablecoin Address of the deposited stablecoin
    /// @param amount Amount of stablecoin deposited (in stablecoin's decimals)
    /// @param monAmount Amount of MonUSD minted (in 18 decimals)
    event TokensDeposited(address indexed user, address indexed stablecoin, uint256 amount, uint256 monAmount);

    /// @notice Emitted when a user withdraws stablecoins by burning MonUSD
    /// @param user Address of the user making the withdrawal
    /// @param stablecoin Address of the withdrawn stablecoin
    /// @param monAmount Amount of MonUSD burned (in 18 decimals)
    /// @param stablecoinAmount Amount of stablecoin withdrawn (in stablecoin's decimals)
    event TokensWithdrawn(
        address indexed user, address indexed stablecoin, uint256 monAmount, uint256 stablecoinAmount
    );

    /// @notice Emitted when MonUSD tokens are minted by the owner
    /// @param to Address receiving the newly minted tokens
    /// @param amount Amount of MonUSD tokens minted (in 18 decimals)
    event TokensMinted(address indexed to, uint256 amount);

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Constructor that initializes the contract with empty name and symbol
    /// @dev Name and symbol are set during initialization to support proxy patterns
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() ERC20("", "") Ownable(msg.sender) {}

    /*//////////////////////////////////////////////////////////////
                           INITIALIZATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Initializes the contract with token name and symbol
     * @dev Can only be called once due to initialization guard
     * @param __name Token name for the MonUSD token
     * @param __symbol Token symbol for the MonUSD token
     * @custom:initialization Must be called after deployment for proxy contracts
     */
    function initialize(string memory __name, string memory __symbol) public {
        require(!initialized, "MonUSD: contract already initialized");
        require(bytes(__name).length > 0, "MonUSD: token name cannot be empty");
        require(bytes(__symbol).length > 0, "MonUSD: token symbol cannot be empty");

        initialized = true;
        _name = __name;
        _symbol = __symbol;
    }

    /*//////////////////////////////////////////////////////////////
                            TOKEN METADATA
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the name of the token
    /// @return The token name set during initialization
    function name() public view override returns (string memory) {
        return _name;
    }

    /// @notice Returns the symbol of the token
    /// @return The token symbol set during initialization
    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    /*//////////////////////////////////////////////////////////////
                        STABLECOIN MANAGEMENT
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Adds a new stablecoin to the list of supported collateral assets
     * @dev Validates the stablecoin contract and retrieves its decimal configuration
     * @param stablecoin Address of the ERC20 stablecoin contract to add
     * @custom:access-control Only callable by the contract owner
     * @custom:validation Checks for valid address and decimal retrieval
     */
    function addStablecoin(address stablecoin) external onlyOwner {
        require(stablecoin != address(0), "MonUSD: stablecoin address cannot be zero");
        require(supportedStablecoins[stablecoin] == 0, "MonUSD: stablecoin already supported");

        try IERC20Metadata(stablecoin).decimals() returns (uint8 decimals__) {
            supportedStablecoins[stablecoin] = decimals__;
            stablecoinsList.push(stablecoin);
            emit StablecoinAdded(stablecoin, decimals__);
        } catch {
            revert("MonUSD: failed to retrieve stablecoin decimals");
        }
    }

    /**
     * @notice Removes a stablecoin from the list of supported collateral assets
     * @dev Removes from both mapping and array, maintaining array integrity
     * @param stablecoin Address of the stablecoin contract to remove
     * @custom:access-control Only callable by the contract owner
     * @custom:array-management Maintains stablecoinsList array integrity
     */
    function removeStablecoin(address stablecoin) external onlyOwner {
        require(supportedStablecoins[stablecoin] != 0, "MonUSD: stablecoin not currently supported");

        supportedStablecoins[stablecoin] = 0;

        for (uint256 i = 0; i < stablecoinsList.length; i++) {
            if (stablecoinsList[i] == stablecoin) {
                stablecoinsList[i] = stablecoinsList[stablecoinsList.length - 1];
                stablecoinsList.pop();
                emit StablecoinRemoved(stablecoin);
                break;
            }
        }
    }

    /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Deposits stablecoins and mints equivalent MonUSD tokens
     * @dev Converts stablecoin amount to 18 decimals and mints MonUSD 1:1
     * @param stablecoin Address of the supported stablecoin to deposit
     * @param amount Amount of stablecoin to deposit (in stablecoin's native decimals)
     * @custom:conversion Automatically handles decimal conversion to 18 decimals
     * @custom:validation Requires supported stablecoin and sufficient allowance
     */
    function deposit(address stablecoin, uint256 amount) external {
        uint8 stablecoinDecimals = supportedStablecoins[stablecoin];
        require(stablecoinDecimals != 0, "MonUSD: stablecoin not supported for deposits");
        require(amount > 0, "MonUSD: deposit amount must be greater than zero");

        IERC20 token = IERC20(stablecoin);
        require(token.transferFrom(msg.sender, address(this), amount), "Transfer failed");

        uint256 monAmount = _convertToMonAmount(amount, stablecoinDecimals);
        _mint(msg.sender, monAmount);

        emit TokensDeposited(msg.sender, stablecoin, amount, monAmount);
    }

    /**
     * @notice Withdraws stablecoins by burning MonUSD tokens
     * @dev Burns MonUSD and transfers equivalent stablecoin amount to user
     * @param stablecoin Address of the supported stablecoin to withdraw
     * @param monAmount Amount of MonUSD to burn (in 18 decimals)
     * @custom:conversion Automatically handles decimal conversion from 18 decimals
     * @custom:validation Requires supported stablecoin and sufficient MonUSD balance
     */
    function withdraw(address stablecoin, uint256 monAmount) external {
        uint8 stablecoinDecimals = supportedStablecoins[stablecoin];
        require(stablecoinDecimals != 0, "MonUSD: stablecoin not supported for withdrawals");
        require(monAmount > 0, "MonUSD: withdrawal amount must be greater than zero");
        require(balanceOf(msg.sender) >= monAmount, "MonUSD: insufficient MonUSD balance");

        uint256 stablecoinAmount = _convertFromMonAmount(monAmount, stablecoinDecimals);

        IERC20 token = IERC20(stablecoin);
        require(
            token.balanceOf(address(this)) >= stablecoinAmount,
            "MonUSD: insufficient stablecoin reserves for withdrawal"
        );

        _burn(msg.sender, monAmount);
        require(token.transfer(msg.sender, stablecoinAmount), "Transfer failed");

        emit TokensWithdrawn(msg.sender, stablecoin, monAmount, stablecoinAmount);
    }

    /**
     * @notice Mints MonUSD tokens to a specified address
     * @dev Only callable by the contract owner for administrative purposes
     * @param to Address to receive the newly minted tokens
     * @param amount Amount of MonUSD tokens to mint (in 18 decimals)
     * @custom:access-control Only callable by the contract owner
     * @custom:emission Used for administrative token distribution
     */
    function mint(address to, uint256 amount) external onlyOwner {
        require(to != address(0), "MonUSD: mint recipient cannot be zero address");
        require(amount > 0, "MonUSD: mint amount must be greater than zero");
        _mint(to, amount);
        emit TokensMinted(to, amount);
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Converts stablecoin amount to MonUSD amount (18 decimals)
     * @dev Scales up or down based on stablecoin's decimal places
     * @param amount Amount in stablecoin's native decimals
     * @param decimals_ Number of decimal places for the stablecoin
     * @return Equivalent amount normalized to 18 decimals for MonUSD
     * @custom:conversion Handles both scaling up and scaling down
     */
    function _convertToMonAmount(uint256 amount, uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ > 18) {
            return amount / (10 ** (decimals_ - 18));
        } else if (decimals_ < 18) {
            return amount * (10 ** (18 - decimals_));
        }
        return amount;
    }

    /**
     * @notice Converts MonUSD amount to stablecoin amount
     * @dev Scales down or up from 18 decimals to stablecoin's decimal places
     * @param monAmount Amount in MonUSD (18 decimals)
     * @param decimals_ Number of decimal places for the target stablecoin
     * @return Equivalent amount normalized to stablecoin's native decimals
     * @custom:conversion Handles both scaling up and scaling down
     */
    function _convertFromMonAmount(uint256 monAmount, uint8 decimals_) internal pure returns (uint256) {
        if (decimals_ > 18) {
            return monAmount * (10 ** (decimals_ - 18));
        } else if (decimals_ < 18) {
            return monAmount / (10 ** (18 - decimals_));
        }
        return monAmount;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Returns the complete list of supported stablecoin addresses
     * @dev Provides enumeration of all stablecoins that can be used for deposits/withdrawals
     * @return Array of supported stablecoin contract addresses
     * @custom:enumeration Used for frontend integration and batch operations
     */
    function getSupportedStablecoins() external view returns (address[] memory) {
        return stablecoinsList;
    }
}
