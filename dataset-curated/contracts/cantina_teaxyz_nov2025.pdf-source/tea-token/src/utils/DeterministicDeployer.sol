// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.26;

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

/* solhint-disable no-unused-import */
import { ERC1967Proxy } from "@openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
/* solhint-enable no-unused-import */
import { Tea } from "../TeaToken/Tea.sol";

library DeterministicDeployer {
    error DeploymentFailed();

    address internal constant SAFE_SINGLETON_FACTORY = 0x914d7Fec6aaC8cd542e72Bca78B30650d45643d7;

    function _deploy(
        bytes32 salt,
        bytes memory creationCode,
        bytes memory constructorArgs
    )
        internal
        returns (address)
    {
        bytes memory payload = abi.encodePacked(salt, creationCode, constructorArgs);
        (bool success, bytes memory res) = SAFE_SINGLETON_FACTORY.call{ value: 0 }(payload);
        if (!success) {
            revert DeploymentFailed();
        }
        address decoded = abi.decode(abi.encodePacked(bytes12(0), res), (address));
        return address(uint160(decoded));
    }

    function _deployProxy(bytes32 salt, bytes memory constructorArgs) internal returns (address) {
        bytes memory bytecode = type(ERC1967Proxy).creationCode;
        address res = DeterministicDeployer._deploy(salt, bytecode, constructorArgs);
        return res;
    }
}
