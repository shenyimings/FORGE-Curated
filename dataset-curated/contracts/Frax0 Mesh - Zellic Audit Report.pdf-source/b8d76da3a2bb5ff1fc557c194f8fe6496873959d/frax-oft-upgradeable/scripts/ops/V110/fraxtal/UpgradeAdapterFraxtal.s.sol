pragma solidity ^0.8.0;

import "scripts/DeployFraxOFTProtocol/DeployFraxOFTProtocol.s.sol";
import {FraxOFTMintableAdapterUpgradeable} from "contracts/FraxOFTMintableAdapterUpgradeable.sol";

interface IERC20PermitPermissionedOptiMintable {
    function addMinter(address) external;
}

// forge script scripts/ops/V110/fraxtal/UpgradeAdapterFraxtal.s.sol --rpc-url https://rpc.frax.com
contract UpgradeAdapter is DeployFraxOFTProtocol {
    
    address frxUsd = 0xFc00000000000000000000000000000000000001;
    address sfrxUsd = 0xfc00000000000000000000000000000000000008;
    address fpi = 0xFc00000000000000000000000000000000000003;

    address comptroller = 0xC4EB45d80DC1F079045E75D5d55de8eD1c1090E6;

    address frxUsdMintableLockboxImp;
    address sfrxUsdMintableLockboxImp;
    address fpiMintableLockboxImp;

    uint256 msigSubmissionCount;

    constructor() {
        proxyAdmin = 0x223a681fc5c5522c85C96157c0efA18cd6c5405c;
    }

    modifier prankAndWriteTxs(address who) {
        vm.startPrank(who);
        _;
        vm.stopPrank();

        msigSubmissionCount++;

        new SafeTxUtil().writeTxs(serializedTxs, filename());
        delete serializedTxs;
    }

    function filename() public view override returns (string memory) {
        string memory root = vm.projectRoot();
        root = string.concat(root, "/scripts/ops/V110/fraxtal/txs/UpgradeAdapter");

        if (msigSubmissionCount == 1) {
            return string.concat(root, "-comptroller.json");
        } else {
            return string.concat(root, "-operator.json");
        }
    }

    function run() public override {
        deployMintableLockboxes();
        generateComptrollerTxs();
        generateOperatorTxs();
    }

    function generateComptrollerTxs() public prankAndWriteTxs(comptroller) {
        addMinterRoles();
    }

    function addMinterRoles() public {
        addMinterRole(frxUsd, fraxtalFrxUsdLockbox);
        addMinterRole(sfrxUsd, fraxtalSFrxUsdLockbox);
        addMinterRole(fpi, fraxtalFpiLockbox);
    }

    function addMinterRole(address _token, address _lockbox) public {
        bytes memory data = abi.encodeCall(
            IERC20PermitPermissionedOptiMintable.addMinter,
            (_lockbox)
        );
        (bool success, ) = _token.call(data);
        require(success, "Add minter role failed");
        serializedTxs.push(
            SerializedTx({
                name: "Add minter role",
                to: _token,
                value: 0,
                data: data
            })
        );
    }

    function generateOperatorTxs() public prankAndWriteTxs(broadcastConfig.delegate) {
        upgradeExistingLockboxes();
        transferProxyAdminOwnership();
    }

    function _validateAndPopulateMainnetOfts() internal override {}

    function deployMintableLockboxes() broadcastAs(senderDeployerPK) public {
        frxUsdMintableLockboxImp = deployMintableLockbox(frxUsd);
        sfrxUsdMintableLockboxImp = deployMintableLockbox(sfrxUsd);
        fpiMintableLockboxImp = deployMintableLockbox(fpi);
    }

    function deployMintableLockbox(address _token) public returns (address) {
        return address(
            new FraxOFTMintableAdapterUpgradeable(
                _token,
                broadcastConfig.endpoint
            )
        );
    }

    function upgradeExistingLockboxes() public {
        upgradeExistingLockbox(fraxtalFrxUsdLockbox, frxUsdMintableLockboxImp);
        upgradeExistingLockbox(fraxtalSFrxUsdLockbox, sfrxUsdMintableLockboxImp);
        upgradeExistingLockbox(fraxtalFpiLockbox, fpiMintableLockboxImp);
    }

    function upgradeExistingLockbox(
        address _lockbox,
        address _implementation
    ) public {
        bytes memory data = abi.encodeCall(
            ProxyAdmin.upgrade,
            (
                TransparentUpgradeableProxy(payable(_lockbox)),
                _implementation
            )
        );

        (bool success, ) = proxyAdmin.call(data);
        require(success, "Upgrade failed");
        serializedTxs.push(
            SerializedTx({
                name: "Upgrade Lockbox",
                to: _lockbox,
                value: 0,
                data: data
            })
        );
    }

    function transferProxyAdminOwnership() public {
        bytes memory data = abi.encodeCall(
            Ownable.transferOwnership,
            (comptroller)
        );

        (bool success, ) = proxyAdmin.call(data);
        require(success, "Transfer ownership failed");
        serializedTxs.push(
            SerializedTx({
                name: "Transfer Proxy Admin Ownership",
                to: proxyAdmin,
                value: 0,
                data: data
            })
        );
    }
}