// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.24;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {AllowList} from "src/allowList/AllowList.sol";
import {IPool} from "src/amm/base/IPool.sol";
import {GenericERC20} from "src/example/ERC20/GenericERC20.sol";
import {GenericERC20FixedSupply} from "src/example/ERC20/GenericERC20FixedSupply.sol";
import {TwentyTwoDecimalERC20} from "src/example/ERC20/TwentyTwoDecimalERC20.sol";
import {SixDecimalERC20} from "src/example/ERC20/SixDecimalERC20.sol";
import {TwentyTwoDecimalERC20} from "src/example/ERC20/TwentyTwoDecimalERC20.sol";
import {FeeOnTransferERC20} from "src/example/ERC20/FeeOnTransferERC20.sol";
import {PoolBase} from "src/amm/base/PoolBase.sol";
import {PythonUtils} from "test/util/PythonUtils.sol";
import {LPToken} from "src/common/LPToken.sol";

/**
 * @title Test Common
 * @dev This contract is an abstract template to be reused by all the tests. NOTE: function prefixes and their usages are as follows:
 * setup = set to proper user, deploy contracts, set global variables, reset user
 * create = set to proper user, deploy contracts, reset user, return the contract
 * _create = deploy contract, return the contract
 */
abstract contract TestCommon is PythonUtils {
    address admin = address(0xad);
    address alice = address(0xa11ce);
    address bob = address(0xB0b);
    address[] ADDRESSES = [
        address(0xace),
        address(0xb0b),
        address(0xcade),
        address(0xda1e),
        address(0xe1f),
        address(0xf1ea),
        address(0x1ea),
        address(0x0af)
    ];

    GenericERC20FixedSupply public xToken;
    GenericERC20 public yToken;
    SixDecimalERC20 public stableCoin;
    TwentyTwoDecimalERC20 public highDecimalCoin;
    FeeOnTransferERC20 public fotCoin;
    LPToken public lpToken;

    AllowList deployerAllowList;
    AllowList yTokenAllowList;

    uint256 amountMinBound;
    uint16 protocolFee = 0;
    uint16 transferFee = 0;
    uint16 totalBasisPoints = 10000;
    PoolBase pool;
    IERC20 _yToken;
    uint fullToken;

    // Check if an address exists in the list
    function exists(address _address, address[] memory _addressList) public pure returns (bool) {
        for (uint256 i = 0; i < _addressList.length; i++) {
            if (_address == _addressList[i]) {
                return true;
            }
        }
        return false;
    }

    /**
     * @dev this function ensures that unique addresses can be randomly retrieved from the address array.
     */
    function getUniqueAddresses(uint256 _seed, uint8 _number) public view returns (address[] memory _addressList) {
        _addressList = new address[](ADDRESSES.length);
        // first one will simply be the seed
        _addressList[0] = ADDRESSES[_seed];
        uint256 j;
        if (_number > 1) {
            // loop until all unique addresses are returned
            for (uint256 i = 1; i < _number; i++) {
                // find the next unique address
                j = _seed;
                do {
                    j++;
                    // if end of list reached, start from the beginning
                    if (j == ADDRESSES.length) {
                        j = 0;
                    }
                    if (!exists(ADDRESSES[j], _addressList)) {
                        _addressList[i] = ADDRESSES[j];
                        break;
                    }
                } while (0 == 0);
            }
        }
        return _addressList;
    }

    /**
     * @dev Deploy and set up an ERC20
     * @param _name token name
     * @param _symbol token symbol
     * @return _token token
     */
    function _createERC20(string memory _name, string memory _symbol) internal returns (GenericERC20 _token) {
        return new GenericERC20(_name, _symbol);
    }

    function getValidExpiration() internal view returns (uint256) {
        return block.timestamp + 1;
    }
}
