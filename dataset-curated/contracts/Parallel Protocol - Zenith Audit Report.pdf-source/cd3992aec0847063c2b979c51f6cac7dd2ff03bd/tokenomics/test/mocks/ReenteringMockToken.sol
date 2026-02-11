// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.25;

import { ERC20Mock } from "./ERC20Mock.sol";

contract ReenteringMockToken is ERC20Mock {
    address public reenterTarget;
    bytes public reenterData;

    constructor(string memory _name, string memory _symbol) ERC20Mock(_name, _symbol, 18) { }

    function setReenterTargetAndData(address _reenterTarget, bytes memory _reenterData) external {
        reenterTarget = _reenterTarget;
        reenterData = _reenterData;
    }

    function transfer(address _receiver, uint256 _amount) public override returns (bool) {
        bool success = super.transfer(_receiver, _amount);

        if (reenterTarget == address(0)) {
            return success;
        }

        (bool reenterSuccess, bytes memory data) = reenterTarget.call(reenterData);
        if (!reenterSuccess) {
            // The call failed, bubble up the error data
            if (data.length > 0) {
                // Decode the revert reason and throw it
                assembly {
                    let data_size := mload(data)
                    revert(add(32, data), data_size)
                }
            } else {
                revert("Call failed without revert reason");
            }
        }

        return success;
    }
}
