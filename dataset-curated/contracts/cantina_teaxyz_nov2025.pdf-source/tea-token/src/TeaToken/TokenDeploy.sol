// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

import { Tea } from "./Tea.sol";
import { MintManager } from "./MintManager.sol";
import { Create2 } from "@openzeppelin/utils/Create2.sol";
import { TimelockController } from "@openzeppelin/governance/TimelockController.sol";

/*                                      _@@                                       
 _@                @_              _@@@@@                                       
 @@   @@@@@    _@@ #@\           @@@@@@@@@@      @@@--@@@         @@@@--@@@_    
/@% @@@   @@@@@@@   @@   @@       @@@@@@@     @@@@#    @@@@     @@@@@    @@@@@  
@@                  @@   @@       @@@@@@@    @@@@@     @@@@@    @@@@~    @@@@@@ 
@@                  @@            @@@@@@@   @@@@@@@@@@@@@@@@@           @@@@@@@ 
t@@                 @@   @@       @@@@@@@   @@@@@@                  @@@@#@@@@@@ 
 @@                @@@  @@@       @@@@@@@   @@@@@@@             @@@@@+   @@@@@@ 
 t@@              j@@   @@        @@@@@@@   #@@@@@@@          _@@@@@     @@@@@@ 
  \@@            @@@    @         @@@@@@@    @@@@@@@@_        @@@@@@@   _@@@@@@ 
    @%  @@@@@@@  @                 @@@@@@@@    @@@@@@@@@@@@   +@@@@@@@@@#@@@@@@ 
         t@@@/                      t@@@@+       t@@@@@@        @@@@@@+    t@@@@
*/

contract TokenDeploy {
    error Unauthorized();
    error AlreadyDeployed();
    error AddressMismatch();

    /// @notice The address of the initial governor to be set as owner for the Tea and MintManager contracts.
    address public immutable INITIAL_GOVERNOR;

    /// @notice The address of the deployed Tea contract.
    address public tea;
    /// @notice The address of the deployed MintManager contract.
    address public mintManager;
    /// @notice The address of the deployed TimelockController contract.
    address public timelockController;

    constructor(address initialGovernor_) {
        INITIAL_GOVERNOR = initialGovernor_;
    }

    /// @notice Deploys the Tea and MintManager contracts.
    /// @param salt The salt to use for the Tea contract deployment.
    /// @param salt2 The salt to use for the MintManager contract deployment.
    function deploy(bytes32 salt, bytes32 salt2, bytes32 salt3) external {
        // One time use.
        if (msg.sender != INITIAL_GOVERNOR) revert Unauthorized();
        if (tea != address(0)) revert AlreadyDeployed();
        
        address[] memory addresses = new address[](1);

        addresses[0] = INITIAL_GOVERNOR;
        
        // Set up timelock with the Initial Governor as owner/admin
        bytes32 codeHashTLC =
            keccak256(abi.encodePacked(type(TimelockController).creationCode, abi.encode(24 hours, addresses, addresses, INITIAL_GOVERNOR)));
        address _timeLockController = Create2.computeAddress(salt3, codeHashTLC, address(this));
        timelockController = _timeLockController;

        // Deploy tea.
        tea = address(new Tea{ salt: salt }(address(this), timelockController));

        // Compute and transfer ownership.
        bytes32 codeHash =
            keccak256(abi.encodePacked(type(MintManager).creationCode, abi.encode(INITIAL_GOVERNOR, tea)));
        address _mintManager = Create2.computeAddress(salt2, codeHash, address(this));
        mintManager = _mintManager;

        Tea(payable(tea)).transferOwnership(_mintManager);
        Tea(payable(tea)).transfer(INITIAL_GOVERNOR, Tea(payable(tea)).totalSupply());

        // Record address.
        if (_mintManager != address(new MintManager{ salt: salt2 }(INITIAL_GOVERNOR, payable(tea)))) revert AddressMismatch();
    }
}
