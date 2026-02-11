pragma solidity ^0.8.0;

import "scripts/ops/V110/fraxtal/UpgradeAdapterFraxtal.s.sol";
import "frax-std/FraxTest.sol";

struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}

interface IOAppReceiver {
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}

contract UpgradeAdapterTest is UpgradeAdapter, FraxTest {
    using OptionsBuilder for bytes;

    address bob = vm.addr(0xb0b);
    // Set mock supply for testing
    uint32 eid = 30101; // Example EID

    function setUp() public override {
        vm.createSelectFork("https://rpc.frax.com", 22382257);
        deal(bob, 100e18);

        super.setUp();
        require(broadcastConfig.chainid == 252, "Fraxtal config not set");

        vm.label(bob, "bob");
        vm.label(frxUsd, "frxUSD");
    }

    function test_UpgradeAdapters() external {
        run();

        validateUpgrade(frxUsd, fraxtalFrxUsdLockbox);
        validateUpgrade(sfrxUsd, fraxtalSFrxUsdLockbox);
        validateUpgrade(fpi, fraxtalFpiLockbox);
    }

    function validateUpgrade(address token, address lockbox) internal {
        _testRecover(token, lockbox);
        _testSend(token, lockbox);
        _testReceive(token, lockbox);
        _testSetInitialTotalSupply(lockbox);
    }

    function _testRecover(address token, address lockbox) internal {
        // recover tokens to delegate
        uint256 balanceDelegateBefore = IERC20(token).balanceOf(broadcastConfig.delegate);
        uint256 balanceLockbox = IERC20(token).balanceOf(lockbox);

        FraxOFTMintableAdapterUpgradeable(lockbox).recover();

        assertEq(
            IERC20(token).balanceOf(broadcastConfig.delegate),
            balanceDelegateBefore + balanceLockbox,
            "Recover failed"
        );
        assertEq(
            IERC20(token).balanceOf(lockbox),
            0,
            "Lockbox balance should be zero after recover"
        );
    }

    function _testSend(address token, address lockbox) internal {
        uint256 amount = 1e18;
        
        console.log(IERC20(token).balanceOf(bob));
        deal(token, bob, amount);
        uint256 balanceBobBefore = IERC20(token).balanceOf(bob);
        uint256 totalSupplyBefore = IERC20(token).totalSupply();
        console.log(IERC20(token).balanceOf(bob));

        vm.startPrank(bob);

        IERC20(token).approve(lockbox, amount);
        bytes memory options = OptionsBuilder.newOptions();
        SendParam memory sendParam = SendParam({
            dstEid: 30101,
            to: addressToBytes32(broadcastConfig.delegate),
            amountLD: amount,
            minAmountLD: amount,
            extraOptions: options,
            composeMsg: '',
            oftCmd: ''
        });
        MessagingFee memory fee = IOFT(lockbox).quoteSend(sendParam, false);
        IOFT(lockbox).send{value: fee.nativeFee}(
            sendParam,
            fee,
            payable(bob)
        );

        vm.stopPrank();

        console.log(IERC20(token).balanceOf(bob));
        assertEq(
            IERC20(token).balanceOf(bob),
            balanceBobBefore - amount,
            "Bob's balance should decrease after send"
        );
        assertEq(
            IERC20(token).totalSupply(),
            totalSupplyBefore - amount,
            "Total supply should decrease after send"
        );
        assertEq(
            FraxOFTMintableAdapterUpgradeable(lockbox).totalTransferToSum(),
            amount,
            "Sum total transfer to should increase"
        );
        assertEq(
            FraxOFTMintableAdapterUpgradeable(lockbox).totalTransferTo(eid),
            amount,
            "Total transfer to should increase"
        );
    }

    function _testReceive(address token, address lockbox) internal {
        uint256 amount = 1e18;
        uint256 balanceBobBefore = IERC20(token).balanceOf(bob);
        uint256 totalSupplyBefore = IERC20(token).totalSupply();

        Origin memory origin = Origin({
            srcEid: eid,
            sender: IOAppCore(lockbox).peers(eid),
            nonce: 1
        });

        bytes memory message = abi.encodePacked(
            bytes32(uint256(uint160(bob))), // sendTo
            uint64(amount / (10**18 / 10**6)), // amountSD - see OFTCoreUpgradeable amountReceivedLD
            bytes32(uint256(uint160(bob))), // composeMsgSender
            '' // composeMsg
        );

        vm.prank(broadcastConfig.endpoint);
        IOAppReceiver(lockbox).lzReceive({
            _origin: origin,
            _guid: bytes32(0),
            _message: message,
            _executor: 0x41Bdb4aa4A63a5b2Efc531858d3118392B1A1C3d, // from LZ docs
            _extraData: ''
        });

        assertEq(
            IERC20(token).balanceOf(bob),
            balanceBobBefore + amount,
            "Bob's balance should increase after receive"
        );
        assertEq(
            IERC20(token).totalSupply(),
            totalSupplyBefore + amount,
            "Total supply should increase after receive"
        );
        assertEq(
            FraxOFTMintableAdapterUpgradeable(lockbox).totalTransferFromSum(),
            amount,
            "Sum total transfer from should increase"
        );
        assertEq(
            FraxOFTMintableAdapterUpgradeable(lockbox).totalTransferFrom(eid),
            amount,
            "Total transfer from should increase"
        );
    }

    function _testSetInitialTotalSupply(address lockbox) internal {
        uint256 initialSupply = 1e18;

        assertEq(
            FraxOFTMintableAdapterUpgradeable(lockbox).initialTotalSupply(eid),
            0,
            "Initial total supply should be zero before setting"
        );
        
        vm.prank(broadcastConfig.delegate);
        FraxOFTMintableAdapterUpgradeable(lockbox).setInitialTotalSupply(eid, initialSupply);

        assertEq(
            FraxOFTMintableAdapterUpgradeable(lockbox).initialTotalSupply(eid),
            initialSupply,
            "Initial total supply should be set correctly"
        );
    }
}
