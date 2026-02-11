// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "forge-std/Vm.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";
import "../../contracts/Earn.sol";


contract SignTest is Test {

    using SignatureChecker for address;
    Earn.ExchangeRateInfo[] public  exchangeRateInfoListReq;

    function testSign() public {
        (address signer, uint256 privateKey) = makeAddrAndKey("myLabel");

        Earn.ExchangeRateInfo memory exchangeRateInfo1 = Earn.ExchangeRateInfo({
            assTokenAddress: makeAddr("signer1"),
            exchangeRateExpiredTimestamp: 10000,
            assToSourceExchangeRate: 1000000000
        });

        Earn.ExchangeRateInfo memory exchangeRateInfo2 = Earn.ExchangeRateInfo({
            assTokenAddress: makeAddr("signer2"),
            exchangeRateExpiredTimestamp: 20000,
            assToSourceExchangeRate: 2000000000
        });

        exchangeRateInfoListReq.push(exchangeRateInfo1);
        exchangeRateInfoListReq.push(exchangeRateInfo2);

        uint256 deadLineReq = block.timestamp + 60;
        bytes memory message = abi.encode(exchangeRateInfoListReq, deadLineReq);
        bytes32 txHash = MessageHashUtils.toEthSignedMessageHash(keccak256(message));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        require(signer.isValidSignatureNow(MessageHashUtils.toEthSignedMessageHash(keccak256(message)), signature), "only accept signer signed message");

        (Earn.ExchangeRateInfo[] memory exchangeRateInfoList,uint256 deadLine) = abi.decode(message, (Earn.ExchangeRateInfo[], uint256));

        for (uint i = 0; i < 2; i++) {
            assertEq(exchangeRateInfoList[i].assTokenAddress, exchangeRateInfoListReq[i].assTokenAddress);
            assertEq(exchangeRateInfoList[i].assToSourceExchangeRate, exchangeRateInfoListReq[i].assToSourceExchangeRate);
            assertEq(exchangeRateInfoList[i].exchangeRateExpiredTimestamp, exchangeRateInfoListReq[i].exchangeRateExpiredTimestamp);
        }
        assertEq(deadLine, deadLineReq);

    }
}
