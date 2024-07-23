// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;


import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";
import {MockFailedMintDSC} from "../mocks/MockFailedMintDSC.sol";
import {MockFailedTransfer} from "../mocks/MockFailedTransfer.sol";
import {MockFailedTransferFrom} from "../mocks/MockFailedTransferFrom.sol";
import {MockMoreDebtDSC} from "../mocks/MockMoreDebtDSC.sol";
import {StdCheats} from "forge-std/StdCheats.sol";



contract DSCEngineTest is StdCheats, Test {
    
    event CollateralRedeemed(address indexed redeemedFrom, address indexed redeemedTo, address token, uint256 amount); // if redeemFrom != redeemedTo, then it was liquidated
    
    
    
    DeployDSC deployer;
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;
    address wbtc;
    uint256 deployerKey;
    address[] tokenAddresses;
    address[] priceFeedAddresses;

    address public USER = makeAddr("user");
    address public ALICE = makeAddr("alice");
    uint256 public amountCollateral = 10 ether;
    uint256 public amountToMint = 100 ether; // We put 100 ether but it simulates that we want to mint $100
    
    
    uint256 public constant STARTING_USER_BALANCE = 10 ether;
    uint256 public constant MIN_HEALTH_FACTOR = 1e18;
    uint256 public constant LIQUIDATION_THRESHOLD = 50;

    // Liquidation
    address public liquidator = makeAddr("liquidator");
    uint256 public collateralToCover = 20 ether;



    function setUp() public {
        deployer = new DeployDSC();
        (dsc, engine, config) = deployer.run();
        (ethUsdPriceFeed, btcUsdPriceFeed, weth, wbtc, deployerKey) = config.activeNetworkConfig();
        if (block.chainid == 31_337) {
            vm.deal(USER, STARTING_USER_BALANCE);
        }
        ERC20Mock(weth).mint(USER, STARTING_USER_BALANCE);
        ERC20Mock(wbtc).mint(USER, STARTING_USER_BALANCE);
        

    }


    function testHandlerSequenceOnOneUser() public {
        ERC20Mock(wbtc).mint(USER, 3.404e28);
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(engine), 3.404e28);
        engine.depositCollateral(wbtc, 3.404e28);
        engine.mintDsc(1.264e31);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 collateralToRedeem = (collateralValueInUsd - (totalDscMinted * 2));
        uint256 maxAmountCollateralToRedeem = engine.getTokenAmountFromUsd(wbtc, collateralToRedeem);
        dsc.approve(address(engine), 5.116e30);
        engine.redeemCollateralForDsc(wbtc, maxAmountCollateralToRedeem, 5.116e30);
        vm.stopPrank();
    }


    function testUnderflowHandler() public {
        ERC20Mock(wbtc).mint(USER, 3.404e28);
        vm.startPrank(USER);
        ERC20Mock(wbtc).approve(address(engine), 3.404e28);
        engine.depositCollateral(wbtc, 3.404e28);
        engine.mintDsc(1.264e31);
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(USER);
        uint256 collateralToRedeem = (collateralValueInUsd - (totalDscMinted * 2));
        uint256 maxAmountCollateralToRedeem = engine.getTokenAmountFromUsd(wbtc, collateralToRedeem);
        dsc.approve(address(engine), 5.116e30);
        engine.redeemCollateralForDsc(wbtc, maxAmountCollateralToRedeem, 5.116e30);
        vm.stopPrank();
    }






}