// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundaiton, 2025.
pragma solidity ^0.8.23;

import {LibString} from "@solady/utils/LibString.sol";

import {ICreditManagerV3} from "@gearbox-protocol/core-v3/contracts/interfaces/ICreditManagerV3.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {OptionalCall} from "@gearbox-protocol/core-v3/contracts/libraries/OptionalCall.sol";

import {IAddressProvider} from "@gearbox-protocol/permissionless/contracts/interfaces/IAddressProvider.sol";
import {IContractsRegister} from "@gearbox-protocol/permissionless/contracts/interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfigurator.sol";
import {IMarketConfiguratorFactory} from
    "@gearbox-protocol/permissionless/contracts/interfaces/IMarketConfiguratorFactory.sol";
import {
    AP_MARKET_CONFIGURATOR_FACTORY,
    NO_VERSION_CONTROL
} from "@gearbox-protocol/permissionless/contracts/libraries/ContractLiterals.sol";

import {CreditManagerFilter, MarketFilter} from "../types/Filters.sol";

abstract contract BaseCompressor {
    using LibString for bytes32;
    using LibString for string;

    struct Pool {
        address addr;
        address configurator;
    }

    address public immutable addressProvider;

    constructor(address addressProvider_) {
        addressProvider = addressProvider_;
    }

    function _getAddress(bytes32 key) internal view returns (address) {
        return IAddressProvider(addressProvider).getAddressOrRevert(key, NO_VERSION_CONTROL);
    }

    function _getLatestAddress(bytes32 key, uint256 minorVersion) internal view returns (address) {
        uint256 latestPatch = IAddressProvider(addressProvider).getLatestPatchVersion(key, minorVersion);
        return IAddressProvider(addressProvider).getAddressOrRevert(key, latestPatch);
    }

    function _appendPostfix(bytes32 contractType, address token) internal view returns (bytes32) {
        (bool success,) = OptionalCall.staticCallOptionalSafe({
            target: token,
            data: abi.encodeWithSignature("basisPointsRate()"),
            gasAllowance: 10000
        });
        if (success) return string.concat(contractType.fromSmallString(), "::USDT").toSmallString();
        return contractType;
    }

    function _getPools(MarketFilter memory filter) internal view returns (Pool[] memory pools) {
        address[] memory configurators = filter.configurators.length != 0
            ? filter.configurators
            : IMarketConfiguratorFactory(_getAddress(AP_MARKET_CONFIGURATOR_FACTORY)).getMarketConfigurators();

        // rough estimate of maximum number of pools
        uint256 max;
        for (uint256 i; i < configurators.length; ++i) {
            address contractsRegister = IMarketConfigurator(configurators[i]).contractsRegister();
            max += IContractsRegister(contractsRegister).getPools().length;
        }

        // allocate the array with maximum potentially needed size (total number of pools can be assumed to be
        // relatively small and the function is only called once, so memory expansion cost is not an issue)
        pools = new Pool[](max);
        uint256 num;

        for (uint256 i; i < configurators.length; ++i) {
            address contractsRegister = IMarketConfigurator(configurators[i]).contractsRegister();
            address[] memory poolsMC = IContractsRegister(contractsRegister).getPools();
            for (uint256 j; j < poolsMC.length; ++j) {
                address pool = poolsMC[j];
                if (filter.pools.length != 0 && !_contains(filter.pools, pool)) continue;
                if (filter.underlying != address(0) && IPoolV3(pool).asset() != filter.underlying) continue;
                pools[num++] = Pool({addr: pool, configurator: configurators[i]});
            }
        }

        // trim the array to its actual size
        assembly {
            mstore(pools, num)
        }
    }

    function _getCreditManagers(CreditManagerFilter memory filter)
        internal
        view
        returns (address[] memory creditManagers)
    {
        Pool[] memory pools = _getPools(MarketFilter(filter.configurators, filter.pools, filter.underlying));

        // rough estimate of maximum number of credit managers
        uint256 max;
        for (uint256 i; i < pools.length; ++i) {
            address cr = IMarketConfigurator(pools[i].configurator).contractsRegister();
            max += IContractsRegister(cr).getCreditManagers(pools[i].addr).length;
        }

        // allocate the array with maximum potentially needed size (total number of credit managers can be assumed
        // to be relatively small and the function is only called once, so memory expansion cost is not an issue)
        creditManagers = new address[](max);
        uint256 num;
        for (uint256 i; i < pools.length; ++i) {
            address cr = IMarketConfigurator(pools[i].configurator).contractsRegister();
            address[] memory managers = IContractsRegister(cr).getCreditManagers(pools[i].addr);
            for (uint256 j; j < managers.length; ++j) {
                if (filter.creditManagers.length != 0 && !_contains(filter.creditManagers, managers[j])) continue;
                creditManagers[num++] = managers[j];
            }
        }
        // trim the array to its actual size
        assembly {
            mstore(creditManagers, num)
        }
    }

    function _contains(address[] memory array, address element) internal pure returns (bool) {
        uint256 len = array.length;
        for (uint256 i; i < len; ++i) {
            if (array[i] == element) return true;
        }
        return false;
    }

    function _getTokens(address pool) internal view returns (address[] memory tokens) {
        address quotaKeeper = IPoolV3(pool).poolQuotaKeeper();
        address[] memory quotedTokens = IPoolQuotaKeeperV3(quotaKeeper).quotedTokens();
        uint256 numTokens = quotedTokens.length;
        tokens = new address[](numTokens + 1);
        tokens[0] = IPoolV3(pool).asset();
        for (uint256 i; i < numTokens; ++i) {
            tokens[i + 1] = quotedTokens[i];
        }
    }

    function _getPriceOracle(address pool, address configurator) internal view returns (address) {
        address contractsRegister = IMarketConfigurator(configurator).contractsRegister();
        return IContractsRegister(contractsRegister).getPriceOracle(pool);
    }

    function _getLossPolicy(address pool, address configurator) internal view returns (address) {
        address contractsRegister = IMarketConfigurator(configurator).contractsRegister();
        return IContractsRegister(contractsRegister).getLossPolicy(pool);
    }
}
