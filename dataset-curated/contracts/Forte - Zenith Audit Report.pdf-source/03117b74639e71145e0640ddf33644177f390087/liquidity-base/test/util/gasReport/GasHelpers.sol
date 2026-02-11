// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.24;

import "lib/forge-std/src/Test.sol";

contract GasHelpers is Test {
    string private checkpointLabel;
    uint256 private checkpointGasLeft = 1; // Start the slot warm.

    uint256 gasUsed = 0;
    string path = "";

    event Gas_Log(string _label, uint256 _gasDelta);

    modifier reportGas(string memory label) {
        startMeasuringGas(label);
        _;
        stopMeasuringGas();
    }

    function startMeasuringGas(string memory label) internal virtual {
        checkpointLabel = label;

        checkpointGasLeft = gasleft();
    }

    function stopMeasuringGas() internal virtual returns (uint256) {
        uint256 checkpointGasLeft2 = gasleft();

        // Subtract 100 to account for the warm SLOAD in startMeasuringGas.
        uint256 gasDelta = checkpointGasLeft - checkpointGasLeft2 - 100;

        emit Gas_Log(string(abi.encodePacked(checkpointLabel, " Gas")), gasDelta);
        return gasDelta;
    }

    function _primer() internal {
        startMeasuringGas("Gas Report Primer");
        stopMeasuringGas();
    }

    function _writeJson(string memory obj) internal {
        vm.writeJson(vm.toString(gasUsed), path, obj);
    }

    function _resetGasUsed() internal {
        gasUsed = 0;
    }
}
