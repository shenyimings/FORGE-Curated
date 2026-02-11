// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/* solhint-disable private-vars-leading-underscore  */
/* solhint-disable func-name-mixedcase  */
/* solhint-disable var-name-mixedcase  */

import {stdStorage, StdStorage, Test} from "forge-std/Test.sol";
import {SigUtils} from "../../utils/SigUtils.sol";
import {Vm} from "forge-std/Vm.sol";
import {Utils} from "../../utils/Utils.sol";

import {MissingReturnToken} from "@solmate/src/test/utils/weird-tokens/MissingReturnToken.sol";
import {AggregatorV3Interface} from "../../../src/interfaces/AggregatorV3Interface.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {MockToken} from "../../mocks/MockToken.sol";
import {MockAToken} from "../../mocks/MockAToken.sol";
import {MockAaveV3Pool} from "../../mocks/MockAaveV3Pool.sol";
import {MockOracle} from "../../mocks/MockOracle.sol";

import {lvlUSD} from "../../../src/lvlUSD.sol";
import {IPool} from "aave-v3-core/contracts/interfaces/IPool.sol";
import {IlvlUSD} from "../../../src/interfaces/IlvlUSD.sol";
import {StakedlvlUSD} from "../../../src/StakedlvlUSD.sol";
import {AaveV3YieldManager} from "../../../src/yield/AaveV3YieldManager.sol";

import {LevelBaseReserveManager} from "../../../src/reserve/LevelBaseReserveManager.sol";
import {EigenlayerReserveManager} from "../../../src/reserve/LevelEigenlayerReserveManager.sol";
import {WrappedRebasingERC20} from "../../../src/WrappedRebasingERC20.sol";
import {ISingleAdminAccessControl} from "../../../src/interfaces/ISingleAdminAccessControl.sol";
import {IlvlUSDDefinitions} from "../../../src/interfaces/IlvlUSDDefinitions.sol";
import {ILevelBaseReserveManager} from "../../../src/interfaces/ILevelBaseReserveManager.sol";

import {LevelMinting} from "../../../src/LevelMinting.sol";

contract ReserveBaseSetup is Test, IlvlUSDDefinitions {
    Utils internal utils;
    lvlUSD internal lvlusdToken;
    StakedlvlUSD internal stakedlvlUSD;

    LevelMinting internal levelMinting;

    AaveV3YieldManager internal aaveYieldManager;
    MockAaveV3Pool internal mockAavePool;

    MockToken internal DAIToken;
    MockToken internal USDCToken;
    MissingReturnToken internal USDTToken;

    MockAToken internal aUSDC; // aUSDC
    MockAToken internal aDAI; // aUSDC

    MockOracle public mockOracle;

    WrappedRebasingERC20 internal waUSDC; // wrapped aUSDC
    WrappedRebasingERC20 internal waUSDT; // wrapped aUSDT
    WrappedRebasingERC20 internal waDAI; //wrapped DAI (18 decimals)

    EigenlayerReserveManager internal eigenlayerReserveManager;

    uint256 internal ownerPrivateKey;
    uint256 internal newOwnerPrivateKey;
    uint256 internal managerAgentPrivateKey;
    uint256 internal treasuryPrivateKey;
    uint256 internal pauserPrivateKey;
    uint256 internal minterPrivateKey;

    address internal owner;
    address internal newOwner;
    address internal managerAgent;
    address internal treasury;
    address internal pauser;
    address internal minter;

    // Roles references
    bytes32 internal adminRole = 0x00;

    function setUp() public virtual {
        utils = new Utils();

        ownerPrivateKey = 0xA11CE;
        newOwnerPrivateKey = 0xA14CE;
        managerAgentPrivateKey = 0x1DECC1;
        treasuryPrivateKey = 0x1DECC3;
        pauserPrivateKey = 0x1DECC4;
        minterPrivateKey = 0x1DECC5;

        owner = vm.addr(ownerPrivateKey);
        newOwner = vm.addr(newOwnerPrivateKey);
        managerAgent = vm.addr(managerAgentPrivateKey);
        treasury = vm.addr(treasuryPrivateKey);
        pauser = vm.addr(pauserPrivateKey);
        minter = vm.addr(minterPrivateKey);

        vm.label(owner, "owner");
        vm.label(managerAgent, "managerAgent");
        vm.label(treasury, "treasury");
        vm.label(pauser, "pauser");

        // Set the roles
        vm.startPrank(owner);

        DAIToken = new MockToken("DAI", "DAI", 18, msg.sender);
        USDCToken = new MockToken(
            "United States Dollar Coin",
            "USDC",
            6,
            msg.sender
        );
        USDTToken = new MissingReturnToken();

        lvlusdToken = new lvlUSD(address(owner));
        _setupLevelMinting();
        _setupStakedLevelUsd();

        stakedlvlUSD = new StakedlvlUSD(
            lvlusdToken,
            address(owner),
            address(owner)
        );

        lvlusdToken.setMinter(address(levelMinting));

        // set up mock aave pool proxy (which creates a mock aToken when initReserve is called)
        mockAavePool = new MockAaveV3Pool();
        mockAavePool.initReserve(address(USDCToken), "aUSDC");
        mockAavePool.initReserve(address(DAIToken), "aDAI");

        // set up aave yield manager
        aaveYieldManager = new AaveV3YieldManager(
            IPool(mockAavePool),
            address(owner)
        );
        // create ERC20 wrapper for aToken
        aUSDC = MockAToken(
            mockAavePool.getReserveData(address(USDCToken)).aTokenAddress
        );
        aDAI = MockAToken(
            mockAavePool.getReserveData(address(DAIToken)).aTokenAddress
        );
        waUSDC = new WrappedRebasingERC20(
            IERC20(address(aUSDC)),
            "waUSDC",
            "waUSDC"
        );
        waDAI = new WrappedRebasingERC20(
            IERC20(
                mockAavePool.getReserveData(address(DAIToken)).aTokenAddress
            ),
            "waDAI",
            "waDAI"
        );
        aaveYieldManager.setWrapperForToken(address(aUSDC), address(waUSDC));
        aaveYieldManager.setWrapperForToken(address(aDAI), address(waDAI));

        // set up reserve managers
        eigenlayerReserveManager = new EigenlayerReserveManager(
            IlvlUSD(address(lvlusdToken)),
            address(0),
            address(0),
            address(0),
            stakedlvlUSD,
            address(owner),
            address(owner),
            "operator1"
        );
        _setupReserveManager(eigenlayerReserveManager);

        vm.stopPrank();
    }

    function _setupReserveManager(LevelBaseReserveManager lrm) internal {
        address[] memory _reserves = new address[](1);
        _reserves[0] = address(lrm);

        uint256[] memory _ratios = new uint256[](1);
        _ratios[0] = 10000;

        levelMinting.addReserveAddress(address(lrm));
        levelMinting.setRoute(_reserves, _ratios);

        lrm.setTreasury(treasury);
        lrm.setYieldManager(address(USDCToken), address(aaveYieldManager));
        lrm.setYieldManager(address(DAIToken), address(aaveYieldManager));

        lrm.grantRole(keccak256("MANAGER_AGENT_ROLE"), address(managerAgent));
        lrm.grantRole(keccak256("PAUSER_ROLE"), pauser);
    }

    function _setupLevelMinting() internal {
        mockOracle = new MockOracle(1e8, 8); // 1:1 price ratio with 8 decimals

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10000;

        address[] memory oracles = new address[](3);
        oracles[0] = address(mockOracle);
        oracles[1] = address(mockOracle);
        oracles[2] = address(mockOracle);

        address[] memory assets = new address[](3);
        assets[0] = address(DAIToken);
        assets[1] = address(USDCToken);
        assets[2] = address(USDTToken);

        address[] memory reserves = new address[](1);
        reserves[0] = address(owner);

        uint256 _maxMintPerBlock = 1e29;
        uint256 _maxRedeemPerBlock = _maxMintPerBlock;

        levelMinting = new LevelMinting(
            IlvlUSD(address(lvlusdToken)),
            assets,
            oracles,
            reserves,
            ratios,
            owner,
            _maxMintPerBlock,
            _maxRedeemPerBlock
        );
    }

    function _setupStakedLevelUsd() internal {
        stakedlvlUSD = new StakedlvlUSD(
            lvlusdToken,
            address(owner),
            address(owner)
        );
    }

    // add this to be excluded from coverage report
    function test() public {}
}
