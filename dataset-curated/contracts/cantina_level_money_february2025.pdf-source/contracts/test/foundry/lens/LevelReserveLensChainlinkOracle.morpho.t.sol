// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.21;

import {Test, console2} from "forge-std/Test.sol";
import {Utils} from "../../utils/Utils.sol";

import {LevelReserveLens} from "../../../src/lens/LevelReserveLens.sol";
import {LevelReserveLensChainlinkOracle} from "../../../src/lens/LevelReserveLensChainlinkOracle.sol";

import {Initializable} from "@openzeppelin-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin-upgradeable/access/OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC1967Utils} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Utils.sol";
import {Upgrades} from "@openzeppelin-upgrades/src/Upgrades.sol";

import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {IMorphoChainlinkOracleV2Factory} from "../../interfaces/morpho/IMorphoChainlinkOracleV2Factory.sol";
import {IMorphoChainlinkOracleV2} from "../../interfaces/morpho/IMorphoChainlinkOracleV2.sol";
import {AggregatorV3Interface} from "../../../src/interfaces/AggregatorV3Interface.sol";

contract LevelReserveLensChainlinkOracleMorphoTest is Test {
    Utils internal utils;

    address internal owner;
    address internal random;
    uint256 internal ownerPrivateKey;
    uint256 internal randomPrivateKey;

    LevelReserveLens internal lens;
    ERC1967Proxy internal proxy;
    LevelReserveLensChainlinkOracle internal oracle;

    IERC20Metadata internal lvlusd = IERC20Metadata(0x7C1156E515aA1A2E851674120074968C905aAF37);
    IMorphoChainlinkOracleV2Factory internal morphoOracleFactory =
        IMorphoChainlinkOracleV2Factory(0x3A7bB36Ee3f3eE32A60e9f2b33c1e5f2E83ad766);
    IMorphoChainlinkOracleV2 internal morphoOracle;

    function setUp() public {
        utils = new Utils();

        ownerPrivateKey = 0xA11CE;
        randomPrivateKey = 0x1CE;

        owner = vm.addr(ownerPrivateKey);
        random = vm.addr(randomPrivateKey);

        // Setup forked environment.
        string memory rpcKey = "MAINNET_RPC_URL";
        utils.startFork(rpcKey, 21790575);

        vm.startPrank(owner);

        LevelReserveLens implementation = new LevelReserveLens();

        proxy = new ERC1967Proxy(
            address(implementation), abi.encodeWithSelector(LevelReserveLens.initialize.selector, owner)
        );

        lens = LevelReserveLens(address(proxy));
        oracle = new LevelReserveLensChainlinkOracle(owner, owner, address(lens));

        morphoOracle = morphoOracleFactory.createMorphoChainlinkOracleV2(
            IERC4626(address(0)),
            1,
            oracle,
            AggregatorV3Interface(address(0)),
            lvlusd.decimals(),
            IERC4626(address(0)),
            1,
            AggregatorV3Interface(address(0)),
            AggregatorV3Interface(address(0)),
            6,
            ""
        );
        vm.stopPrank();
    }

    function test_Success() public {
        uint256 price = morphoOracle.price();

        /// From Morpho docs: Returns the price of 1 asset of collateral token quoted in 1 asset of loan token, scaled by 1e36.
        /// It corresponds to the price of 10**(collateral token decimals) assets of collateral token quoted in
        /// 10**(loan token decimals) assets of loan token with `36 + loan token decimals - collateral token decimals` decimals of precision.
        /// Loan token is USDC (6 decimals) and collateral token is lvlUSD (18 decimals).
        assertEq(10 ** (36 + 6 - 18), int256(price));
    }
}
