// SPDX-License-Identifier: ISC
pragma solidity 0.8.25;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title This is the upgradable proxy contract that delegates Anvil protocol governance logic to the implementation,
 * providing a consistent governor address along with upgradability.
 *
 * @custom:security-contact security@af.xyz
 */
// solc-ignore-next-line missing-receive
contract AnvilGovernorDelegator is ERC1967Proxy {
    /***************
     * ERROR TYPES *
     ***************/
    error Unauthorized();

    modifier onlyAdmin() {
        if (msg.sender != ERC1967Utils.getAdmin()) revert Unauthorized();

        _;
    }

    /*********
     * VIEWS *
     *********/

    function getAdmin() external view returns (address) {
        return ERC1967Utils.getAdmin();
    }

    function getImplementation() external view returns (address) {
        return ERC1967Utils.getImplementation();
    }

    /*****************************
     * STATE-MODIFYING FUNCTIONS *
     *****************************/

    constructor(
        address _admin,
        address _implementation,
        bytes memory _delegateData
    ) ERC1967Proxy(_implementation, _delegateData) {
        ERC1967Utils.changeAdmin(_admin);
    }

    function changeAdmin(address _newAdmin) public onlyAdmin {
        ERC1967Utils.changeAdmin(_newAdmin);
    }

    function upgradeToAndCall(address _newImplementation, bytes memory _data) public onlyAdmin {
        ERC1967Utils.upgradeToAndCall(_newImplementation, _data);
    }
}
