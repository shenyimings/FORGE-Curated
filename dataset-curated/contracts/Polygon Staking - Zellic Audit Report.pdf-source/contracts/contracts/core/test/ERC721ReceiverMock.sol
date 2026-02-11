// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

/**
 * @title ERC721 Receiver
 * @notice Mocks ERC721 receiver for testing
 */
contract ERC721ReceiverMock is IERC721Receiver {
    struct Data {
        address operator;
        address from;
        uint256 tokenId;
        bytes data;
    }

    Data[] private data;

    function getData() external view returns (Data[] memory) {
        return data;
    }

    function onERC721Received(
        address _operator,
        address _from,
        uint256 _tokenId,
        bytes calldata _data
    ) external returns (bytes4) {
        data.push(Data(_operator, _from, _tokenId, _data));
        return this.onERC721Received.selector;
    }
}
