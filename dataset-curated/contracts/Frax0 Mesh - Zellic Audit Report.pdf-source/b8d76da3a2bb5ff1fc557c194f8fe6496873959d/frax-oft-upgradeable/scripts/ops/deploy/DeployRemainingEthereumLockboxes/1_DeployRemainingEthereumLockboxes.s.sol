// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.22;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import "contracts/FraxOFTAdapterUpgradeable.sol";

/*
GOALS
- Deploy upgradeable (s)frxETH, FXS, FPI lockboxes to Ethereum

TODO
- Connect to Solana OFTs
*/

// forge script scripts/ops/deploy/DeployRemainingEthereumLockboxes/1_DeployRemainingEthereumLockboxes.s.sol --rpc-url https://ethereum-rpc.publicnode.com --verify --etherscan-api-key $ETHERSCAN_API_KEY --broadcast
contract DeployRemainingEthereumLockboxes is DeployFraxOFTProtocol {

    using Strings for uint256;
    using stdJson for string;

    address frxEth = 0x5E8422345238F34275888049021821E8E08CAa1f;
    address sfrxEth = 0xac3E018457B222d93114458476f3E3416Abbe38F;
    address fxs = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address fpi = 0x5Ca135cB8527d76e932f34B5145575F9d8cbE08E;
  

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/deploy/DeployRemainingEthereumLockboxes/txs/");

        string memory name = string.concat(broadcastConfig.chainid.toString(), "-");
        name = string.concat(name, simulateConfig.chainid.toString());
        name = string.concat(name, ".json");
        return string.concat(root, name);
    }

    // Configure destination OFT addresses as they may be different per chain
    // `connectedOfts` is used within DeployfraxOFTProtocol.setupDestination()
    function _populateConnectedOfts() public override {
        if (simulateConfig.chainid == 252) {
            connectedOfts[0] = fraxtalLockboxes[0];
            connectedOfts[1] = fraxtalLockboxes[1];
            connectedOfts[2] = fraxtalLockboxes[2];
            connectedOfts[3] = fraxtalLockboxes[3];
        } else {
            connectedOfts[0] = expectedProxyOfts[0];
            connectedOfts[1] = expectedProxyOfts[1];
            connectedOfts[2] = expectedProxyOfts[2];
            connectedOfts[3] = expectedProxyOfts[3];
        }
    }

    function determinePeer(
        uint256 _chainid,
        address _oft,
        address[] memory _peerOfts
    ) public override view returns (address peer) {
        if (_chainid == 252) {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: fraxtalLockboxes
            });
            require(peer != address(0), "Invalid fraxtal peer");
        } else {
            peer = getPeerFromArray({
                _oft: _oft,
                _oftArray: _peerOfts
            });
            require(peer != address(0), "Invalid proxy peer");
        }
    }

    function getPeerFromArray(address _oft, address[] memory _oftArray) public override view returns (address peer) {
        require(_oftArray.length == 4, "getPeerFromArray index mismatch");
        if (_oft == frxEthOft || _oft == proxyFrxEthOft) {
            peer = _oftArray[0];
        } else if (_oft == sfrxEthOft || _oft == proxySFrxEthOft) {
            peer = _oftArray[1];
        } else if (_oft == wfraxOft || _oft == proxyFraxOft) {
            peer = _oftArray[2];
        } else if (_oft == fpiOft || _oft == proxyFpiOft) {
            peer = _oftArray[3];
        }
    }

    function run() public override {
        // [frxEthOft, sfrxEthOft, wfraxOft, fpiOft]
        delete fraxtalLockboxes;
        fraxtalLockboxes.push(fraxtalFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalSFrxEthLockbox);
        fraxtalLockboxes.push(fraxtalFraxLockbox);
        fraxtalLockboxes.push(fraxtalFpiLockbox);

        delete expectedProxyOfts;
        expectedProxyOfts.push(proxyFrxEthOft);
        expectedProxyOfts.push(proxySFrxEthOft);
        expectedProxyOfts.push(proxyFraxOft);
        expectedProxyOfts.push(proxyFpiOft);

        connectedOfts = new address[](expectedProxyOfts.length);

        super.run();
    }

    function postDeployChecks() internal override view {
        require(proxyOfts.length == 4, "Did not deploy 4 expected OFTs");
    }

    // Skip setting up solana
    function setupNonEvms() public override pure {}

    // ProxyAdmin ownership already transferred when deploying (s)frxUSD lockboxes
    // https://etherscan.io/tx/0xe850df76dfa2edd21c6ac64e2c24a4f12935cf3116163d5a417a9568ca7f373e#eventlog
    function setPriviledgedRoles() public override {
        /// @dev transfer ownership of OFT
        for (uint256 o=0; o<proxyOfts.length; o++) {
            address proxyOft = proxyOfts[o];
            FraxOFTUpgradeable(proxyOft).setDelegate(broadcastConfig.delegate);
            Ownable(proxyOft).transferOwnership(broadcastConfig.delegate);
        }

        // Ownable(proxyAdmin).transferOwnership(broadcastConfig.delegate);
    }


    // Deploy the four lockboxes to any address
    function deployFraxOFTUpgradeablesAndProxies() broadcastAs(configDeployerPK) public override {
        (, frxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _token: frxEth
        });

        (, sfrxEthOft) = deployFraxOFTUpgradeableAndProxy({
            _token: sfrxEth
        });

        (, wfraxOft) = deployFraxOFTUpgradeableAndProxy({
            _token: fxs
        });

        (, fpiOft) = deployFraxOFTUpgradeableAndProxy({
            _token: fpi
        });
    }

    function deployFraxOFTUpgradeableAndProxy(address _token) public returns (address implementation, address proxy) {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
        implementationMock = 0x8f1B9c1fd67136D525E14D96Efb3887a33f16250;
        
        // create the implementation
        bytes memory bytecode = bytes.concat(
            abi.encodePacked(type(FraxOFTAdapterUpgradeable).creationCode),
            abi.encode(_token, broadcastConfig.endpoint)
        );
        assembly {
            implementation := create(0, add(bytecode, 0x20), mload(bytecode))
            if iszero(extcodesize(implementation)) {
                revert(0, 0)
            }
        }

        // TODO: shall we init implementation with address(0) ?
        // FraxOFTAdapterUpgradeable(implementation).initialize(address(0));

        // create the proxy
        proxy = address(new TransparentUpgradeableProxy(implementationMock, vm.addr(configDeployerPK), ""));
        proxyOfts.push(proxy);

        // upgrade and init
        bytes memory initializeArgs = abi.encodeWithSelector(
            FraxOFTAdapterUpgradeable.initialize.selector,
            vm.addr(configDeployerPK)
        );
        TransparentUpgradeableProxy(payable(proxy)).upgradeToAndCall({
            newImplementation: implementation,
            data: initializeArgs
        });

        // transfer ownership to config deployer
        TransparentUpgradeableProxy(payable(proxy)).changeAdmin(proxyAdmin);

        require(
            FraxOFTAdapterUpgradeable(proxy).token() == _token,
            "OFT token not set"
        );
        require(
            FraxOFTUpgradeable(proxy).owner() == vm.addr(configDeployerPK),
            "OFT owner incorrect"
        );
    }
}