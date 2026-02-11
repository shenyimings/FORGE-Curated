// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./BlueprintCoreV4.sol";

contract Blueprint is OwnableUpgradeable, BlueprintCore {
    // slither-disable-next-line naming-convention
    function setNFTContractAddress(address _nftContractAddress) public onlyOwner {
        require(_nftContractAddress != address(0), "NFT Contract is invalid");
        nftContractAddress = _nftContractAddress;
    }

    function setWhitelistAddresses(address[] calldata whitelistAddress) public onlyOwner {
        for (uint256 i = 0; i < whitelistAddress.length; i++) {
            whitelistUsers[whitelistAddress[i]] = Status.Issued;
        }
    }

    function addWhitelistAddress(address whitelistAddress) public onlyOwner {
        whitelistUsers[whitelistAddress] = Status.Issued;
    }

    function deleteWhitelistAddress(address whitelistAddress) public onlyOwner {
        delete whitelistUsers[whitelistAddress];
    }

    function resetAgentCreationStatus(address userAddress, uint256 tokenId) public onlyOwner {
        whitelistUsers[userAddress] = Status.Issued;
        nftTokenIdMap[tokenId] = Status.Init;
    }

    // slither-disable-next-line costly-loop
    function removeWhitelistAddresses(address[] calldata removedAddress) public onlyOwner {
        for (uint256 i = 0; i < removedAddress.length; i++) {
            delete whitelistUsers[removedAddress[i]];
        }
    }
}
