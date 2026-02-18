// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.29;

import "./TestWithdrawRequest.sol";
import "../src/withdraws/EtherFi.sol";
import "../src/withdraws/Ethena.sol";
import "../src/withdraws/GenericERC4626.sol";
import "../src/withdraws/GenericERC20.sol";
import "../src/withdraws/Origin.sol";
import "../src/withdraws/Dinero.sol";

contract TestEtherFiWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) public override {
        vm.prank(0x0EF8fa4760Db8f5Cd4d993f3e3416f30f942D705); // etherFi: admin
        WithdrawRequestNFT.finalizeRequests(requestId);
    }

    function deployManager() public override {
        manager = new EtherFiWithdrawRequestManager();
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{value: 10e18}();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestEthenaWithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 requestId) public override {
        IsUSDe.UserCooldown memory wCooldown = sUSDe.cooldowns(address(uint160(requestId)));
        if (wCooldown.cooldownEnd > block.timestamp) {
            vm.warp(wCooldown.cooldownEnd);
        }
    }

    function deployManager() public override {
        manager = new EthenaWithdrawRequestManager();
        allowedDepositTokens.push(ERC20(address(USDe)));
        deal(address(USDe), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestGenericERC4626WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 /* requestId */) public pure override {
        return;
    }

    function deployManager() public override {
        manager = new GenericERC4626WithdrawRequestManager(address(sDAI));
        allowedDepositTokens.push(ERC20(address(DAI)));
        deal(address(DAI), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestGenericERC20WithdrawRequest is TestWithdrawRequest {
    function finalizeWithdrawRequest(uint256 /* requestId */) public pure override {
        return;
    }

    function deployManager() public override {
        manager = new GenericERC20WithdrawRequestManager(address(DAI));
        allowedDepositTokens.push(ERC20(address(DAI)));
        deal(address(DAI), address(this), 10_000e18);
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestOriginWithdrawRequest is TestWithdrawRequest {

    function finalizeWithdrawRequest(uint256 /* requestId */) public override {
        uint256 claimDelay = OriginVault.withdrawalClaimDelay();
        vm.warp(block.timestamp + claimDelay);

        deal(address(WETH), address(OriginVault), 1_000e18);
        OriginVault.addWithdrawalQueueLiquidity();
    }

    function deployManager() public override {
        manager = new OriginWithdrawRequestManager();
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{value: 10e18}();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestDinero_pxETH_WithdrawRequest is TestWithdrawRequest {

    function finalizeWithdrawRequest(uint256 requestId) public override {
        uint256 initialBatchId = requestId >> 120 & type(uint120).max;
        uint256 finalBatchId = requestId & type(uint120).max;
        address rewardRecipient = PirexETH.rewardRecipient();

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            bytes memory validator = PirexETH.batchIdToValidator(i);
            vm.record();
            PirexETH.status(validator);
            (bytes32[] memory reads, ) = vm.accesses(address(PirexETH));
            vm.store(address(PirexETH), reads[0], bytes32(uint256(IPirexETH.ValidatorStatus.Withdrawable)));

            deal(rewardRecipient, 32e18);
            vm.prank(rewardRecipient);
            PirexETH.dissolveValidator{value: 32e18}(validator);
        }
    }

    function deployManager() public override {
        manager = new DineroWithdrawRequestManager(address(pxETH));
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{value: 45e18}();
        depositCallData = "";
        withdrawCallData = "";
    }
}

contract TestDinero_apxETH_WithdrawRequest is TestWithdrawRequest {

    function finalizeWithdrawRequest(uint256 requestId) public override {
        uint256 initialBatchId = requestId >> 120 & type(uint120).max;
        uint256 finalBatchId = requestId & type(uint120).max;
        address rewardRecipient = PirexETH.rewardRecipient();

        for (uint256 i = initialBatchId; i <= finalBatchId; i++) {
            bytes memory validator = PirexETH.batchIdToValidator(i);
            vm.record();
            PirexETH.status(validator);
            (bytes32[] memory reads, ) = vm.accesses(address(PirexETH));
            vm.store(address(PirexETH), reads[0], bytes32(uint256(IPirexETH.ValidatorStatus.Withdrawable)));

            deal(rewardRecipient, 32e18);
            vm.prank(rewardRecipient);
            PirexETH.dissolveValidator{value: 32e18}(validator);
        }
    }

    function deployManager() public override {
        manager = new DineroWithdrawRequestManager(address(apxETH));
        allowedDepositTokens.push(ERC20(address(WETH)));
        WETH.deposit{value: 45e18}();
        depositCallData = "";
        withdrawCallData = "";
    }
}
