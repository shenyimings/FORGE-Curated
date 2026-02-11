// SPDX-License-Identifier: BSL-1.1
pragma solidity =0.8.28;

/*
 _____ _____ __    ____  _____ 
|     |  _  |  |  |    \|  _  |
| | | |     |  |__|  |  |     |
|_|_|_|__|__|_____|____/|__|__|   
*/

// interfaces
import {IRiscZeroVerifier} from "risc0/IRiscZeroVerifier.sol";

// external
import {Steel} from "risc0/steel/Steel.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// exchange rate is 1:1
contract LendingProtocolMock is Ownable {
    using SafeERC20 for IERC20;
    // --------- STORAGE ---------------

    address public token;
    IRiscZeroVerifier public verifier;
    bytes32 public borrowImageId;
    bytes32 public withdrawImageId;

    mapping(address => uint256) public balanceOf;
    mapping(address => uint256) public borrowBalanceOf;

    error LendingProtocolMock_JournalNotValid();
    error LendingProtocolMock_InsufficientBalance();
    error LendingProtocolMock_InsufficientLiquidity();
    error LendingProtocolMock_InvalidCommitment(uint256 id);

    constructor(address _token, address _verifier, address _owner) Ownable(_owner) {
        verifier = IRiscZeroVerifier(_verifier);
        token = _token;
    }

    // --------- OWNABLE ---------------
    function setVerifier(address _verifier) external onlyOwner {
        verifier = IRiscZeroVerifier(_verifier);
    }

    function setBorrowImageId(bytes32 _imageId) external onlyOwner {
        borrowImageId = _imageId;
    }

    function setWithdrawImageId(bytes32 _imageId) external onlyOwner {
        withdrawImageId = _imageId;
    }

    // --------- PUBLIC METHODS ---------------
    function deposit(uint256 amount, address to) external {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[to] += amount;
    }

    function borrow(uint256 amount, bytes calldata journalData, bytes calldata seal) external {
        _verifyProof(journalData, seal, borrowImageId);

        // decode action data
        (uint256 liquidity, address user) = abi.decode(journalData[96:], (uint256, address));

        require(liquidity >= amount, LendingProtocolMock_InsufficientLiquidity());
        require(IERC20(token).balanceOf(address(this)) >= amount, LendingProtocolMock_InsufficientBalance());
        borrowBalanceOf[user] += amount;
        IERC20(token).safeTransfer(user, amount);
    }

    function repay(uint256 amount) external {
        require(borrowBalanceOf[msg.sender] >= amount, LendingProtocolMock_InsufficientBalance());
        borrowBalanceOf[msg.sender] -= amount;
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount, bytes calldata journalData, bytes calldata seal) external {
        _verifyProof(journalData, seal, withdrawImageId);

        // decode action data
        (uint256 provided, address user) = abi.decode(journalData[96:], (uint256, address));

        require(provided >= amount, LendingProtocolMock_InsufficientLiquidity());
        require(balanceOf[user] >= amount, LendingProtocolMock_InsufficientBalance());
        balanceOf[user] -= amount;
        IERC20(token).safeTransfer(user, amount);
    }

    // --------- PRIVATE METHODS ---------------
    function _verifyProof(bytes calldata journalData, bytes calldata seal, bytes32 imageId) private view {
        require(journalData.length > 95, LendingProtocolMock_JournalNotValid());

        // verify proof
        verifier.verify(seal, imageId, sha256(journalData));
    }
}
