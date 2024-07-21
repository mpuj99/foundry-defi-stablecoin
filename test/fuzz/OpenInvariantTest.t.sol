// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral

// 2. Getter view functions should never revert


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18; 

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract OpenInvaiantsTest is StdInvariant, Test{
    DeployDSC deployer;
    DSCEngine engine;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc; 

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        targetContract(address(engine));

    }

/*
    function invariant_protocolMustHaveMoreValueThanTotalSupplyOpen() public view  {
        // get value of all collateral in the protocol DSCEngine, so the weth and the wbtc toguether has to be allways more than the total supply od Dsc
        // compare it to all debt (dsc);
        uint256 totalSupply = dsc.totalSupply();
        uint256 totalWethDeposited = IERC20(weth).balanceOf(address(engine));
        uint256 totalWbtcDeposited = IERC20(wbtc).balanceOf(address(engine));

        uint256 storedWethValue = engine.getUsdValue(weth, totalWethDeposited);
        uint256 storedWbtcValue = engine.getUsdValue(wbtc, totalWbtcDeposited);
        console.log("weth value: ", storedWethValue);
        console.log("wbtc value: ", storedWbtcValue);
        console.log("totalSupply: ", totalSupply);

        assert(storedWethValue + storedWbtcValue >= totalSupply);


    }
*/
}