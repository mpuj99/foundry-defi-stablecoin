// What are our invariants?

// 1. The total supply of DSC should be less than the total value of collateral

// 2. Getter view functions should never revert


// Here we are going to use the handler to narrow the functions and make some sense on the calls, if not is going to keep calling functions that doesn't
// make sense, like calling redeemCollateral() function without depositing it before.


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18; 

import {Test, console} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Handler} from "./Handler.t.sol";

contract InvariantsTest is StdInvariant, Test{
    DeployDSC deployer;
    DSCEngine engine;
    HelperConfig config;
    DecentralizedStableCoin dsc;
    address weth;
    address wbtc;
    Handler handler;

    function setUp() external {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (,, weth, wbtc,) = config.activeNetworkConfig();
        //targetContract(address(engine));
        // We are going to put the target contract address  to our handler, and our handler is going to make the first or setUp calls to the DSCengine, 
        // before calling the tests below.
        handler = new Handler(engine, dsc);
        targetContract(address(handler));


    }

    /**
     * @notice This test will be called after all the functions from the handler are called and didn't revert.
     */


    function invariant_protocolMustHaveMoreValueThanTotalSupply() public view  {
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
        console.log("Times mint is called: ", handler.timesMintIsCalled());
        console.log("Times Redeem and Burn is called: ", handler.timesRedeemAndBurnIsCalled());
        console.log("Times deposit is called: ", handler.timesDepositIsCalled());

        assert(storedWethValue + storedWbtcValue >= totalSupply);


    }


    function invariant_functionsGettersShouldNeverRevert() public view {
        // engine.getAccountCollateralValue(address);
        //engine.getAccountInformation(address);
        // engine.getCollateralDepositedOfUser(address, token address);
        // engine.getDscMinted(address);
        engine.getAditionalFeedPrecision();
        engine.getCollateralTokens();
        engine.getLiquidationBonus();
        engine.getPrecision();
        




    }

}