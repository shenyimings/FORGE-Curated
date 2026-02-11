// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

/* solhint-disable func-name-mixedcase  */

import "../LevelMinting.utils.sol";
import {console2} from "forge-std/console2.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract LevelMintingCoreTest is LevelMintingUtils {
    function setUp() public override {
        super.setUp();
        // Add oracle for DAI
        vm.prank(owner);
        LevelMintingContract.addOracle(address(DAIToken), address(mockOracle));
    }

    function test__mint() public {
        executeMint();
    }

    function test_redeem() public {
        executeRedeem();
        assertEq(
            DAIToken.balanceOf(address(LevelMintingContract)),
            0,
            "Mismatch in DAI balance"
        );
        assertEq(
            DAIToken.balanceOf(beneficiary),
            _DAIToDeposit,
            "Mismatch in DAI balance"
        );
        assertEq(
            lvlusdToken.balanceOf(beneficiary),
            0,
            "Mismatch in lvlUSD balance"
        );
    }

    function test_initiate_and_complete_redeem() public {
        vm.prank(owner);
        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);
        ILevelMinting.Order memory redeemOrder = redeem_setup(
            50 wei,
            50 wei,
            false,
            address(DAIToken)
        );
        vm.prank(owner);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();

        (, ILevelMinting.Route memory route) = mint_setup(
            500 wei,
            500 wei,
            false,
            address(DAIToken)
        );
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            lvlusd_amount: 5000 wei,
            collateral_amount: 50 wei
        });
        DAIToken.mint(50000 wei, beneficiary);
        LevelMintingContract.__mint(order, route);

        vm.startPrank(beneficiary);
        LevelMintingContract.initiateRedeem(redeemOrder);
        vm.warp(10 days);
        uint bal = DAIToken.balanceOf(beneficiary);
        LevelMintingContract.completeRedeem(redeemOrder.collateral_asset);
        uint new_val = DAIToken.balanceOf(beneficiary);
        assertEq(new_val - bal, 50 wei);
        vm.stopPrank();
    }

    function test_fuzz_initiate_and_complete_redeem(
        uint256 mintAmount,
        uint256 collateralAmount,
        uint64 mintNonce,
        uint16 daysToWait
    ) public {
        collateralAmount = bound(collateralAmount, 1, 1e10);
        mintAmount = bound(mintAmount, collateralAmount, 1e15);
        uint256 lvlusdAmount = collateralAmount;
        daysToWait = uint16(bound(daysToWait, 10, 30)); // Between 1 and 30 days
        mintNonce = uint64(bound(mintNonce, 1, 1000));

        vm.startPrank(benefactor);
        DAIToken.approve(address(LevelMintingContract), collateralAmount);
        vm.stopPrank();

        vm.startPrank(benefactor);
        lvlusdToken.approve(address(LevelMintingContract), lvlusdAmount);
        vm.stopPrank();

        vm.startPrank(beneficiary);
        DAIToken.approve(address(LevelMintingContract), collateralAmount);
        vm.stopPrank();

        vm.startPrank(beneficiary);
        lvlusdToken.approve(address(LevelMintingContract), lvlusdAmount);
        vm.stopPrank();

        vm.startPrank(redeemer);
        DAIToken.approve(address(LevelMintingContract), collateralAmount);
        vm.stopPrank();

        vm.startPrank(owner);
        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);

        ILevelMinting.Order memory redeemOrder = redeem_setup(
            lvlusdAmount,
            collateralAmount,
            false,
            address(DAIToken)
        );

        vm.prank(owner);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();

        (, ILevelMinting.Route memory route) = mint_setup(
            lvlusdAmount,
            collateralAmount,
            false,
            address(DAIToken)
        );

        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            lvlusd_amount: lvlusdAmount,
            collateral_amount: collateralAmount
        });

        DAIToken.mint(mintAmount * 1000, beneficiary); // Mint enough for the test
        LevelMintingContract.__mint(order, route);

        vm.startPrank(beneficiary);
        LevelMintingContract.initiateRedeem(redeemOrder);

        vm.warp(daysToWait * 1 days);

        uint256 balBefore = DAIToken.balanceOf(beneficiary);
        LevelMintingContract.completeRedeem(redeemOrder.collateral_asset);
        uint256 balAfter = DAIToken.balanceOf(beneficiary);

        assertEq(
            balAfter - balBefore,
            collateralAmount,
            "Incorrect redeem amount"
        );
        vm.stopPrank();
    }

    function test_initiate_and_complete_redeem_stablecoin_depeg_price_above_unit()
        public
    {
        vm.startPrank(owner);

        // assume stablecoin price is > 1, so when you burn lvlusd, you
        // get less stablecoins back
        mockOracle.updatePriceAndDecimals(1099, 3);

        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);
        ILevelMinting.Order memory redeemOrder = redeem_setup(
            50 wei,
            40 wei,
            false,
            address(DAIToken)
        );
        vm.prank(owner);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();

        (, ILevelMinting.Route memory route) = mint_setup(
            500 wei,
            500 wei,
            false,
            address(DAIToken)
        );
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            lvlusd_amount: 5000 wei,
            collateral_amount: 50 wei
        });
        DAIToken.mint(50000 wei, beneficiary);
        LevelMintingContract.__mint(order, route);

        vm.startPrank(beneficiary);
        LevelMintingContract.initiateRedeem(redeemOrder);
        vm.warp(10 days);
        uint bal = DAIToken.balanceOf(beneficiary);
        LevelMintingContract.completeRedeem(redeemOrder.collateral_asset);
        uint new_val = DAIToken.balanceOf(beneficiary);
        assertLt(new_val - bal, 50 wei);
        vm.stopPrank();
    }

    function test_initiate_and_complete_redeem_stablecoin_depeg_price_below_unit()
        public
    {
        vm.startPrank(owner);

        // assume stablecoin price is < 1, so when you burn lvlusd, you
        // get the same amount of
        mockOracle.updatePriceAndDecimals(995, 3);

        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);
        ILevelMinting.Order memory redeemOrder = redeem_setup(
            50 wei,
            50 wei,
            false,
            address(DAIToken)
        );
        vm.prank(owner);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();

        (, ILevelMinting.Route memory route) = mint_setup(
            500 wei,
            500 wei,
            false,
            address(DAIToken)
        );
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            lvlusd_amount: 5000 wei,
            collateral_amount: 50 wei
        });
        DAIToken.mint(50000 wei, beneficiary);
        LevelMintingContract.__mint(order, route);

        vm.startPrank(beneficiary);
        LevelMintingContract.initiateRedeem(redeemOrder);
        vm.warp(10 days);
        uint bal = DAIToken.balanceOf(beneficiary);
        LevelMintingContract.completeRedeem(redeemOrder.collateral_asset);
        uint new_val = DAIToken.balanceOf(beneficiary);
        assertEq(new_val - bal, 50 wei);
        vm.stopPrank();
    }

    function test_initiate_and_complete_redeem_min_collateral_not_met_revert()
        public
    {
        vm.prank(owner);
        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);
        ILevelMinting.Order memory redeemOrder = redeem_setup(
            50 wei,
            51 wei,
            false,
            address(DAIToken)
        );
        vm.prank(owner);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();
        (, ILevelMinting.Route memory route) = mint_setup(
            500 wei,
            500 wei,
            false,
            address(DAIToken)
        );
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            lvlusd_amount: 5000 wei,
            collateral_amount: 50 wei
        });
        DAIToken.mint(50000 wei, beneficiary);
        LevelMintingContract.__mint(order, route);

        vm.startPrank(beneficiary);
        LevelMintingContract.initiateRedeem(redeemOrder);
        vm.warp(10 days);
        uint bal = DAIToken.balanceOf(beneficiary);
        vm.expectRevert(MinimumCollateralAmountNotMet);
        LevelMintingContract.completeRedeem(redeemOrder.collateral_asset);
        vm.stopPrank();
    }

    function test__usdc__mintMinLvlUSDAmountNotMetRevert(
        uint mintDollarAmount,
        uint lvlUSDDollarAmount,
        int mockOraclePriceDeviationBps
    ) public {
        vm.assume(mintDollarAmount >= 1);
        vm.assume(mintDollarAmount < 1e9);
        vm.assume(mockOraclePriceDeviationBps > -2000);
        // we only consider mockOraclePriceDeviationBps values < 0, because in the positive
        // deviation case, the multiplier for lvlUSDDollarAmount will be capped at 1
        vm.assume(mockOraclePriceDeviationBps < 0);
        vm.assume(lvlUSDDollarAmount < 1e10);
        vm.assume(
            lvlUSDDollarAmount >
                (mintDollarAmount * uint(1e4 + mockOraclePriceDeviationBps)) /
                    1e4
        );
        mockOracle.updatePriceAndDecimals(
            int((1e8 * (1e4 + mockOraclePriceDeviationBps)) / 1e4),
            mockOracle.decimals()
        );
        _test_mint_min_lvlusd_amount_not_met_revert(
            USDCToken,
            address(mockOracle),
            mintDollarAmount,
            lvlUSDDollarAmount
        );
    }

    function test__dai__mintMinLvlUSDAmountNotMetRevert(
        uint mintDollarAmount,
        uint lvlUSDDollarAmount,
        int mockOraclePriceDeviationBps
    ) public {
        vm.assume(mintDollarAmount >= 1);
        vm.assume(mintDollarAmount < 1e9);
        vm.assume(mockOraclePriceDeviationBps > -2000);
        // we only consider mockOraclePriceDeviationBps values < 0, because in the positive
        // deviation case, the multiplier for lvlUSDDollarAmount will be capped at 1
        vm.assume(mockOraclePriceDeviationBps < 0);
        vm.assume(lvlUSDDollarAmount < 1e10);
        vm.assume(
            lvlUSDDollarAmount >
                (mintDollarAmount * uint(1e4 + mockOraclePriceDeviationBps)) /
                    1e4
        );
        mockOracle.updatePriceAndDecimals(
            int((1e8 * (1e4 + mockOraclePriceDeviationBps)) / 1e4),
            mockOracle.decimals()
        );
        _test_mint_min_lvlusd_amount_not_met_revert(
            DAIToken,
            address(mockOracle),
            mintDollarAmount,
            lvlUSDDollarAmount
        );
    }

    function test__usdc__mintLvlUSD(
        uint mintDollarAmount,
        uint lvlUSDDollarAmount,
        int mockOraclePriceDeviationBps
    ) public {
        vm.assume(mintDollarAmount >= 1);
        vm.assume(mintDollarAmount < 1e9);
        vm.assume(mockOraclePriceDeviationBps > -2000);
        // we only consider mockOraclePriceDeviationBps values < 0, because in the positive
        // deviation case, the multiplier for lvlUSDDollarAmount will be capped at 1
        vm.assume(mockOraclePriceDeviationBps < 0);
        vm.assume(lvlUSDDollarAmount < 1e18);
        uint newOraclePrice = uint(
            (1e8 * (1e4 + mockOraclePriceDeviationBps)) / 1e4
        );
        // we multiple the LHS and RHS by 1e18 to make sure that the statement is not true because of rounding errors
        vm.assume(
            (1e18 * mintDollarAmount * newOraclePrice) / 1e8 >=
                1e18 * lvlUSDDollarAmount
        );
        vm.assume(lvlUSDDollarAmount > 0);
        mockOracle.updatePriceAndDecimals(
            int(newOraclePrice),
            mockOracle.decimals()
        );
        _test_mint_lvlusd(
            USDCToken,
            address(mockOracle),
            mintDollarAmount,
            lvlUSDDollarAmount
        );
    }

    function test__dai__mintLvlUSD(
        uint mintDollarAmount,
        uint lvlUSDDollarAmount,
        int mockOraclePriceDeviationBps
    ) public {
        vm.assume(mintDollarAmount >= 1);
        vm.assume(mintDollarAmount < 1e8);
        vm.assume(mockOraclePriceDeviationBps > -2000);
        // we only consider mockOraclePriceDeviationBps values < 0, because in the positive
        // deviation case, the multiplier for lvlUSDDollarAmount will be capped at 1
        vm.assume(mockOraclePriceDeviationBps < 0);
        vm.assume(lvlUSDDollarAmount < 1e10);
        uint newOraclePrice = uint(
            (1e8 * (1e4 + mockOraclePriceDeviationBps)) / 1e4
        );
        // we multiple the LHS and RHS by 1e18 to make sure that the statement is not true because of rounding errors
        vm.assume(
            (1e18 * mintDollarAmount * newOraclePrice) / 1e8 >=
                1e18 * lvlUSDDollarAmount
        );
        vm.assume(lvlUSDDollarAmount > 0);
        mockOracle.updatePriceAndDecimals(
            int(newOraclePrice),
            mockOracle.decimals()
        );
        _test_mint_lvlusd(
            DAIToken,
            address(mockOracle),
            mintDollarAmount,
            lvlUSDDollarAmount
        );
    }

    function _normalizeAmount(
        uint amount,
        address token
    ) public returns (uint) {
        uint8 decimals = ERC20(address(token)).decimals();
        return amount * (10 ** decimals);
    }

    function _test_mint_min_lvlusd_amount_not_met_revert(
        MockToken token,
        address oracle,
        uint mintDollarAmount,
        uint lvlUSDDollarAmount
    ) public {
        vm.startPrank(owner);
        LevelMintingContract.addOracle(address(token), oracle);
        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();
        (, ILevelMinting.Route memory route) = mint_setup(
            50 ether,
            50 ether,
            false,
            address(token)
        );
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(token),
            lvlusd_amount: _normalizeAmount(
                lvlUSDDollarAmount,
                address(lvlusdToken)
            ),
            collateral_amount: _normalizeAmount(
                mintDollarAmount,
                address(token)
            )
        });
        token.mint(500 ether, beneficiary);
        token.mint(500 ether, benefactor);

        vm.startPrank(order.benefactor);
        vm.expectRevert(MinimumlvlUSDAmountNotMet);
        LevelMintingContract.mint(order, route);
        vm.stopPrank();
    }

    function _test_mint_lvlusd(
        MockToken token,
        address oracle,
        uint mintDollarAmount,
        uint lvlUSDDollarAmount
    ) public {
        vm.startPrank(owner);
        LevelMintingContract.addOracle(address(token), oracle);
        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();
        (, ILevelMinting.Route memory route) = mint_setup(
            500000000 ether,
            500000000 ether,
            false,
            address(token)
        );
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(token),
            lvlusd_amount: _normalizeAmount(
                lvlUSDDollarAmount,
                address(lvlusdToken)
            ),
            collateral_amount: _normalizeAmount(
                mintDollarAmount,
                address(token)
            )
        });
        token.mint(5000000000000000000000000000000 ether, beneficiary);
        token.mint(5000000000000000000000000000000 ether, benefactor);

        vm.startPrank(order.benefactor);
        // note: we calculate balances of "beneficiary" both before and after
        //       because that account is used as the benefactor of the mint order
        uint beneficiaryBalBefore = ERC20(token).balanceOf(beneficiary);
        uint reserveBalBefore = ERC20(token).balanceOf(
            address(LevelMintingContract)
        );
        uint lvlusdTokenSupplyBefore = lvlusdToken.totalSupply();
        LevelMintingContract.mint(order, route);
        uint reserveBalAfter = ERC20(token).balanceOf(
            address(LevelMintingContract)
        );
        assertEq(
            reserveBalAfter - reserveBalBefore,
            _normalizeAmount(mintDollarAmount, address(token))
        );
        assertEq(
            beneficiaryBalBefore - ERC20(token).balanceOf(beneficiary),
            _normalizeAmount(mintDollarAmount, address(token))
        );

        // check that (dollar value of reserves) == (dollar value of lvlUSD in circulation)
        // note that we are checking for strict equality, rather than over-collateralization,
        // because this also tests that the minted amount of lvlUSD is correct
        _checkSolvency(
            address(token),
            address(LevelMintingContract),
            oracle,
            true
        );
        vm.stopPrank();
    }

    // check solvency of protocol, assuming that reserves are all stored in a single address
    function _checkSolvency(
        address collateral,
        address reserve,
        address oracle,
        bool checkEquality // check equality of reserve value and outstanding lvlUSD value
    ) public {
        int _price;
        (, _price, , , ) = MockOracle(oracle).latestRoundData();
        uint collateralDecimals = ERC20(collateral).decimals();
        uint reserveBal = ERC20(collateral).balanceOf(address(reserve));
        // calculate the reserve value scaled up by the difference in decimals
        // between lvlUSD and collateral asset
        uint scaledReserveValue = (10 ** (18 - collateralDecimals) *
            reserveBal *
            uint(_price)) / (10 ** MockOracle(oracle).decimals());
        if (checkEquality) {
            // this is a strict equality check
            assertEq(scaledReserveValue, lvlusdToken.totalSupply());
        } else {
            // check that protocol is fully collateralized
            assertGe(scaledReserveValue, lvlusdToken.totalSupply());
        }
    }

    function test_initiate_and_complete_redeem_insufficient_cooldown_revert()
        public
    {
        vm.prank(owner);
        LevelMintingContract.setMaxRedeemPerBlock(type(uint256).max);
        ILevelMinting.Order memory redeemOrder = redeem_setup(
            50 wei,
            50 wei,
            false,
            address(DAIToken)
        );
        (, ILevelMinting.Route memory route) = mint_setup(
            50 wei,
            50 wei,
            false,
            address(DAIToken)
        );
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: beneficiary,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            lvlusd_amount: 50 wei,
            collateral_amount: 50 wei
        });
        DAIToken.mint(50 wei, beneficiary);
        LevelMintingContract.__mint(order, route);

        vm.prank(owner);
        LevelMintingContract.grantRole(redeemerRole, beneficiary);
        vm.stopPrank();
        vm.startPrank(beneficiary);
        LevelMintingContract.initiateRedeem(redeemOrder);
        vm.warp(6 days); // not enough time as passed!
        vm.expectRevert(InvalidCooldown);
        LevelMintingContract.completeRedeem(redeemOrder.collateral_asset);
        vm.stopPrank();
    }

    function test_dai_withdraw() public {
        vm.deal(address(LevelMintingContract), _DAIToDeposit);

        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: benefactor,
            beneficiary: benefactor,
            collateral_asset: address(DAIToken),
            collateral_amount: _DAIToDeposit,
            lvlusd_amount: _lvlusdToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(LevelMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        ILevelMinting.Route memory route = ILevelMinting.Route({
            addresses: targets,
            ratios: ratios
        });

        // taker
        vm.startPrank(benefactor);
        DAIToken.approve(address(LevelMintingContract), _DAIToDeposit);

        vm.stopPrank();

        assertEq(lvlusdToken.balanceOf(benefactor), 0);

        vm.recordLogs();
        vm.prank(minter);
        LevelMintingContract.__mint(order, route);
        vm.getRecordedLogs();

        assertEq(lvlusdToken.balanceOf(benefactor), _lvlusdToMint);

        //redeem
        ILevelMinting.Order memory redeemOrder = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.REDEEM,
            benefactor: benefactor,
            beneficiary: benefactor,
            collateral_asset: address(DAIToken),
            lvlusd_amount: _lvlusdToMint,
            collateral_amount: _DAIToDeposit
        });

        // taker
        vm.startPrank(benefactor);
        lvlusdToken.approve(address(LevelMintingContract), _lvlusdToMint);

        vm.stopPrank();

        vm.startPrank(redeemer);
        LevelMintingContract.__redeem(redeemOrder);

        assertEq(DAIToken.balanceOf(benefactor), _DAIToDeposit);
        assertEq(lvlusdToken.balanceOf(benefactor), 0);

        vm.stopPrank();
    }

    function test_fuzz_mint_noSlippage(uint256 expectedAmount) public {
        vm.assume(expectedAmount > 0 && expectedAmount < _maxMintPerBlock);
        (
            ILevelMinting.Order memory order,
            ILevelMinting.Route memory route
        ) = mint_setup(expectedAmount, _DAIToDeposit, false, address(DAIToken));

        vm.recordLogs();
        LevelMintingContract.__mint(order, route);
        vm.getRecordedLogs();
        assertEq(DAIToken.balanceOf(benefactor), 0);
        assertEq(
            DAIToken.balanceOf(address(LevelMintingContract)),
            _DAIToDeposit
        );
        assertEq(lvlusdToken.balanceOf(beneficiary), expectedAmount);
    }

    function test_multipleValid_reserveRatios_addresses() public {
        uint256 _smallLvlUsdToMint = 1.75 * 10 ** 23;
        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            collateral_amount: _DAIToDeposit,
            lvlusd_amount: _smallLvlUsdToMint
        });

        address[] memory targets = new address[](3);
        targets[0] = address(LevelMintingContract);
        targets[1] = reserve1;
        targets[2] = reserve2;

        uint256[] memory ratios = new uint256[](3);
        ratios[0] = 3_000;
        ratios[1] = 4_000;
        ratios[2] = 3_000;

        ILevelMinting.Route memory route = ILevelMinting.Route({
            addresses: targets,
            ratios: ratios
        });

        // taker
        vm.startPrank(benefactor);
        DAIToken.approve(address(LevelMintingContract), _DAIToDeposit);

        vm.stopPrank();

        assertEq(DAIToken.balanceOf(benefactor), _DAIToDeposit);

        vm.prank(minter);
        vm.expectRevert(InvalidRoute);
        LevelMintingContract.__mint(order, route);

        vm.prank(owner);
        LevelMintingContract.addReserveAddress(reserve2);

        vm.prank(minter);
        LevelMintingContract.__mint(order, route);

        assertEq(DAIToken.balanceOf(benefactor), 0);
        assertEq(lvlusdToken.balanceOf(beneficiary), _smallLvlUsdToMint);

        assertEq(
            DAIToken.balanceOf(address(reserve1)),
            (_DAIToDeposit * 4) / 10
        );
        assertEq(
            DAIToken.balanceOf(address(reserve2)),
            (_DAIToDeposit * 3) / 10
        );
        assertEq(
            DAIToken.balanceOf(address(LevelMintingContract)),
            (_DAIToDeposit * 3) / 10
        );

        // remove reserve and expect reversion
        vm.prank(owner);
        LevelMintingContract.removeReserveAddress(reserve2);

        vm.prank(minter);
        vm.expectRevert(InvalidRoute);
        LevelMintingContract.__mint(order, route);
    }

    function test_fuzz_multipleInvalid_reserveRatios_revert(
        uint256 ratio1
    ) public {
        ratio1 = bound(ratio1, 0, UINT256_MAX - 7_000);
        vm.assume(ratio1 != 3_000);

        ILevelMinting.Order memory mintOrder = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            collateral_amount: _DAIToDeposit,
            lvlusd_amount: _lvlusdToMint
        });

        address[] memory targets = new address[](2);
        targets[0] = address(LevelMintingContract);
        targets[1] = owner;

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = ratio1;
        ratios[1] = 7_000;

        ILevelMinting.Route memory route = ILevelMinting.Route({
            addresses: targets,
            ratios: ratios
        });

        vm.startPrank(benefactor);
        DAIToken.approve(address(LevelMintingContract), _DAIToDeposit);

        vm.stopPrank();

        assertEq(DAIToken.balanceOf(benefactor), _DAIToDeposit);

        vm.expectRevert(InvalidRoute);
        vm.prank(minter);
        LevelMintingContract.__mint(mintOrder, route);

        assertEq(DAIToken.balanceOf(benefactor), _DAIToDeposit);
        assertEq(lvlusdToken.balanceOf(beneficiary), 0);

        assertEq(DAIToken.balanceOf(address(LevelMintingContract)), 0);
        assertEq(DAIToken.balanceOf(owner), 0);
    }

    function test_fuzz_singleInvalid_reserveRatio_revert(
        uint256 ratio1
    ) public {
        vm.assume(ratio1 != 10_000);

        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            collateral_amount: _DAIToDeposit,
            lvlusd_amount: _lvlusdToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(LevelMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = ratio1;

        ILevelMinting.Route memory route = ILevelMinting.Route({
            addresses: targets,
            ratios: ratios
        });

        // taker
        vm.startPrank(benefactor);
        DAIToken.approve(address(LevelMintingContract), _DAIToDeposit);

        vm.stopPrank();

        assertEq(DAIToken.balanceOf(benefactor), _DAIToDeposit);

        vm.expectRevert(InvalidRoute);
        vm.prank(minter);
        LevelMintingContract.__mint(order, route);

        assertEq(DAIToken.balanceOf(benefactor), _DAIToDeposit);
        assertEq(lvlusdToken.balanceOf(beneficiary), 0);

        assertEq(DAIToken.balanceOf(address(LevelMintingContract)), 0);
    }

    function test_unsupported_assets_ERC20_revert() public {
        vm.startPrank(owner);
        LevelMintingContract.removeSupportedAsset(address(DAIToken));
        DAIToken.mint(_DAIToDeposit, benefactor);
        vm.stopPrank();

        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(DAIToken),
            collateral_amount: _DAIToDeposit,
            lvlusd_amount: _lvlusdToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(LevelMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        ILevelMinting.Route memory route = ILevelMinting.Route({
            addresses: targets,
            ratios: ratios
        });

        // taker
        vm.startPrank(benefactor);
        DAIToken.approve(address(LevelMintingContract), _DAIToDeposit);

        vm.stopPrank();

        vm.recordLogs();
        vm.expectRevert(UnsupportedAsset);
        vm.prank(minter);
        LevelMintingContract.__mint(order, route);
        vm.getRecordedLogs();
    }

    function test_unsupported_assets_ETH_revert() public {
        vm.startPrank(owner);
        vm.deal(benefactor, _DAIToDeposit);
        vm.stopPrank();

        ILevelMinting.Order memory order = ILevelMinting.Order({
            order_type: ILevelMinting.OrderType.MINT,
            benefactor: benefactor,
            beneficiary: beneficiary,
            collateral_asset: address(token),
            collateral_amount: _DAIToDeposit,
            lvlusd_amount: _lvlusdToMint
        });

        address[] memory targets = new address[](1);
        targets[0] = address(LevelMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        ILevelMinting.Route memory route = ILevelMinting.Route({
            addresses: targets,
            ratios: ratios
        });

        // taker
        vm.startPrank(benefactor);
        DAIToken.approve(address(LevelMintingContract), _DAIToDeposit);

        vm.stopPrank();

        vm.recordLogs();
        vm.expectRevert(UnsupportedAsset);
        vm.prank(minter);
        LevelMintingContract.__mint(order, route);
        vm.getRecordedLogs();
    }

    function test_add_and_remove_supported_asset() public {
        address asset = address(20);
        vm.expectEmit(true, false, false, false);
        emit AssetAdded(asset);
        vm.startPrank(owner);
        LevelMintingContract.addSupportedAsset(asset);
        assertTrue(LevelMintingContract.isSupportedAsset(asset));

        vm.expectEmit(true, false, false, false);
        emit AssetRemoved(asset);
        LevelMintingContract.removeSupportedAsset(asset);
        assertFalse(LevelMintingContract.isSupportedAsset(asset));
    }

    function test_cannot_add_asset_already_supported_revert() public {
        address asset = address(20);
        vm.expectEmit(true, false, false, false);
        emit AssetAdded(asset);
        vm.startPrank(owner);
        LevelMintingContract.addSupportedAsset(asset);
        assertTrue(LevelMintingContract.isSupportedAsset(asset));

        vm.expectRevert(InvalidAssetAddress);
        LevelMintingContract.addSupportedAsset(asset);
    }

    function test_cannot_removeAsset_not_supported_revert() public {
        address asset = address(20);
        assertFalse(LevelMintingContract.isSupportedAsset(asset));

        vm.prank(owner);
        vm.expectRevert(InvalidAssetAddress);
        LevelMintingContract.removeSupportedAsset(asset);
    }

    function test_cannotAdd_addressZero_revert() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAssetAddress);
        LevelMintingContract.addSupportedAsset(address(0));
    }

    function test_cannotAdd_lvlUSD_revert() public {
        vm.prank(owner);
        vm.expectRevert(InvalidAssetAddress);
        LevelMintingContract.addSupportedAsset(address(lvlusdToken));
    }

    function test_sending_redeem_order_to_mint_revert() public {
        ILevelMinting.Order memory order = redeem_setup(
            1 ether,
            50 ether,
            false,
            address(DAIToken)
        );

        address[] memory targets = new address[](1);
        targets[0] = address(LevelMintingContract);

        uint256[] memory ratios = new uint256[](1);
        ratios[0] = 10_000;

        ILevelMinting.Route memory route = ILevelMinting.Route({
            addresses: targets,
            ratios: ratios
        });

        vm.expectRevert(InvalidOrder);
        vm.prank(minter);
        LevelMintingContract.__mint(order, route);
    }

    function test_mismatchedAddressesAndRatios_revert() public {
        uint256 _smallLvlUsdToMint = 1.75 * 10 ** 23;
        (
            ILevelMinting.Order memory order,
            ILevelMinting.Route memory route
        ) = mint_setup(
                _smallLvlUsdToMint,
                _DAIToDeposit,
                false,
                address(DAIToken)
            );

        address[] memory targets = new address[](3);
        targets[0] = address(LevelMintingContract);
        targets[1] = reserve1;
        targets[2] = reserve2;

        uint256[] memory ratios = new uint256[](2);
        ratios[0] = 3_000;
        ratios[1] = 4_000;

        route = ILevelMinting.Route({addresses: targets, ratios: ratios});

        vm.recordLogs();
        vm.prank(minter);
        vm.expectRevert(InvalidRoute);
        LevelMintingContract.__mint(order, route);
    }

    function testRecoverTokensFromWrappedRebasingErc20() public {
        vm.startPrank(owner);
        // mint non-underlying token to a wrapped rebasing ERC20 contract
        DAIToken.mint(1000, address(waUSDC));
        waUSDC.transferERC20(address(DAIToken), bob, 999);
        assertEq(DAIToken.balanceOf(bob), 999);
        assertEq(DAIToken.balanceOf(address(waUSDC)), 1);
    }

    function testRecoverETHFromWrappedRebasingErc20() public {
        vm.startPrank(owner);

        // mint ETH to the wrapped rebasing ERC20 contract
        vm.deal(address(waUSDC), 100 ether);

        // verify initial ETH balances
        assertEq(address(waUSDC).balance, 100 ether);
        assertEq(bob.balance, 0);

        // recover ETH to bob
        waUSDC.transferEth(payable(bob), 100 ether);

        // verify final ETH balances
        assertEq(address(waUSDC).balance, 0);
        assertEq(bob.balance, 100 ether);

        vm.stopPrank();
    }
}
