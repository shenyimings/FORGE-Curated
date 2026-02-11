// SPDX-License-Identifier: MIT
// solhint-disable gas-custom-errors
// solhint-disable reason-string

pragma solidity ^0.8.27;

import {EnumerableSet} from "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import {IGovernanceVotePower} from "@flarenetwork/flare-periphery-contracts/flare/IGovernanceVotePower.sol";
import {IVPContractEvents} from "@flarenetwork/flare-periphery-contracts/flare/IVPContractEvents.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafePct} from "../../utils/library/SafePct.sol";
import {IVPToken, IWNat} from "../interfaces/IWNat.sol";


contract WNatMock is IWNat, ERC20 {
    using EnumerableSet for EnumerableSet.AddressSet;

    IGovernanceVotePower private governanceVP;

    struct Delegation {
        address delegateAddress; // address to which the vote power is delegated
        uint16 bips; // 10000 bips = 100%
    }

    mapping(address => Delegation[]) private delegations;
    mapping(address delegatee => EnumerableSet.AddressSet) private delegators;

    constructor(
        address /*_governance*/,
        string memory _name,
        string memory _symbol
    )
        ERC20(_name, _symbol)
    {
    }

    receive() external payable {
        deposit();
    }

    function name() public view override(ERC20, IVPToken) returns (string memory) {
        return ERC20.name();
    }

    function symbol() public view override(ERC20, IVPToken) returns (string memory) {
        return ERC20.symbol();
    }

    function decimals() public view override(ERC20, IVPToken) returns (uint8) {
        return ERC20.decimals();
    }

    function deposit() public payable {
        _mint(msg.sender, msg.value);
    }

    function depositTo(address _recipient) public payable {
        _mint(_recipient, msg.value);
    }

    function withdraw(uint256 _amount) external {
        _burn(msg.sender, _amount);
        payable(msg.sender).transfer(_amount);
    }

    function withdrawFrom(address _owner, uint256 _amount) external {
        _spendAllowance(_owner, msg.sender, _amount);
        _burn(_owner, _amount);
        payable(msg.sender).transfer(_amount);
    }

    function delegate(address _to, uint256 _bips) external {
        require(_to != address(0), "cannot delegate to zero address");
        require(_to != msg.sender, "cannot delegate to self");
        require(_bips <= SafePct.MAX_BIPS, "bips out of range");

        uint256 totalBips = 0;
        bool update = false;
        Delegation[] storage ownerDelegations = delegations[msg.sender];
        for (uint256 i = 0; i < ownerDelegations.length; i++) {
            if (ownerDelegations[i].delegateAddress == _to) {
                ownerDelegations[i].bips = uint16(_bips);
                update = true;
            }
            totalBips += ownerDelegations[i].bips;
        }
        if (!update) {
            // add new delegation
            ownerDelegations.push(Delegation(_to, uint16(_bips)));
            totalBips += _bips;
        }
        require(totalBips <= SafePct.MAX_BIPS, "total bips cannot exceed 10000");
        require(ownerDelegations.length <= 2, "cannot have more than 2 delegations");

        // update delegators set
        delegators[_to].add(msg.sender);
    }

    function undelegateAll() external {
        // remove from delegators set
        Delegation[] storage ownerDelegations = delegations[msg.sender];
        for (uint256 i = 0; i < ownerDelegations.length; i++) {
            address delegateAddress = ownerDelegations[i].delegateAddress;
            delegators[delegateAddress].remove(msg.sender);
        }
        delete delegations[msg.sender];
    }

    function delegatesOf(
        address _owner
    )
        external view
        returns (
            address[] memory _delegateAddresses,
            uint256[] memory _bips,
            uint256 _count,
            uint256 _delegationMode
        )
    {
        Delegation[] storage ownerDelegations = delegations[_owner];
        _count = ownerDelegations.length;
        _delegateAddresses = new address[](_count);
        _bips = new uint256[](_count);
        for (uint256 i = 0; i < _count; i++) {
            _delegateAddresses[i] = ownerDelegations[i].delegateAddress;
            _bips[i] = ownerDelegations[i].bips;
        }
        _delegationMode = 1; // 1 means delegation by percentage (bips)
    }

    function totalVotePower() external view returns(uint256) {
        return totalSupply();
    }

    function votePowerOf(address _owner) external view returns(uint256 _votePower) {
        uint256 balance = balanceOf(_owner);
        _votePower = balance;

        // Subtract delegated vote power
        Delegation[] storage ownerDelegations = delegations[_owner];
        for (uint256 i = 0; i < ownerDelegations.length; i++) {
            uint256 bips = ownerDelegations[i].bips;
            _votePower -= (balance * bips) / SafePct.MAX_BIPS;
        }

        // Add vote power from delegators
        EnumerableSet.AddressSet storage ownerDelegators = delegators[_owner];
        for (uint256 i = 0; i < ownerDelegators.length(); i++) {
            address delegator = ownerDelegators.at(i);
            Delegation[] storage delegatorDelegations = delegations[delegator];
            for (uint256 j = 0; j < delegatorDelegations.length; j++) {
                if (delegatorDelegations[j].delegateAddress == _owner) {
                    uint256 bips = delegatorDelegations[j].bips;
                    _votePower += (balanceOf(delegator) * bips) / SafePct.MAX_BIPS;
                }
            }
        }
    }

    function undelegatedVotePowerOf(address _owner) external view returns(uint256 _votePower) {
        uint256 balance = balanceOf(_owner);
        _votePower = balance;

        // Subtract delegated vote power
        Delegation[] storage ownerDelegations = delegations[_owner];
        for (uint256 i = 0; i < ownerDelegations.length; i++) {
            uint256 bips = ownerDelegations[i].bips;
            _votePower -= (balance * bips) / SafePct.MAX_BIPS;
        }
    }

    function votePowerFromTo(address _from, address _to) external view returns(uint256) {
        Delegation[] storage ownerDelegations = delegations[_from];
        for (uint256 i = 0; i < ownerDelegations.length; i++) {
            if (ownerDelegations[i].delegateAddress == _to) {
                uint256 balance = balanceOf(_from);
                uint256 bips = ownerDelegations[i].bips;
                return (balance * bips) / SafePct.MAX_BIPS;
            }
        }
        return 0; // No delegations found
    }

    function delegationModeOf(address /*_who*/) external pure returns(uint256) {
        // In this mock implementation, we only support delegation by percentage (bips)
        return 1; // 1 means delegations by percentage (bips)
    }

    function setGovernanceVotePower(IGovernanceVotePower _governanceVotePower) external {
        governanceVP = _governanceVotePower;
    }

    function governanceVotePower() external view returns (IGovernanceVotePower) {
        return governanceVP;
    }

    //////// UNIMPLEMENTED METHODS ////////

    function balanceOfAt(address /*_owner*/, uint256 /*_blockNumber*/) external pure returns (uint256) {
        revert("not implemented");
    }

    function totalSupplyAt(uint256 /*_blockNumber*/) external pure returns(uint256) {
        revert("not implemented");
    }

    function totalVotePowerAt(uint256 /*_blockNumber*/) external pure returns(uint256) {
        revert("not implemented");
    }

    function votePowerFromToAt(address /*_from*/, address /*_to*/, uint256 /*_blockNumber*/)
        external pure returns(uint256)
    {
        revert("not implemented");
    }

    function votePowerOfAt(address /*_owner*/, uint256 /*_blockNumber*/) external pure returns(uint256) {
        revert("not implemented");
    }

    function votePowerOfAtIgnoringRevocation(address /*_owner*/, uint256 /*_blockNumber*/)
        external pure returns(uint256)
    {
        revert("not implemented");
    }

    function delegatesOfAt(address /*_who*/, uint256 /*_blockNumber*/)
        external pure
        returns (
            address[] memory /*_delegateAddresses*/,
            uint256[] memory /*_bips*/,
            uint256 /*_count*/,
            uint256 /*_delegationMode*/
        )
    {
        revert("not implemented");
    }

    function undelegatedVotePowerOfAt(address /*_owner*/, uint256 /*_blockNumber*/) external pure returns(uint256) {
        revert("not implemented");
    }

    function batchDelegate(address[] memory /*_delegatees*/, uint256[] memory /*_bips*/) external pure {
        revert("not implemented");
    }

    function delegateExplicit(address /*_to*/, uint256 /*_amount*/) external pure {
        revert("not implemented");
    }

    function revokeDelegationAt(address /*_who*/, uint256 /*_blockNumber*/) external pure {
        revert("not implemented");
    }

    function undelegateAllExplicit(address[] memory /*_delegateAddresses*/) external pure returns (uint256) {
        revert("not implemented");
    }

    function readVotePowerContract() external pure returns (IVPContractEvents) {
        revert("not implemented");
    }

    function writeVotePowerContract() external pure returns (IVPContractEvents) {
        revert("not implemented");
    }
}
