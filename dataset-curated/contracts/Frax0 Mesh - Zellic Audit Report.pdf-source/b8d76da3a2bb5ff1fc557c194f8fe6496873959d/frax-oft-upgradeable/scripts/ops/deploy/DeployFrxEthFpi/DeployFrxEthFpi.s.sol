// SPDX-License-Identifier: ISC
pragma solidity ^0.8.19;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";

/*
Intro:
frxETH and FPI legacy OFTs were deployed after Mode and Sei were connected to 
sfrxETH, sFRAX, FRAX, and FXS.

Goal:
Deploy frxETH and FPI upgradeable OFTs to Mode and Sei 
*/

contract DeployFrxEThFpis is DeployFraxOFTProtocol {
    using OptionsBuilder for bytes;
    using stdJson for string;
    using Strings for uint256;

    function version() public virtual override pure returns (uint256, uint256, uint256) {
        return (1, 0, 2);
    }

    /// @dev override to alter file save location
    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/DeployFrxEthFpi/txs/");
        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");

        return string.concat(root, name);
    }


    function setUp() public override {
        super.setUp();

        // clear out legacyOfts
        delete legacyOfts;
        delete proxyOfts;

        // set legacy OFTs with frxETH and FPI
        legacyOfts.push(0xF010a7c8877043681D59AD125EbF575633505942);
        legacyOfts.push(0xE41228a455700cAF09E551805A8aB37caa39D08c);
    }

    /// @dev no need for post-deploy checks
    function deploySource() public virtual override {
        preDeployChecks();
        deployFraxOFTUpgradeablesAndProxies();
        // postDeployChecks();
    }

    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(oftDeployerPK) public virtual override {
        // Implementation and proxy admin have already been deployed
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;

        // Deploy frxETH
        (, address proxy) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Ether",
            _symbol: "frxETH"
        });
        require(proxy == 0x43eDD7f3831b08FE70B7555ddD373C8bF65a9050, "frxETH address wrong");

        // deploy FPI
        (, proxy) = deployFraxOFTUpgradeableAndProxy({
            _name: "Frax Price Index",
            _symbol: "FPI"
        });
        require(proxy == 0xEed9DE5E41b53D1C8fAB8AAB4b0e446F828c1483, "FPI address wrong");
    }

    /// @dev override as the proxyAdmin ownership is already properly set
    function setPriviledgedRoles() public virtual override {
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(broadcastConfig.delegate);
            Ownable(proxyOft).transferOwnership(broadcastConfig.delegate);
        }

        /// @dev transfer ownership of ProxyAdmin
        // Ownable(proxyAdmin).transferOwnership(broadcastConfig.delegate);
    }

}
