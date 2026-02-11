// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVesting.sol";

/// @title LinearTokenVesting
/// @notice This contract implements the vesting strategy for the remaining ZEN supply.  
contract LinearTokenVesting is Ownable, IVesting {
    
    uint8 private _allowedOwnershipTransfers = 2;

    ERC20 public token;
    address public beneficiary;

    uint256 public amountForEachClaim;
    uint256 public startTimestamp;
    uint256 public timeBetweenClaims; 
    uint256 public intervalsToClaim;
    uint256 public intervalsAlreadyClaimed;

    event Claimed(address indexed claimer, address indexed beneficiary, uint256 claimAmount, uint256 timestamp);
    event ChangedBeneficiary(address indexed newBeneficiary, address indexed oldBeneficiary);
    event ChangedVestingParams(
                                uint256 newTimeBetweenClaims, 
                                uint256 newIntervalsToClaim, 
                                uint256 oldTimeBetweenClaims, 
                                uint256 oldIntervalsToClaim);

    error AddressParameterCantBeZero();
    error TokenAndBeneficiaryCantBeTheSame();
    error AmountCantBeZero();
    error InvalidTimes();
    error InvalidNumOfIntervals();
    error NothingToClaim();
    error ClaimCompleted();
    error UnauthorizedOperation();
    error ERC20NotSet();
    error VestingNotStartedYet();
    error VestingAlreadyStarted();
    error UnauthorizedAccount(address account);
    error ImmutableOwner();

    /// @notice Smart contract constructor
    /// @param _beneficiary the account that will receive the vested zen
    /// @param _timeBetweenClaims The minimum time in seconds that must be waited between claims
    /// @param _intervalsToClaim The number of vesting periods 
    constructor(address _beneficiary, uint256 _timeBetweenClaims, uint256 _intervalsToClaim) Ownable(msg.sender) {
        _setBeneficiary(_beneficiary);
        _setVestingParams(_timeBetweenClaims, _intervalsToClaim);
    }

    /// @notice Set official ZEN ERC-20 smart contract that will be used for initial transfer and start vesting
    /// @param addr Address of the ERC20
    function setERC20(address addr) public onlyOwner {
        if (address(token) != address(0)) revert UnauthorizedOperation();  //ERC-20 address already set
        if(addr == address(0)) revert AddressParameterCantBeZero();
        if(addr == beneficiary) revert TokenAndBeneficiaryCantBeTheSame();
        token = ERC20(addr);
    }

    /// @notice This function is called by the ERC20 when minting has ended, to notify that the vesting period can start.
    function startVesting() public {
        if (msg.sender != address(token)) revert UnauthorizedOperation(); 
        if (amountForEachClaim != 0 || startTimestamp != 0) revert VestingAlreadyStarted(); //already called

        uint256 totalToVest = token.balanceOf(address(this));
        if (totalToVest == 0) revert AmountCantBeZero();
        amountForEachClaim = totalToVest / intervalsToClaim;
        startTimestamp = block.timestamp;
    } 

    /// @notice This function is called for transfer to beneficiary the amount that was accrued from the last claim. If it is called before at least one interval has passed, the claim fails. 
    ///         If more than one period have passed, the sum of amounts of the passed periods is transferred. 
    function claim() public {
        if (address(token) == address(0)) revert ERC20NotSet();
        if (startTimestamp == 0) revert VestingNotStartedYet();
        if (intervalsAlreadyClaimed == intervalsToClaim) revert ClaimCompleted();

        uint256 periodsPassed = (block.timestamp - (startTimestamp + timeBetweenClaims * intervalsAlreadyClaimed)) / timeBetweenClaims;
        if (periodsPassed == 0) revert NothingToClaim();

        uint256 intervalsToClaimNow = _min(intervalsToClaim - intervalsAlreadyClaimed, periodsPassed); 
        intervalsAlreadyClaimed += intervalsToClaimNow;       
        uint256 amountToClaimNow;
        if (intervalsAlreadyClaimed < intervalsToClaim) {
            amountToClaimNow = intervalsToClaimNow * amountForEachClaim;
        }
        else {
            amountToClaimNow = token.balanceOf(address(this));
        }

        emit Claimed(msg.sender, beneficiary, amountToClaimNow, block.timestamp);

        token.transfer(beneficiary, amountToClaimNow);
    }

    /// @notice Changes the beneficiary of the vesting
    /// @param newBeneficiary Address of the new beneficiary
    function changeBeneficiary(address newBeneficiary) public onlyOwner {
        if (intervalsAlreadyClaimed == intervalsToClaim) revert UnauthorizedOperation();
        if (newBeneficiary == address(token)) revert TokenAndBeneficiaryCantBeTheSame();

        address oldBeneficiary = beneficiary;
        _setBeneficiary(newBeneficiary);
        emit ChangedBeneficiary(newBeneficiary, oldBeneficiary);
    }

    /// @notice Changes the number of vesting intervals and their duration. After this method has been called, the supply not claimed yet (i.e the balance of this contract) will be able to be claimed 
    /// in a time equal to newTimeBetweenClaims * newNumberOfIntervalsToClaim. Note that the remaining supply includes the amounts already accrued but not claimed yet.
    /// @param newTimeBetweenClaims New duration in seconds of a vesting interval
    /// @param newNumberOfIntervalsToClaim Number of intervals that need to pass for vesting the remaining supply
    function changeVestingParams(uint256 newTimeBetweenClaims, uint256 newNumberOfIntervalsToClaim) public onlyOwner {
        if (intervalsAlreadyClaimed == intervalsToClaim) revert UnauthorizedOperation();
        uint256 oldTimeBetweenClaims = timeBetweenClaims;
        uint256 oldNumberOfIntervalsToClaim = intervalsToClaim;
        _setVestingParams(newTimeBetweenClaims, newNumberOfIntervalsToClaim);

        // if startVesting was already called, startTimestamp, amountForEachClaim and intervalsAlreadyClaimed need to be reset
        if (startTimestamp != 0){
            uint256 totalToVest = token.balanceOf(address(this));
            amountForEachClaim = totalToVest / intervalsToClaim;
            startTimestamp = block.timestamp;
            intervalsAlreadyClaimed = 0;
        }
        emit ChangedVestingParams(newTimeBetweenClaims, newNumberOfIntervalsToClaim, oldTimeBetweenClaims, oldNumberOfIntervalsToClaim);
    }

    function _min(uint256 a, uint256 b) internal pure returns(uint256) {
        return a < b? a : b;
    }

    function _setBeneficiary(address newBeneficiary) internal {
        if(newBeneficiary == address(0)) revert AddressParameterCantBeZero();
        beneficiary = newBeneficiary;
    }

    function _setVestingParams(uint256 newTimeBetweenClaims, uint256 newNumberOfIntervalsToClaim) internal {
        if(newNumberOfIntervalsToClaim == 0) revert InvalidNumOfIntervals(); 
        if(newTimeBetweenClaims == 0) revert InvalidTimes();

        timeBetweenClaims = newTimeBetweenClaims;
        intervalsToClaim = newNumberOfIntervalsToClaim;        
    }

    function _transferOwnership(address newOwner) internal override {
        if (_allowedOwnershipTransfers == 0) revert ImmutableOwner();

        unchecked {--_allowedOwnershipTransfers;}
        super._transferOwnership(newOwner);
   }
}