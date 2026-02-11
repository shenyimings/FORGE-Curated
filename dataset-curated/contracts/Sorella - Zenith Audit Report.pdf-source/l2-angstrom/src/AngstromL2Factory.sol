// SPDX-License-Identifier: BUSL-1.1
pragma solidity =0.8.26;

import {Ownable} from "solady/src/auth/Ownable.sol";
import {IPoolManager} from "./interfaces/IUniV4.sol";
import {AngstromL2} from "./AngstromL2.sol";
import {IFlashBlockNumber} from "./interfaces/IFlashBlockNumber.sol";
import {Currency} from "v4-core/src/types/Currency.sol";
import {IFactory} from "./interfaces/IFactory.sol";
import {IHookAddressMiner} from "./interfaces/IHookAddressMiner.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {SSTORE2} from "solady/src/utils/SSTORE2.sol";
import {SafeCastLib} from "solady/src/utils/SafeCastLib.sol";

contract AngstromL2Factory is Ownable, IFactory {
    using SafeCastLib for *;

    error ProtocolFeeExceedsMaximum();
    error TotalFeeAboveOneHundredPercent();
    error NotVerifiedHook();
    error FlashBlockNumberProviderAlreadySet();

    event FlashBlockNumberProviderUpdated(address newFlashBlockNumberProvider);
    event DefaultProtocolSwapFeeE6Updated(uint24 newDefaultProtocolSwapFeeE6);
    event DefaultProtocolTaxFeeE6Updated(uint24 newDefaultProtocolTaxFeeE6);
    event ProtocolSwapFeeUpdated(address indexed hook, PoolKey key, uint256 newFeeE6);
    event ProtocolTaxFeeUpdated(address indexed hook, PoolKey key, uint256 newFeeE6);
    event PoolCreated(
        address hook,
        PoolKey key,
        uint24 creatorSwapFeeE6,
        uint24 creatorTaxFeeE6,
        uint24 protocolSwapFeeE6,
        uint24 protocolTaxFeeE6
    );

    IPoolManager public immutable UNI_V4;
    IHookAddressMiner public immutable HOOK_ADDRESS_MINER;
    /// @dev Separate address to store init code of hook contract to enable factory to be within
    /// code size limit.
    address public immutable HOOK_INITCODE_STORE;
    /// @dev Default protocol swap fee to be used for new pools, as a multiple of the final resulting swap fee (`defaultProtocolSwapFeeE6 = f_pr / (1 - (1 - f_lp) * (1 - (f_cr + f_pr)))`).
    uint24 public defaultProtocolSwapFeeAsMultipleE6;
    /// @dev Protocol fee on MEV tax from ToB swap.
    uint24 public defaultProtocolTaxFeeE6;
    IFlashBlockNumber public override flashBlockNumberProvider;
    mapping(AngstromL2 hook => bool verified) public isVerifiedHook;

    uint256 internal constant FACTOR_E6 = 1e6;
    uint24 internal constant MAX_DEFAULT_PROTOCOL_FEE_MULTIPLE_E6 = 3.0e6; // 3x or 300%
    uint24 internal constant MAX_PROTOCOL_SWAP_FEE_E6 = 0.05e6;
    uint24 internal constant MAX_PROTOCOL_TAX_FEE_E6 = 0.75e6;

    // Ownable explicit constructor commented out because of weird foundry bug causing
    // "modifier-style base constructor call without arguments": https://github.com/foundry-rs/foundry/issues/11607.
    constructor(
        address owner,
        IPoolManager uniV4,
        IFlashBlockNumber initialFlashBlockNumberProvider,
        IHookAddressMiner hookAddressMiner
    ) 
    /* Ownable() */
    {
        _initializeOwner(owner);
        flashBlockNumberProvider = initialFlashBlockNumberProvider;
        UNI_V4 = uniV4;
        HOOK_ADDRESS_MINER = hookAddressMiner;
        HOOK_INITCODE_STORE = SSTORE2.write(type(AngstromL2).creationCode);
    }

    receive() external payable {}

    /// @dev Allows deployment on chains that do not support flash blocks and later upgrade.
    function setFlashBlockNumberProvider(IFlashBlockNumber newFlashBlockNumberProvider) public {
        _checkOwner();
        if (address(flashBlockNumberProvider) != address(0)) {
            revert FlashBlockNumberProviderAlreadySet();
        }
        flashBlockNumberProvider = newFlashBlockNumberProvider;
        emit FlashBlockNumberProviderUpdated(address(newFlashBlockNumberProvider));
    }

    function withdrawRevenue(Currency currency, address to, uint256 amount) public {
        _checkOwner();
        currency.transfer(to, amount);
    }

    function setDefaultProtocolSwapFeeMultiple(uint24 newDefaultProtocolSwapFeeE6) public {
        _checkOwner();
        defaultProtocolSwapFeeAsMultipleE6 = newDefaultProtocolSwapFeeE6;
        emit DefaultProtocolSwapFeeE6Updated(newDefaultProtocolSwapFeeE6);
    }

    function setDefaultProtocolTaxFee(uint24 newDefaultProtocolTaxFeeE6) public {
        _checkOwner();
        defaultProtocolTaxFeeE6 = newDefaultProtocolTaxFeeE6;
        emit DefaultProtocolTaxFeeE6Updated(newDefaultProtocolTaxFeeE6);
    }

    function setProtocolSwapFee(AngstromL2 hook, PoolKey calldata key, uint256 newFeeE6) public {
        _checkOwner();
        hook.setProtocolSwapFee(key, newFeeE6);
        emit ProtocolSwapFeeUpdated(address(hook), key, newFeeE6);
    }

    function setProtocolTaxFee(AngstromL2 hook, PoolKey calldata key, uint256 newFeeE6) public {
        _checkOwner();
        hook.setProtocolTaxFee(key, newFeeE6);
        emit ProtocolTaxFeeUpdated(address(hook), key, newFeeE6);
    }

    function createNewHookAndPoolWithMiner(
        address initialOwner,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        uint24 creatorSwapFeeE6,
        uint24 creatorTaxFeeE6
    ) public returns (AngstromL2 newAngstrom) {
        bytes32 salt = HOOK_ADDRESS_MINER.mineAngstromHookAddress(initialOwner);
        newAngstrom = deployNewHook(initialOwner, salt);
        newAngstrom.initializeNewPool(key, sqrtPriceX96, creatorSwapFeeE6, creatorTaxFeeE6);
    }

    function createNewHookAndPoolWithSalt(
        address initialOwner,
        bytes32 salt,
        PoolKey calldata key,
        uint160 sqrtPriceX96,
        uint24 creatorSwapFeeE6,
        uint24 creatorTaxFeeE6
    ) public returns (AngstromL2 newAngstrom) {
        newAngstrom = deployNewHook(initialOwner, salt);
        newAngstrom.initializeNewPool(key, sqrtPriceX96, creatorSwapFeeE6, creatorTaxFeeE6);
    }

    function deployNewHook(address owner, bytes32 salt) public returns (AngstromL2 newAngstrom) {
        bytes memory initcode = bytes.concat(
            SSTORE2.read(HOOK_INITCODE_STORE), abi.encode(UNI_V4, flashBlockNumberProvider, owner)
        );
        assembly ("memory-safe") {
            newAngstrom := create2(0, add(initcode, 0x20), mload(initcode), salt)
            // Propagate initcode error if deployment fails.
            if iszero(newAngstrom) {
                returndatacopy(mload(0x40), 0, returndatasize())
                revert(mload(0x40), returndatasize())
            }
        }
        isVerifiedHook[newAngstrom] = true;
    }

    function recordPoolCreationAndGetStartingProtocolFee(
        PoolKey calldata key,
        uint24 creatorSwapFeeE6,
        uint24 creatorTaxFeeE6
    ) public returns (uint24 protocolSwapFeeE6, uint24 protocolTaxFeeE6) {
        if (!isVerifiedHook[AngstromL2(payable(msg.sender))]) revert NotVerifiedHook();
        protocolSwapFeeE6 = getDefaultProtocolSwapFee(creatorSwapFeeE6, key.fee);
        protocolTaxFeeE6 = defaultProtocolTaxFeeE6;
        if (protocolSwapFeeE6 > MAX_PROTOCOL_SWAP_FEE_E6) {
            protocolSwapFeeE6 = MAX_PROTOCOL_SWAP_FEE_E6;
        }
        if (!(creatorSwapFeeE6 + protocolSwapFeeE6 <= FACTOR_E6)) {
            revert TotalFeeAboveOneHundredPercent();
        }
        if (!(creatorTaxFeeE6 + protocolTaxFeeE6 <= FACTOR_E6)) {
            revert TotalFeeAboveOneHundredPercent();
        }
        emit PoolCreated(
            msg.sender, key, creatorSwapFeeE6, creatorTaxFeeE6, protocolSwapFeeE6, protocolTaxFeeE6
        );
        return (protocolSwapFeeE6, protocolTaxFeeE6);
    }

    function getDefaultProtocolSwapFee(uint256 creatorSwapFeeE6, uint256 lpFeeE6)
        public
        view
        returns (uint24)
    {
        // Solve`f_pr / (1 - (1 - f_lp) * (1 - (f_cr + f_pr))) = defaultProtocolSwapFeeAsMultipleE6` for `f_pr`.
        return (
            defaultProtocolSwapFeeAsMultipleE6
                * (FACTOR_E6 * FACTOR_E6 - (FACTOR_E6 - lpFeeE6) * (FACTOR_E6 - creatorSwapFeeE6))
                / (FACTOR_E6 * FACTOR_E6 - defaultProtocolSwapFeeAsMultipleE6 * (FACTOR_E6 - lpFeeE6))
        ).toUint24();
    }

    function getDefaultNetPoolSafeSwapFee(uint256 creatorSwapFeeE6, uint256 lpFeeE6)
        public
        view
        returns (uint256)
    {
        uint256 defaultProtocolSwapFeeE6 = getDefaultProtocolSwapFee(creatorSwapFeeE6, lpFeeE6);
        return (
            FACTOR_E6 * FACTOR_E6
                - (FACTOR_E6 - lpFeeE6) * (FACTOR_E6 - creatorSwapFeeE6 - defaultProtocolSwapFeeE6)
        ) / FACTOR_E6;
    }
}
