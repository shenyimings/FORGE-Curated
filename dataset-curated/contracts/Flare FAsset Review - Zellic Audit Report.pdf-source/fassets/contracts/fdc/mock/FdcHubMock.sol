// SPDX-License-Identifier: MIT
// solhint-disable no-empty-blocks
pragma solidity ^0.8.27;

import {IFdcHub} from "@flarenetwork/flare-periphery-contracts/flare/IFdcHub.sol";
import {FdcRequestFeeConfigurationsMock} from "./FdcRequestFeeConfigurationsMock.sol";
import {IFdcRequestFeeConfigurations}
    from "@flarenetwork/flare-periphery-contracts/flare/IFdcRequestFeeConfigurations.sol";
import {IFdcInflationConfigurations}
    from "@flarenetwork/flare-periphery-contracts/flare/IFdcInflationConfigurations.sol";

contract FdcHubMock is IFdcHub {
    /// The FDC request fee configurations contract.
    IFdcRequestFeeConfigurations public fdcRequestFeeConfigurations;

    constructor() {
        fdcRequestFeeConfigurations = new FdcRequestFeeConfigurationsMock();
    }

     /**
     * Method to request an attestation.
     * @param _data ABI encoded attestation request
     */
    function requestAttestation(bytes calldata _data) external payable {
        emit AttestationRequest(_data, msg.value);
    }

    /**
     * The offset (in seconds) for the requests to be processed during the current voting round.
     */
    function requestsOffsetSeconds() external pure returns (uint8) {
        return 0;
    }

    /**
     * The FDC inflation configurations contract.
     */
    function fdcInflationConfigurations() external view returns(IFdcInflationConfigurations) {}
}
