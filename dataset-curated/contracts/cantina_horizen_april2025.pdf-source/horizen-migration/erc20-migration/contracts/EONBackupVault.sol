// SPDX-License-Identifier: MIT 
pragma solidity ^0.8.0;

import "./interfaces/IZenToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/// @title EONBackupVault
/// @notice This contract is used to store balances from old EON chain, and, once all are loaded, distribute corresponding ZEN in the new chain.
///         In the constructor will receive an admin address (owner), the only entity authorized to perform operations. Before loading all the accounts,
//          the cumulative hash calculated with all the accounts dump data must be set.
///         
contract EONBackupVault is Ownable {

    struct AddressValue {
        address addr;
        uint256 value;
    }
    
    // Map of the balances
    mapping(address => uint256) public balances;
    
    // Array to track inserted addresses
    address[] private addressList;
    
    // Cumulative Hash calculated
    bytes32 public _cumulativeHash;

    // Final expected Cumulative Hash, used for checkpoint, to unlock distribution
    bytes32 public cumulativeHashCheckpoint;      
  
    // Tracks rewarded addresses (index to next address to reward)
    uint256 private nextRewardIndex;

    IZenToken public zenToken;

    error AddressNotValid();
    error CumulativeHashNotValid();
    error CumulativeHashCheckpointReached();
    error CumulativeHashCheckpointNotSet();
    error UnauthorizedOperation();
    error ERC20NotSet();
    error NothingToDistribute();


    /// @notice Smart contract constructor
    /// @param _admin  the only entity authorized to perform restore and distribution operations
    constructor(address _admin) Ownable(_admin) {   
    }

    /// @notice Set expected cumulative hash after all the data has been loaded
    /// @param _cumulativeHashCheckpoint  a cumulative recursive hash calculated with all the dump data.
    ///                                   Will be used to verify the consistency of the restored data, and as
    ///                                   a checkpoint to understand when all the data has been loaded and the distribution 
    ///                                   can start
    function setCumulativeHashCheckpoint(bytes32 _cumulativeHashCheckpoint) public onlyOwner {
        if(_cumulativeHashCheckpoint == bytes32(0)) revert CumulativeHashNotValid();  
        if (cumulativeHashCheckpoint != bytes32(0)) revert UnauthorizedOperation();  //already set
        cumulativeHashCheckpoint = _cumulativeHashCheckpoint;
    }

    /// @notice Insert a new batch of tuples (address, value) and updates the cumulative hash.
    ///         To guarantee the same algorithm is applied, the expected cumulativeHash after the batch processing must be provided explicitly
    function batchInsert(bytes32 expectedCumulativeHash, AddressValue[] memory addressValues) public onlyOwner {
        if (cumulativeHashCheckpoint == bytes32(0)) revert CumulativeHashCheckpointNotSet();  
        if(_cumulativeHash == cumulativeHashCheckpoint) revert CumulativeHashCheckpointReached();
        uint256 i;
        bytes32 auxHash = _cumulativeHash;
        while (i != addressValues.length) {
            balances[addressValues[i].addr] = addressValues[i].value;
            addressList.push(addressValues[i].addr);
            auxHash = keccak256(abi.encode(auxHash, addressValues[i].addr, addressValues[i].value));
            unchecked { ++i; }
        }
        _cumulativeHash = auxHash;
        if (expectedCumulativeHash != _cumulativeHash) revert CumulativeHashNotValid();   
    }

    /// @notice Set official ZEN ERC-20 smart contract that will be used for minting
    function setERC20(address addr) public onlyOwner {  
        if (address(zenToken) != address(0)) revert UnauthorizedOperation();  //ERC-20 address already set
        if(addr == address(0)) revert AddressNotValid();
        zenToken = IZenToken(addr);
    }
    
    /// @notice Distribute ZEN for the next (max) "maxCount" addresses, until we have reached the end of the list
    ///         Can be executed only when we have reached the planned cumulativeHashCheckpoint (meaning all data has been loaded)
    function distribute(uint256 maxCount) public onlyOwner {
        if (cumulativeHashCheckpoint == bytes32(0)) revert CumulativeHashCheckpointNotSet();  
        if (address(zenToken) == address(0)) revert ERC20NotSet();
        if (_cumulativeHash != cumulativeHashCheckpoint) revert CumulativeHashNotValid(); //Loaded data not matching - distribution locked
        if (nextRewardIndex == addressList.length) revert NothingToDistribute();        

        uint256 count = 0;
        uint256 _nextRewardIndex = nextRewardIndex;
        while (_nextRewardIndex != addressList.length && count != maxCount) {
            address addr = addressList[_nextRewardIndex];      
            uint256 amount = balances[addr];
            if (amount > 0) {                
                balances[addr] = 0;
                zenToken.mint(addr, amount);
            }
            unchecked { 
                ++_nextRewardIndex;
                ++count;
            }
        }
        nextRewardIndex = _nextRewardIndex;
        if (nextRewardIndex == addressList.length){
            zenToken.notifyMintingDone();
        }
    }

    /// @notice Return true if admin is able to distribute more
    function moreToDistribute() public view  returns (bool) { 
        return (address(zenToken) != address(0)) && 
               (_cumulativeHash != bytes32(0)) &&
               _cumulativeHash == cumulativeHashCheckpoint && 
               nextRewardIndex <  addressList.length;
    }
}