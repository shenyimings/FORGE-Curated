// SPDX-License-Identifier: BUSL-1.1
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2024.
pragma solidity ^0.8.23;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IPoolQuotaKeeperV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolQuotaKeeperV3.sol";
import {IPoolV3} from "@gearbox-protocol/core-v3/contracts/interfaces/IPoolV3.sol";
import {IMarketFactory} from "../interfaces/factories/IMarketFactory.sol";
import {IContractsRegister} from "../interfaces/IContractsRegister.sol";
import {IMarketConfigurator} from "../interfaces/IMarketConfigurator.sol";
import {Call} from "../interfaces/Types.sol";
import {AbstractFactory} from "./AbstractFactory.sol";

abstract contract AbstractMarketFactory is AbstractFactory, IMarketFactory {
    // ------------ //
    // MARKET HOOKS //
    // ------------ //

    function onCreateMarket(address, address, address, address, address, address)
        external
        virtual
        override
        returns (Call[] memory)
    {}

    function onShutdownMarket(address) external virtual override returns (Call[] memory) {}

    function onCreateCreditSuite(address) external virtual override returns (Call[] memory) {}

    function onShutdownCreditSuite(address) external virtual override returns (Call[] memory) {}

    function onUpdatePriceOracle(address, address, address) external virtual override returns (Call[] memory) {}

    function onUpdateInterestRateModel(address, address, address) external virtual override returns (Call[] memory) {}

    function onUpdateRateKeeper(address, address, address) external virtual override returns (Call[] memory) {}

    function onUpdateLossPolicy(address, address, address) external virtual override returns (Call[] memory) {}

    function onAddToken(address, address, address) external virtual override returns (Call[] memory) {}

    // --------- //
    // INTERNALS //
    // --------- //

    function _validateDefaultConstructorParams(address pool, bytes calldata constructorParams) internal view {
        (address decodedPool, address decodedAddressProvider) = abi.decode(constructorParams[:64], (address, address));
        if (decodedPool != pool || decodedAddressProvider != addressProvider) {
            revert InvalidConstructorParamsException();
        }
    }

    function _marketConfigurator(address pool) internal view returns (address) {
        return Ownable(IPoolV3(pool).acl()).owner();
    }

    function _contractsRegister(address pool) internal view returns (address) {
        return IMarketConfigurator(_marketConfigurator(pool)).contractsRegister();
    }

    function _underlying(address pool) internal view returns (address) {
        return IPoolV3(pool).asset();
    }

    function _quotaKeeper(address pool) internal view returns (address) {
        return IPoolV3(pool).poolQuotaKeeper();
    }

    function _interestRateModel(address pool) internal view returns (address) {
        return IPoolV3(pool).interestRateModel();
    }

    function _priceOracle(address pool) internal view returns (address) {
        return IContractsRegister(_contractsRegister(pool)).getPriceOracle(pool);
    }

    function _lossPolicy(address pool) internal view returns (address) {
        return IContractsRegister(_contractsRegister(pool)).getLossPolicy(pool);
    }

    function _rateKeeper(address quotaKeeper) internal view returns (address) {
        return IPoolQuotaKeeperV3(quotaKeeper).gauge();
    }

    function _quotedTokens(address quotaKeeper) internal view returns (address[] memory) {
        return IPoolQuotaKeeperV3(quotaKeeper).quotedTokens();
    }

    function _isQuotedToken(address quotaKeeper, address token) internal view returns (bool) {
        return IPoolQuotaKeeperV3(quotaKeeper).isQuotedToken(token);
    }

    function _quota(address quotaKeeper, address token) internal view returns (uint96 quota) {
        (,,, quota,,) = IPoolQuotaKeeperV3(quotaKeeper).getTokenQuotaParams(token);
    }
}
