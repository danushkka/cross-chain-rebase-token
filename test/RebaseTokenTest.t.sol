// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {Vault} from "../src/Vault.sol";
import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract RebaseTokenTest is Test {
    ////////////////////////////////////
    ///////// STATE VARIABLES //////////
    ////////////////////////////////////

    RebaseToken private rebaseToken;
    Vault private vault;

    address private owner = makeAddr("owner");
    address private user = makeAddr("user");

    uint256 private constant MIN_AMOUNT = 1e5;
    uint256 private constant STARTING_BALANCE = 1e18;
    uint256 private constant INITIAL_INITEREST_RATE = 3e9;
    uint256 private constant PRECISION = 1e18;

    ////////////////////////////////////
    ////////////// EVENTS //////////////
    ////////////////////////////////////

    event InterestRateUpdated(uint256 newInterestRate);
    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    ////////////////////////////////////
    //////////// MODIFIERS /////////////
    ////////////////////////////////////

    modifier roleGranted(address _user) {
        vm.prank(owner);
        rebaseToken.grantMintAndBurnRole(_user);
        _;
    }

    ////////////////////////////////////
    //////////// FUNCTIONS /////////////
    ////////////////////////////////////

    function setUp() public {
        vm.startPrank(owner);
        rebaseToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(rebaseToken)));
        rebaseToken.grantMintAndBurnRole(address(vault));
        vm.stopPrank();
    }

    function addRewardsToVault(uint256 rewardAmount) public {
        (bool success,) = payable(address(vault)).call{value: rewardAmount}("");
    }

    ////////////////////////////////////
    ////////// INTEREST RATE ///////////
    ////////////////////////////////////

    function testDepositLinearInterest(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();

        uint256 initialBalance = rebaseToken.balanceOf(user);
        console2.log("Balance of user: ", initialBalance);
        assertEq(initialBalance, amount);

        vm.warp(block.timestamp + 1 hours);
        uint256 middleBalance = rebaseToken.balanceOf(user);
        assert(middleBalance > initialBalance);

        vm.warp(block.timestamp + 1 hours);
        uint256 endBalance = rebaseToken.balanceOf(user);
        assert(endBalance > middleBalance);

        assertApproxEqAbs(endBalance - middleBalance, middleBalance - initialBalance, 1);

        vm.stopPrank();
    }

    function testCanUpdateInterestRate(uint256 newInterestRate) public {
        uint256 currentInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, MIN_AMOUNT, currentInterestRate - 1e5);

        vm.prank(owner);
        rebaseToken.updateInterestRate(newInterestRate);

        assert(newInterestRate < currentInterestRate);
        assertEq(newInterestRate, rebaseToken.getInterestRate());
    }

    function testCannotUpdateInterestRateIfNotOwner(uint256 newInterestRate) public {
        uint256 currentInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, MIN_AMOUNT, currentInterestRate - 1e5);

        vm.prank(user);
        vm.expectRevert();
        rebaseToken.updateInterestRate(newInterestRate);
    }

    function testInterestRateCannotIncrease(uint256 newInterestRate) public {
        uint256 currentInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, currentInterestRate, type(uint256).max);

        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(
                RebaseToken.RebaseToken__InterestRateShouldAlwaysDecrease.selector, newInterestRate, currentInterestRate
            )
        );

        rebaseToken.updateInterestRate(newInterestRate);
    }

    function testMultipleUsersHaveCorrectInterestRates() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");

        // Mint to user1 at initial Rate
        vm.prank(owner);
        rebaseToken.grantMintAndBurnRole(user1);
        vm.startPrank(user1);
        rebaseToken.mint(user1, 100, rebaseToken.getInterestRate());
        vm.stopPrank();

        // Update Interest Rate
        vm.prank(owner);
        rebaseToken.updateInterestRate(2e9);

        // Mint to user2 at new Rate
        vm.prank(owner);
        rebaseToken.grantMintAndBurnRole(user2);
        vm.startPrank(user2);
        rebaseToken.mint(user2, 100, rebaseToken.getInterestRate());
        vm.stopPrank();

        assertEq(rebaseToken.getUserInterestRate(user1), 3e9);
        assertEq(rebaseToken.getUserInterestRate(user2), 2e9);
    }

    function testInterestAccruesCorrectlyOverLongPeriod() public {
        vm.deal(user, STARTING_BALANCE);
        vm.prank(user);
        vault.deposit{value: STARTING_BALANCE}();

        // Warp 100 years (3.15e9 seconds)
        vm.warp(block.timestamp + 3153600000);

        uint256 balance = rebaseToken.balanceOf(user);
        assertGt(balance, STARTING_BALANCE * 10);
    }

    function testNoInterestAccruesWithZeroTimePassed() public {
        vm.deal(user, STARTING_BALANCE);
        vm.prank(user);
        vault.deposit{value: STARTING_BALANCE}();

        uint256 balance = rebaseToken.balanceOf(user);
        assertEq(balance, STARTING_BALANCE);
    }

    function testInterestAccruesAfterMultipleMints() public roleGranted(user) {
        vm.startPrank(user);
        rebaseToken.mint(user, MIN_AMOUNT, rebaseToken.getInterestRate());

        vm.warp(block.timestamp + 10 hours);
        rebaseToken.mint(user, MIN_AMOUNT, rebaseToken.getInterestRate());

        uint256 balance = rebaseToken.balanceOf(user);
        assertGt(balance, MIN_AMOUNT * 2); // Should be > 2 times amount minted
        vm.stopPrank();
    }

    function testUpdateInterestRateEmitsEvent(uint256 newInterestRate) public {
        uint256 currentInterestRate = rebaseToken.getInterestRate();
        newInterestRate = bound(newInterestRate, MIN_AMOUNT, currentInterestRate - 1e5);

        vm.prank(owner);
        vm.expectEmit(true, false, false, false);
        emit InterestRateUpdated(newInterestRate);
        rebaseToken.updateInterestRate(newInterestRate);
    }

    ////////////////////////////////////
    /////////////// MINT ///////////////
    ////////////////////////////////////

    function testCannotMintWithoutRoleGranted(uint256 amountToMint) public {
        uint256 interestRate = rebaseToken.getInterestRate();
        amountToMint = bound(amountToMint, MIN_AMOUNT, type(uint96).max);

        vm.startPrank(user);
        vm.expectRevert();
        rebaseToken.mint(user, amountToMint, interestRate);
        vm.stopPrank();
    }

    function testMintRevertsIfZeroAmount() public roleGranted(user) {
        uint256 interestRate = rebaseToken.getInterestRate();

        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(RebaseToken.RebaseToken__MustBeMoreThanZero.selector, 0)); // abi.encodeWithSelector(RebaseToken.RebaseToken__MustBeMoreThanZero.selector, 0)
        rebaseToken.mint(user, 0, interestRate);
        vm.stopPrank();
    }

    function testCanMint(uint256 amountToMint) public roleGranted(user) {
        amountToMint = bound(amountToMint, MIN_AMOUNT, type(uint96).max);

        vm.startPrank(user);
        rebaseToken.mint(user, amountToMint, rebaseToken.getInterestRate());
        vm.stopPrank();

        assertEq(rebaseToken.balanceOf(user), amountToMint);
    }

    ////////////////////////////////////
    /////////////// BURN ///////////////
    ////////////////////////////////////

    function testCannotBurnWithoutRoleGranted(uint256 amountToMint) public {
        amountToMint = bound(amountToMint, MIN_AMOUNT, type(uint96).max);

        vm.prank(user);
        vm.expectRevert();
        rebaseToken.burn(user, amountToMint);
    }

    function testBurnRevertsIfZeroAmount() public roleGranted(user) {
        vm.startPrank(user);
        vm.expectRevert(abi.encodeWithSelector(RebaseToken.RebaseToken__MustBeMoreThanZero.selector));
        rebaseToken.burn(user, 0);
        vm.stopPrank();
    }

    function testCanBurn(uint256 amountToMint, uint256 amountToBurn) public roleGranted(user) {
        amountToMint = bound(amountToMint, MIN_AMOUNT, type(uint96).max);
        vm.startPrank(user);
        rebaseToken.mint(user, amountToMint, rebaseToken.getInterestRate());

        uint256 initialBalance = rebaseToken.balanceOf(user);
        amountToBurn = bound(amountToBurn, MIN_AMOUNT, initialBalance);

        rebaseToken.burn(user, amountToBurn);
        uint256 finalBalance = rebaseToken.balanceOf(user);
        vm.stopPrank();

        assertEq(finalBalance, initialBalance - amountToBurn);
    }

    ////////////////////////////////////
    ////////////// REDEEM //////////////
    ////////////////////////////////////

    function testRedeemStraightAway(uint256 amount) public {
        amount = bound(amount, MIN_AMOUNT, type(uint96).max);

        vm.startPrank(user);
        vm.deal(user, amount);
        vault.deposit{value: amount}();
        assertEq(rebaseToken.balanceOf(user), amount);

        vault.redeem(type(uint256).max);
        assertEq(rebaseToken.balanceOf(user), 0);
        assertEq(user.balance, amount);
        vm.stopPrank();
    }

    function testRedeemAfterTimePassed(uint256 initialAmount, uint256 timePassed) public {
        initialAmount = bound(initialAmount, 1e18, type(uint96).max);
        timePassed = bound(timePassed, 1000, type(uint96).max);

        vm.deal(user, initialAmount);
        vm.prank(user);
        vault.deposit{value: initialAmount}();
        assertEq(rebaseToken.balanceOf(user), initialAmount);

        vm.warp(block.timestamp + timePassed);
        uint256 balanceAfterTimePassed = rebaseToken.balanceOf(user);

        uint256 interestAccrued = balanceAfterTimePassed - initialAmount;
        vm.deal(owner, interestAccrued);
        vm.prank(owner);
        addRewardsToVault(interestAccrued);

        vm.prank(user);
        vault.redeem(balanceAfterTimePassed);

        uint256 ethBalance = address(user).balance;

        assertEq(ethBalance, balanceAfterTimePassed);
        assertGt(balanceAfterTimePassed, initialAmount);
    }

    function testRedeemEmitsEvent(uint256 amountToRedeem) public {
        amountToRedeem = bound(amountToRedeem, MIN_AMOUNT, type(uint96).max);
        vm.deal(user, amountToRedeem);

        vm.startPrank(user);
        vault.deposit{value: amountToRedeem}();
        vm.expectEmit(true, true, false, false);
        emit Redeem(user, amountToRedeem);
        vault.redeem(amountToRedeem);
    }

    ////////////////////////////////////
    ///////////// DEPOSIT //////////////
    ////////////////////////////////////

    function testCanDeposit(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, MIN_AMOUNT, type(uint96).max);
        vm.deal(user, amountToDeposit);

        vm.prank(user);
        vault.deposit{value: amountToDeposit}();

        assertEq(rebaseToken.balanceOf(user), amountToDeposit);
    }

    function testDepositEmintsEvent(uint256 amountToDeposit) public {
        amountToDeposit = bound(amountToDeposit, MIN_AMOUNT, type(uint96).max);
        vm.deal(user, amountToDeposit);

        vm.prank(user);
        vm.expectEmit(true, true, false, false);
        emit Deposit(user, amountToDeposit);
        vault.deposit{value: amountToDeposit}();
    }

    ////////////////////////////////////
    ///////////// TRANSFER /////////////
    ////////////////////////////////////

    function testCanTransfer(uint256 depositAmount, uint256 amountToSend) public {
        depositAmount = bound(depositAmount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, MIN_AMOUNT, depositAmount - MIN_AMOUNT);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        address user2 = makeAddr("user2");

        assertEq(rebaseToken.balanceOf(user2), 0);
        assertEq(rebaseToken.balanceOf(user), depositAmount);

        vm.prank(owner);
        rebaseToken.updateInterestRate(2e9);

        vm.prank(user);
        rebaseToken.transfer(user2, amountToSend);

        assertEq(rebaseToken.balanceOf(user2), amountToSend);
        assertEq(rebaseToken.balanceOf(user), depositAmount - amountToSend);

        assertEq(rebaseToken.getUserInterestRate(user), rebaseToken.getUserInterestRate(user2));
        assertEq(rebaseToken.getUserInterestRate(user), INITIAL_INITEREST_RATE);
    }

    function testCanTransferFrom(uint256 depositAmount, uint256 amountToSend) public {
        depositAmount = bound(depositAmount, 2e5, type(uint96).max);
        amountToSend = bound(amountToSend, MIN_AMOUNT, depositAmount - MIN_AMOUNT);

        vm.deal(user, depositAmount);
        vm.prank(user);
        vault.deposit{value: depositAmount}();

        address user2 = makeAddr("user2");

        assertEq(rebaseToken.balanceOf(user2), 0);
        assertEq(rebaseToken.balanceOf(user), depositAmount);

        vm.prank(owner);
        rebaseToken.updateInterestRate(2e9);

        vm.startPrank(user);
        rebaseToken.approve(user, amountToSend);
        rebaseToken.transferFrom(user, user2, amountToSend);
        vm.stopPrank();

        assertEq(rebaseToken.balanceOf(user2), amountToSend);
        assertEq(rebaseToken.balanceOf(user), depositAmount - amountToSend);

        assertEq(rebaseToken.getUserInterestRate(user), rebaseToken.getUserInterestRate(user2));
        assertEq(rebaseToken.getUserInterestRate(user), INITIAL_INITEREST_RATE);
    }

    ////////////////////////////////////
    ////////////// GETTERS /////////////
    ////////////////////////////////////

    function testGetInterestRate() public view {
        assertEq(rebaseToken.getInterestRate(), INITIAL_INITEREST_RATE);
    }

    function testGetPrincipleBalanceOf() public roleGranted(user) {
        uint256 amountToMint = 1e18;
        vm.startPrank(user);
        rebaseToken.mint(user, amountToMint, rebaseToken.getInterestRate());
        vm.stopPrank();

        vm.warp(1000); // 1000 seconds passed

        assertEq(rebaseToken.getPrincipleBalanceOf(user), amountToMint);
    }

    function testGetAccumulatedInterestSinceLastInteraction() public roleGranted(user) {
        uint256 amountToMint = 1e18;
        uint256 time = 1000; // 1000 seconds passed

        vm.startPrank(user);
        rebaseToken.mint(user, amountToMint, rebaseToken.getInterestRate());

        vm.warp(block.timestamp + time);
        uint256 expectedAccumulatedInterest = PRECISION + (time * INITIAL_INITEREST_RATE);
        uint256 actualAccumulatedInterest = rebaseToken.getAccumulatedInterestSinceLastInteraction(user);
        vm.stopPrank();

        assertEq(expectedAccumulatedInterest, actualAccumulatedInterest);
    }

    function testGetUserInterestRate() public roleGranted(user) {
        uint256 amountToMint = 1e18;
        uint256 newInterestRate = 2e9;

        vm.startPrank(user);
        rebaseToken.mint(user, amountToMint, rebaseToken.getInterestRate());
        vm.stopPrank();

        vm.prank(owner);
        rebaseToken.updateInterestRate(newInterestRate);

        address newUser = makeAddr("newUser");
        vm.prank(owner);
        rebaseToken.grantMintAndBurnRole(newUser);

        vm.startPrank(newUser);
        rebaseToken.mint(newUser, amountToMint, rebaseToken.getInterestRate());
        vm.stopPrank();

        assertEq(rebaseToken.getUserInterestRate(user), INITIAL_INITEREST_RATE);
        assertEq(rebaseToken.getUserInterestRate(newUser), newInterestRate);
    }

    function testGetRebaseToken() public view {
        assertEq(address(rebaseToken), vault.getRebaseToken());
    }
}
