// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./kpkShares.TestBase.sol";

/// @notice Example test contract demonstrating the parameterized test framework
/// @dev This shows how to use the framework to test scenarios across multiple configurations
contract kpkSharesParameterizedExampleTest is kpkSharesTestBase {
    /// @notice Example: Test fee charging across all relevant configurations automatically
    /// @dev This single test will run across multiple configurations (zero fees, boundary conditions, etc.)
    function testFeeChargingAcrossConfigurations() public {
        // Run fee charging scenario with automatically generated relevant configurations
        runScenario(TestScenario.FEE_CHARGING);
    }

    /// @notice Example: Test fee rounding with specific amounts
    function testFeeRoundingWithSmallAmounts() public {
        uint256[] memory testParams = new uint256[](1);
        testParams[0] = 1; // Test with 1 wei to trigger rounding
        runScenario(TestScenario.FEE_ROUNDING, testParams);
    }

    /// @notice Example: Test boundary conditions (MIN_TIME_ELAPSED, etc.)
    function testBoundaryConditions() public {
        runScenario(TestScenario.BOUNDARY_CONDITIONS);
    }

    /// @notice Example: Test zero values across all zero-value configurations
    function testZeroValues() public {
        runScenario(TestScenario.ZERO_VALUES);
    }

    /// @notice Example: Test all conditional combinations
    function testConditionalCombinations() public {
        runScenario(TestScenario.CONDITIONAL_COMBINATIONS);
    }

    /// @notice Example: Test with custom preset configurations
    function testWithCustomPresets() public {
        ConfigPreset[] memory presets = new ConfigPreset[](3);
        presets[0] = ConfigPreset.ZERO_FEES;
        presets[1] = ConfigPreset.MIN_TIME_ELAPSED;
        presets[2] = ConfigPreset.NO_PERF_MODULE;

        uint256[] memory testParams = new uint256[](1);
        testParams[0] = _sharesAmount(1000);

        runScenarioWithPresets(TestScenario.FEE_CHARGING, presets, testParams);
    }

    /// @notice Example: Test with completely custom configurations
    function testWithCustomConfigs() public {
        TestConfig[] memory configs = new TestConfig[](2);

        // Custom config 1: Very small fees that might round to zero
        configs[0] = createCustomConfig(
            1, // 0.01% management fee
            1, // 0.01% redemption fee
            1, // 0.01% performance fee
            address(perfFeeModule),
            MIN_TIME_ELAPSED + 1,
            _usdcAmount(1), // Very small amount
            _sharesAmount(1), // Very small amount
            "Minimal fees and amounts"
        );

        // Custom config 2: Zero fees with normal amounts
        configs[1] = createCustomConfig(
            0,
            0,
            0,
            address(0),
            MIN_TIME_ELAPSED + 1 hours,
            _usdcAmount(1000),
            _sharesAmount(1000),
            "Zero fees, normal amounts"
        );

        uint256[] memory testParams = new uint256[](0);
        runScenarioWithConfigs(TestScenario.FEE_CHARGING, configs, testParams);
    }
}

