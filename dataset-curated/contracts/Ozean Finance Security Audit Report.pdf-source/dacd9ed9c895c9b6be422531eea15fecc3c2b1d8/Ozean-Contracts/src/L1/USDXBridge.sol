// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import {Ownable} from "openzeppelin/contracts/access/Ownable.sol";
import {SafeERC20} from "openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "openzeppelin/contracts/security/ReentrancyGuard.sol";
import {OptimismPortal} from "optimism/src/L1/OptimismPortal.sol";
import {SystemConfig} from "optimism/src/L1/SystemConfig.sol";
import {ISemver} from "optimism/src/universal/interfaces/ISemver.sol";

/// @title  USDX Bridge
/// @notice This contract provides bridging functionality for allow-listed stablecoins to the Ozean Layer L2.
///         Users can deposit any allow-listed stablecoin and recieve USDX, the native gas token for Ozean, on
///         the L2 via the Optimism Portal contract. The owner of this contract can modify the set of
///         allow-listed stablecoins accepted, along with the deposit caps, and can also withdraw any deposited
///         ERC20 tokens.
contract USDXBridge is Ownable, ReentrancyGuard, ISemver {
    using SafeERC20 for IERC20Decimals;

    /// @notice Semantic version.
    /// @custom:semver 1.0.0
    string public constant version = "1.0.0";

    /// @notice Contract of the Optimism Portal.
    /// @custom:network-specific
    OptimismPortal public immutable portal;

    /// @notice Address of the System Config contract.
    SystemConfig public immutable config;

    /// @notice Addresses of allow-listed stablecoins.
    /// @dev    stablecoin => allowlisted
    mapping(address => bool) public allowlisted;

    /// @notice The limit to the total USDX supply that can be minted and bridged per deposted stablecoin.
    /// @dev    stablecoin => amount
    mapping(address => uint256) public depositCap;

    /// @notice The total amount of USDX bridged via this contract per deposted stablecoin.
    /// @dev    stablecoin => amount
    mapping(address => uint256) public totalBridged;

    /// @notice The gas limit passed to the Optimism portal when depositing USDX.
    uint64 public gasLimit;

    /// EVENTS ///

    /// @notice An event emitted when a bridge deposit is made by a user.
    event BridgeDeposit(address indexed _stablecoin, uint256 _amount, address indexed _to);

    /// @notice An event emitted when an ERC20 token is withdrawn from this contract.
    event WithdrawCoins(address indexed _coin, uint256 _amount, address indexed _to);

    /// @notice An event emitted when en ERC20 stablecoin is set as allowlisted or not (true if allowlisted, false if
    /// removed).
    event AllowlistSet(address indexed _coin, bool _set);

    /// @notice An event emitted when the deposit cap for an ERC20 stablecoin is modified.
    event DepositCapSet(address indexed _coin, uint256 _newDepositCap);

    /// @notice An event emitted when the gas limit is updated.
    event GasLimitSet(uint64 _newGasLimit);

    /// SETUP ///

    /// @notice The constructor contract set up.
    /// @param  _owner The address granted ownership rights to this contract.
    /// @param  _portal The Optimism Portal contract, which is directly responsible for bridging USDX.
    /// @param  _config The Optimism System Config contract, which ensures alignment on the gas token.
    /// @param  _stablecoins An array of allow-listed stablecoins that can be used to mint and bridge USDX.
    /// @param  _depositCaps The deposit caps per stablecoin for this contract, which limits the total amount bridged.
    /// @dev    Ensure that the index for each deposit cap aligns with the index of the stablecoin that is allowlisted.
    /// @dev    This function includes an unbounded for-loop. Ensure that the array of allow-listed
    ///         stablecoins is reasonable in length.
    constructor(
        address _owner,
        OptimismPortal _portal,
        SystemConfig _config,
        address[] memory _stablecoins,
        uint256[] memory _depositCaps
    ) {
        _transferOwnership(_owner);
        portal = _portal;
        config = _config;
        gasLimit = 21000;
        /// Add allow-listed stablecoins and deposit caps
        if (address(config) != address(0)) {
            uint256 length = _stablecoins.length;
            require(
                length == _depositCaps.length,
                "USDXBridge: Stablecoins array length must equal the Deposit Caps array length."
            );
            for (uint256 i; i < length; ++i) {
                allowlisted[_stablecoins[i]] = true;
                emit AllowlistSet(_stablecoins[i], true);
                depositCap[_stablecoins[i]] = _depositCaps[i];
                emit DepositCapSet(_stablecoins[i], _depositCaps[i]);
            }
        }
    }

    /// BRIDGE ///

    /// @notice This function allows users to deposit any allow-listed stablecoin to the Ozean Layer L2.
    /// @param  _stablecoin Depositing stablecoin address.
    /// @param  _amount The amount of deposit stablecoin to be swapped for USDX.
    /// @param  _to Recieving address on L2.
    function bridge(address _stablecoin, uint256 _amount, address _to) external nonReentrant {
        /// Checks
        require(allowlisted[_stablecoin], "USDXBridge: Stablecoin not accepted.");
        require(_amount > 0, "USDXBridge: May not bridge nothing.");
        uint256 bridgeAmount = _getBridgeAmount(_stablecoin, _amount);
        require(
            totalBridged[_stablecoin] + bridgeAmount < depositCap[_stablecoin],
            "USDXBridge: Bridge amount exceeds deposit cap."
        );
        /// Update state
        totalBridged[_stablecoin] += bridgeAmount;
        IERC20Decimals(_stablecoin).safeTransferFrom(msg.sender, address(this), _amount);
        /// Mint USDX
        usdx().mint(address(this), bridgeAmount);
        /// Bridge USDX
        usdx().approve(address(portal), bridgeAmount);
        portal.depositERC20Transaction({
            _to: _to,
            _mint: bridgeAmount,
            _value: bridgeAmount,
            _gasLimit: gasLimit,
            _isCreation: false,
            _data: ""
        });
        emit BridgeDeposit(_stablecoin, _amount, _to);
    }

    /// OWNER ///

    /// @notice This function allows the owner to either add or remove an allow-listed stablecoin for bridging.
    /// @param  _stablecoin The stablecoin address to add or remove.
    /// @param  _set A boolean for whether the stablecoin is allow-listed or not. True for allow-listed, false
    ///         otherwise.
    function setAllowlist(address _stablecoin, bool _set) external onlyOwner {
        allowlisted[_stablecoin] = _set;
        emit AllowlistSet(_stablecoin, _set);
    }

    /// @notice This function allows the owner to modify the deposit cap for deposited stablecoins.
    /// @param  _stablecoin The stablecoin address to modify the deposit cap.
    /// @param  _newDepositCap The new deposit cap.
    function setDepositCap(address _stablecoin, uint256 _newDepositCap) external onlyOwner {
        depositCap[_stablecoin] = _newDepositCap;
        emit DepositCapSet(_stablecoin, _newDepositCap);
    }

    /// @notice This function allows the owner to modify the gas limit for USDX deposits.
    /// @param  _newGasLimit The new gas limit to be set for transactions.
    function setGasLimit(uint64 _newGasLimit) external onlyOwner {
        gasLimit = _newGasLimit;
        emit GasLimitSet(_newGasLimit);
    }

    /// @notice This function allows the owner to withdraw any ERC20 token held by this contract.
    /// @param  _coin The address of the ERC20 token to withdraw.
    /// @param  _amount The amount of tokens to withdraw.
    function withdrawERC20(address _coin, uint256 _amount) external onlyOwner {
        IERC20Decimals(_coin).safeTransfer(msg.sender, _amount);
        emit WithdrawCoins(_coin, _amount, msg.sender);
    }

    /// VIEW ///

    /// @notice This view function returns the address, as the USDX interface, for minting and bridging.
    /// @return IUSDX Interface and address.
    function usdx() public view returns (IUSDX) {
        (address addr,) = config.gasPayingToken();
        return IUSDX(addr);
    }

    /// @notice This view function normalises deposited amounts given diverging decimals for tokens and USDX.
    /// @param  _stablecoin The address of the deposited stablecoin.
    /// @param  _amount The amount of the stablecoin deposited.
    /// @return uint256 The amount of USDX to mint given the deposited stablecoin amount.
    /// @dev    Assumes 1:1 conversion between the deposited stablecoin and USDX.
    function _getBridgeAmount(address _stablecoin, uint256 _amount) internal view returns (uint256) {
        uint8 depositDecimals = IERC20Decimals(_stablecoin).decimals();
        uint8 usdxDecimals = usdx().decimals();
        return (_amount * 10 ** usdxDecimals) / (10 ** depositDecimals);
    }
}

/// @notice An interface whihc extends the IERC20 to include a decimals view function.
/// @dev    Any allow-listed stablecoin added to the bridge must conform to this interface.
interface IERC20Decimals is IERC20 {
    function decimals() external view returns (uint8);
}

/// @notice An interface whihc extends the IERC20Decimals to include a mint function to allow for minting
///         of new USDX tokens by this bridge.
interface IUSDX is IERC20Decimals {
    function mint(address to, uint256 amount) external;
}
