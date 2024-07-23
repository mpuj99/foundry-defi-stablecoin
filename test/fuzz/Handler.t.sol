// Handler is going to narrow down the way we call the function

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine engine;
    DecentralizedStableCoin dsc;
    ERC20Mock weth;
    ERC20Mock wbtc;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max; // we don't put uint256 because if you put +1 is going to revert with an overflow

    uint256 public timesMintIsCalled;
    uint256 public timesDepositIsCalled;
    uint256 public timesRedeemAndBurnIsCalled;
    address[] public usersWithCollateralDeposited;
    address[] public usersWithDscMinted;
    MockV3Aggregator ethUsdPriceFeed;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _decentralizedStableCoin) {
        engine = _dscEngine;
        dsc = _decentralizedStableCoin;
        address[] memory collateralTokens = engine.getCollateralTokens();
        weth = ERC20Mock(collateralTokens[0]);
        wbtc = ERC20Mock(collateralTokens[1]);

        ethUsdPriceFeed = MockV3Aggregator(engine.getCollateralTokenPriceFeed(address(weth)));
    }

    function mintDsc(uint256 amountToMint, uint256 addressSeed) public {
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(totalDscMinted);
        if (maxDscToMint < 0) {
            return;
        }
        amountToMint = bound(amountToMint, 0, uint256(maxDscToMint));
        if (amountToMint == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.mintDsc(amountToMint);
        vm.stopPrank();
        usersWithDscMinted.push(sender);

        timesMintIsCalled++;
    }

    /**
     *
     * @param collateralSeed random fuzz number that calls _getCollateralFromSeed
     * @param amountCollateral random fuzz number
     *
     * @notice We bound the parameter collateralSeed to only pick the valid addresses(weth, wbtc) with the help of _getCollateralFromSeed() function.
     * @notice We bound the parameter amountCollateral to not be zero, as we have an applied modifier that reverts if it's zero
     */
    function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        // Bound as well the amountCollateral
        amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

        vm.startPrank(msg.sender);
        collateral.mint(msg.sender, amountCollateral);
        collateral.approve(address(engine), amountCollateral);
        engine.depositCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
        // We keep track of all the addresses are depositing collateral to then mint, because te function mint wasn't called at all, probably because it was using random
        //addresses to mint, we don't want that.
        usersWithCollateralDeposited.push(msg.sender);
        timesDepositIsCalled++;
    }

    function redeemCollateral(uint256 collateralSeed, uint256 amountCollateral, uint256 addressSeed) public {
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        if (usersWithCollateralDeposited.length == 0) {
            return;
        }
        address sender = usersWithCollateralDeposited[addressSeed % usersWithCollateralDeposited.length];
        uint256 maxAmountCollateralToRedeem = engine.getCollateralDepositedOfUser(address(collateral), sender);
        console.log("Balance of: ", maxAmountCollateralToRedeem);
        amountCollateral = bound(amountCollateral, 0, maxAmountCollateralToRedeem);
        if (amountCollateral == 0) {
            return;
        }
        vm.startPrank(sender);
        engine.redeemCollateral(address(collateral), amountCollateral);
        vm.stopPrank();
    }

    //function updateCollateralPrice(uint96 newPrice) public {
    //    int256 newPriceInt = int256(uint256(newPrice));
    //    ethUsdPriceFeed.updateAnswer(newPriceInt);
    //}

    /*
    
    function redeemCollateralAndBurn(uint256 collateralSeed, uint256 amountCollateral, uint256 addressSeed, uint256 amountToBurn) public {
        // Gets one of the collaterals tokens that we have
        ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
        ERC20Mock otherCollateral;
        // We store the other collateral token to substract to the maxAmountCollateralToRedeem
        if (collateral == weth) {
            otherCollateral = wbtc;
        } else {
            otherCollateral = weth;
        }

        // If the array of users that minted is empty we return nothing
        if (usersWithDscMinted.length == 0) {
            return;
        }
        // We are going to redeem and burn from the users that has already minted, we don't want the users that only deposit colateral.
        address sender = usersWithDscMinted[addressSeed % usersWithDscMinted.length];
        //uint256 totalCollateralOfMainToken = engine.getCollateralDepositedOfUser(sender, address(collateral));
        //if(totalCollateralOfMainToken == 0) {
        //    return;
        //}
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = engine.getAccountInformation(sender);
        
        
        //console.log("Balance of user: ", totalCollateralOfMainToken);
        console.log("DSc Minted: ", totalDscMinted);
        // Set the amount to burn
        amountToBurn = bound(amountToBurn, 0, totalDscMinted);
        if (amountToBurn == 0) {
            return;
        }
        // Calculate the DSC that are going to be left(if the case)
        uint256 dscMintedLeft = totalDscMinted - amountToBurn;
        console.log("DSC minted left: ", dscMintedLeft);
        
        // Calculate the collateral of the other token (ether)
        // uint256 totalCollateralOfOtherToken = engine.getCollateralDepositedOfUser(sender, address(otherCollateral));
        // Calculate the USD value of the collateral of the other token
        uint256 usdValueCollateralOfOtherToken = engine.getUsdValue(address(otherCollateral), engine.getCollateralDepositedOfUser(sender, address(otherCollateral)));
        console.log("USD value Collateral of OTHER token: ", usdValueCollateralOfOtherToken);
        // Calculate the USD value of the collateral of the main token
        uint256 usdValueCollateralOfMainToken = engine.getUsdValue(address(collateral), engine.getCollateralDepositedOfUser(sender, address(collateral)));
        console.log("USD value collateral of MAIN token: ", usdValueCollateralOfMainToken);
        if(usdValueCollateralOfMainToken == 0) {
            return;
        }
        //console.log("USD value on main token: ", usdValueCollateralOfMainToken);

        // Calculate the max collateral to redeem on both tokens respecting the 200% value
        //uint256 collateralToRedeemInUsdValue = collateralValueInUsd - (dscMintedLeft * 2);
        // Substract the collateral of the other token to the total collateral to redeem, to get the collateral we can redeem on the
        // main token, we set everything to int256 because the value can be negative.
        int256 collateralToRedeemUsdOfMainToken = (int256(collateralValueInUsd) - (int256(dscMintedLeft) * 2)) - int256(usdValueCollateralOfOtherToken);
        // We calculate the absolut value to see if it's bigger than the value of the main token itself
        if (engine.abs(collateralToRedeemUsdOfMainToken) > usdValueCollateralOfMainToken) {
            collateralToRedeemUsdOfMainToken = int256(usdValueCollateralOfMainToken);
        }
        console.log("Collateral to redeem of the MAIN token (USD): ", collateralToRedeemUsdOfMainToken);
        // Convert the collateral to redeem of the main token from USD to Token amount (weth or wbtc)
        uint256 maxAmountCollateralToRedeemOnMainToken = engine.getTokenAmountFromUsd(address(collateral), uint256(engine.abs(collateralToRedeemUsdOfMainToken)));
        console.log("Max collateral to redeem of MAIN token (ether): ", maxAmountCollateralToRedeemOnMainToken);
        
        
        //uint256 maxAmountCollateralToRedeem = maxAmountCollateralToRedeemOnBothTokens - totalCollateralOfOtherCollateral;

        amountCollateral = bound(amountCollateral, 0, maxAmountCollateralToRedeemOnMainToken);
        if (amountCollateral == 0){
            return;
        }
        
        vm.startPrank(sender);
        dsc.approve(address(engine), amountToBurn);
        engine.redeemCollateralForDsc(address(collateral), amountCollateral, amountToBurn);
        vm.stopPrank();
        timesRedeemAndBurnIsCalled++;
    }*/
    /*
    function burnDsc(uint256 amountToBurn, uint256 addressSeed) public {
        if (usersWithDscMinted.length == 0) {
            return;
        }
        address sender = usersWithDscMinted[addressSeed % usersWithDscMinted.length];
        (uint256 totalDscMinted,) = engine.getAccountInformation(sender);
        
        uint256 maxDscToBurn = totalDscMinted;
        console.log("DSc Minted: ", maxDscToBurn);
        amountToBurn = bound(amountToBurn, 0, maxDscToBurn);
        if (amountToBurn == 0) {
            return;
        }
        vm.startPrank(sender);
        dsc.approve(address(engine), amountToBurn);
        engine.burnDsc(amountToBurn);
        vm.stopPrank();
        timesBurnIsCalled++;

    }*/

    // Helper functions

    /**
     *
     * @param collateralSeed random fuzz number
     * @notice from the number he puts he outputs one of the valid tokens (weth, wbtc) by getting the "rest" of the division(evens == weth, odd == wbtc)
     */
    function _getCollateralFromSeed(uint256 collateralSeed) public view returns (ERC20Mock) {
        if (collateralSeed % 2 == 0) {
            return weth;
        } else {
            return wbtc;
        }
    }
}
