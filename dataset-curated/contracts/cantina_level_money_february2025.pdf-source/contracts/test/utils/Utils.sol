// SPDX-License-Identifier: Unlicense
pragma solidity >=0.8.0;

import {Test} from "forge-std/Test.sol";

contract Utils is Test {
    bytes32 internal nextUser = keccak256(abi.encodePacked("user address"));

    function getNextUserAddress() external returns (address payable) {
        address payable user = payable(address(uint160(uint256(nextUser))));
        nextUser = keccak256(abi.encodePacked(nextUser));
        return user;
    }

    // create users with 100 ETH balance each
    function createUsers(
        uint256 userNum
    ) external returns (address payable[] memory) {
        address payable[] memory users = new address payable[](userNum);
        for (uint256 i = 0; i < userNum; i++) {
            address payable user = this.getNextUserAddress();
            vm.deal(user, 100 ether);
            users[i] = user;
        }

        return users;
    }

    // move block.number forward by a given number of blocks
    function mineBlocks(uint256 numBlocks) external {
        uint256 targetBlock = block.number + numBlocks;
        vm.roll(targetBlock);
    }

    function startFork(
        string memory rpcKey,
        uint256 blockNumber
    ) external returns (uint256 forkId) {
        forkId = vm.createFork(vm.envString(rpcKey), blockNumber);
        vm.selectFork(forkId);
    }

    /// Useful function to check balance of tokens that don't conform
    /// to the ERC20 standard
    function checkBalance(
        address token,
        address account
    ) external returns (uint256) {
        // The function selector for balanceOf(address)
        bytes4 selector = bytes4(keccak256("balanceOf(address)"));

        // Encode the function call
        bytes memory data = abi.encodeWithSelector(selector, account);

        // Make the call
        (bool success, bytes memory returnData) = token.staticcall(data);

        require(success, "Balance check failed");

        // Decode the result
        return abi.decode(returnData, (uint256));
    }

    // add this to be excluded from coverage report
    function test() public {}
}
