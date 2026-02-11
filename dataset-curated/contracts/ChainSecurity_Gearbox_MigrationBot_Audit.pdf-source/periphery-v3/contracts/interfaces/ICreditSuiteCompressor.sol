// SPDX-License-Identifier: MIT
// Gearbox Protocol. Generalized leverage for DeFi protocols
// (c) Gearbox Foundation, 2025.
pragma solidity ^0.8.23;

import {IVersion} from "@gearbox-protocol/core-v3/contracts/interfaces/base/IVersion.sol";
import {BaseState} from "../types/BaseState.sol";
import {AdapterState, CreditFacadeState, CreditManagerState, CreditSuiteData} from "../types/CreditSuiteData.sol";
import {CreditManagerFilter} from "../types/Filters.sol";

interface ICreditSuiteCompressor is IVersion {
    function getCreditSuites(CreditManagerFilter memory filter) external view returns (CreditSuiteData[] memory);

    function getCreditSuiteData(address creditManager) external view returns (CreditSuiteData memory);

    function getCreditManagerState(address creditManager) external view returns (CreditManagerState memory);

    function getCreditFacadeState(address creditFacade) external view returns (CreditFacadeState memory);

    function getCreditConfiguratorState(address creditConfigurator) external view returns (BaseState memory);

    function getAccountFactoryState(address accountFactory) external view returns (BaseState memory);

    function getAdapters(address creditManager) external view returns (AdapterState[] memory);
}
