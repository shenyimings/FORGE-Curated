// SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.24;

// import {GasHelpers} from "test/util/gasReport/GasHelpers.sol";
// import "src/common/TBC.sol";
// import {IPool} from "src/amm/base/IPool.sol";
// import {GenericERC20} from "src/example/ERC20/GenericERC20.sol";
// import {AllowList} from "src/allowList/AllowList.sol";

// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

// import {console} from "forge-std/console.sol";
// import {Test} from "forge-std/Test.sol";


// abstract contract GasReport is GasHelpers, Test {
//     IPool[] _pools;

//     using Strings for uint256;

//     address _xToken;
//     address _yToken;
//     AllowList _yTokenAllowList;
//     AllowList _deployerAllowList;
//     uint16 _lpFee;
//     bool _liquidityRemovalAllowed;

//     uint constant XTOKEN_SUPPLY = 100_000_000_000 * 1e18;
//     uint constant YTOKEN_SUPPLY = 100_000_000_000 * 1e18;
//     uint AMOUNT_TO_SWAP;

//     function getTBCString() internal view  virtual returns (string memory name) {}
    
//     // this is to warm the slot so that the gas report is more accurate
//     function warmSlot(uint i) internal {
//         (uint minOut, , ) = _pools[i].simSwap(_yToken, AMOUNT_TO_SWAP);
//         vm.startPrank(owner());
//         _pools[i].swap(_yToken, AMOUNT_TO_SWAP, minOut, msg.sender);
//         vm.stopPrank();
//     }

//     function _setup() internal {

//         _xToken = address(new GenericERC20("xToken", "xToken"));
//         _yToken = address(new GenericERC20("yToken", "yToken"));
//         _lpFee = 20;
//         _liquidityRemovalAllowed = true;
//         _yTokenAllowList = new AllowList();
//         _deployerAllowList = new AllowList();
//         _yTokenAllowList.addToAllowList(address(_yToken));
//         _deployerAllowList.addToAllowList(msg.sender);

//         vm.startPrank(this.owner()); // deploy stuff
//         GenericERC20(_xToken).mint(address(owner()), XTOKEN_SUPPLY);
//         GenericERC20(_yToken).mint(address(owner()), YTOKEN_SUPPLY);

//         this.setYTokenAllowList(address(_yTokenAllowList));
//         this.setDeployerAllowList(address(_deployerAllowList));
//         this.proposeProtocolFeeCollector(msg.sender);
//         this.confirmProtocolFeeCollector();
//         vm.stopPrank();
//     }

//     function _setupPart2() internal {
//         vm.startPrank(owner());
//         for (uint i = 0; i < _pools.length; i++) {
//             GenericERC20(_yToken).approve(address(_pools[i]), YTOKEN_SUPPLY);
//             GenericERC20(_xToken).approve(address(_pools[i]), XTOKEN_SUPPLY);
//             _pools[i].addXSupply(XTOKEN_SUPPLY);
//             _pools[i].enableSwaps(true);
//         }
//         vm.stopPrank();
//     }

    

//     function testGasReport_swap() public {
//         string memory tbcString = getTBCString();
//         string memory toAdd = "swap";
//         for (uint i = 0; i < _pools.length; i++) {
//             string memory label = string.concat(tbcString, "_", toAdd, "_", Strings.toString(i));
//             warmSlot(i);
//             vm.startPrank(owner());
//             (uint minOut, , ) = _pools[i].simSwap(_yToken, AMOUNT_TO_SWAP);
//             startMeasuringGas(label);
//             _pools[i].swap(_yToken, AMOUNT_TO_SWAP, minOut, msg.sender);
//             uint gasUsed = stopMeasuringGas();
//             vm.stopPrank();
//             console.log(label, gasUsed);
//         }
//     }

//     function testGasReport_swapMultiplePerTransaction() public {
//         string memory tbcString = getTBCString();
//         string memory toAdd = "swapMultiplePerTransaction";
        
//         for (uint i = 0; i < _pools.length; i++) {
//             warmSlot(i);
//             IPool _pool = _pools[i];
//             string memory label = string.concat(tbcString, "_", toAdd, "_", Strings.toString(i));
//             vm.startPrank(owner());
//             GenericERC20(_yToken).approve(address(_pool), YTOKEN_SUPPLY);
//             GenericERC20(_xToken).approve(address(_pool), XTOKEN_SUPPLY);
//             startMeasuringGas(label);
//             for (uint j = 0; j < 10; j++) {
//                 if (j % 2 == 0) {
//                     (uint minOut, , ) = _pool.simSwap(_yToken, AMOUNT_TO_SWAP);
//                     _pool.swap(_yToken, AMOUNT_TO_SWAP, minOut);
//                 } else {
//                     (uint minOut, , ) = _pool.simSwap(_xToken, AMOUNT_TO_SWAP);
//                     _pool.swap(_xToken, AMOUNT_TO_SWAP, minOut);
//                 }
//             }
//             uint gasUsed = stopMeasuringGas();
//             vm.stopPrank();
//             console.log(label, gasUsed);
//         }
//     }
// }
