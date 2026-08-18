// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";

import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";

import {
    IERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";
import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";

import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";

contract CrossChainTest is Test {
    ////////////////////////////////////
    ////////// STATE VARIABLES /////////
    ////////////////////////////////////

    struct BridgeResult {
        uint256 sourceBalanceBefore;
        uint256 sourceBalanceAfter;
        uint256 destinationBalanceBefore;
        uint256 destinationBalanceAfter;
        uint256 sourceInterestRate;
        uint256 destinationInterestRate;
    }

    address owner = makeAddr("owner");
    address user = makeAddr("user");
    uint256 SEND_VALUE = 1e5;

    uint256 sepoliaFork;
    uint256 optSepoliaFork;

    CCIPLocalSimulatorFork ccipLocalSimulatorFork;

    RebaseToken sepoliaToken;
    RebaseToken optSepoliaToken;

    Vault vault;

    RebaseTokenPool sepoliaPool;
    RebaseTokenPool optSepoliaPool;

    Register.NetworkDetails sepoliaNetworkDetails;
    Register.NetworkDetails optSepoliaNetworkDetails;

    ////////////////////////////////////
    ////////////// SET UP //////////////
    ////////////////////////////////////

    function setUp() public {
        sepoliaFork = vm.createSelectFork("sepolia-eth");
        optSepoliaFork = vm.createFork("opt-sepolia");

        ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        vm.makePersistent(address(ccipLocalSimulatorFork)); // exists across both forks

        // I. Deploy & Configure on Sepolia
        sepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startPrank(owner);
        sepoliaToken = new RebaseToken();
        vault = new Vault(IRebaseToken(address(sepoliaToken)));
        sepoliaPool = new RebaseTokenPool(
            IERC20(address(sepoliaToken)),
            new address[](0),
            sepoliaNetworkDetails.rmnProxyAddress,
            sepoliaNetworkDetails.routerAddress
        );

        // Grant mint and burn roles to the vault and pool on Sepolia
        sepoliaToken.grantMintAndBurnRole(address(vault));
        sepoliaToken.grantMintAndBurnRole(address(sepoliaPool));

        // Register the token and pool on Sepolia
        RegistryModuleOwnerCustom(sepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(sepoliaToken));
        TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(sepoliaToken), address(sepoliaPool));

        vm.stopPrank();

        // II. Deploy & Configure on Optimism Sepolia
        vm.selectFork(optSepoliaFork);
        optSepoliaNetworkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);
        vm.startPrank(owner);
        optSepoliaToken = new RebaseToken();
        optSepoliaPool = new RebaseTokenPool(
            IERC20(address(optSepoliaToken)),
            new address[](0),
            optSepoliaNetworkDetails.rmnProxyAddress,
            optSepoliaNetworkDetails.routerAddress
        );

        // Grant mint and burn roles to the pool on Optimism Sepolia
        optSepoliaToken.grantMintAndBurnRole(address(optSepoliaPool));

        // Register the token and pool on Optimism Sepolia
        RegistryModuleOwnerCustom(optSepoliaNetworkDetails.registryModuleOwnerCustomAddress)
            .registerAdminViaOwner(address(optSepoliaToken));
        TokenAdminRegistry(optSepoliaNetworkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(optSepoliaToken));
        TokenAdminRegistry(optSepoliaNetworkDetails.tokenAdminRegistryAddress)
            .setPool(address(optSepoliaToken), address(optSepoliaPool));

        vm.stopPrank();

        // Configure the token pools for cross-chain communication,
        // so that each pool knows about the other pool and token on the other chain
        configureTokenPool(
            sepoliaFork,
            address(sepoliaPool),
            optSepoliaNetworkDetails.chainSelector,
            address(optSepoliaPool),
            address(optSepoliaToken)
        );
        configureTokenPool(
            optSepoliaFork,
            address(optSepoliaPool),
            sepoliaNetworkDetails.chainSelector,
            address(sepoliaPool),
            address(sepoliaToken)
        );
    }

    function configureTokenPool(
        uint256 fork,
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress
    ) public {
        vm.selectFork(fork);
        vm.startPrank(owner);

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector, // which chain to connect to
            remotePoolAddresses: remotePoolAddresses, // the pool address on the remote chain
            remoteTokenAddress: abi.encode(remoteTokenAddress), // the token address on the remote chain
            outboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0}),
            inboundRateLimiterConfig: RateLimiter.Config({isEnabled: false, capacity: 0, rate: 0})
        });

        // Apply the chain updates to the local token pool
        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);
        vm.stopPrank();
    }

    function bridgeTokens(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) internal returns (BridgeResult memory result) {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: false})
            )
        });

        // Request funds for the user to pay for the fee
        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        // Approve to the Router
        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);
        uint256 localBalanceBefore = localToken.balanceOf(user);

        // Send the Message
        vm.prank(user);
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
        uint256 localBalanceAfter = localToken.balanceOf(user);

        // assertEq(localBalanceBefore - amountToBridge, localBalanceAfter);
        uint256 localUserInterestRate = localToken.getUserInterestRate(user);

        // Some time has passed...
        vm.selectFork(remoteFork);
        vm.warp(block.timestamp + 1 hours);
        uint256 remoteBalanceBefore = remoteToken.balanceOf(user);

        // Simulation of the delivery and execution on the destination chain
        vm.selectFork(localFork); // switch to the localFork since ccipLocalSimulatorFork is deployed there
        ccipLocalSimulatorFork.switchChainAndRouteMessage(remoteFork);
        uint256 remoteBalanceAfter = remoteToken.balanceOf(user);
        uint256 remoteUserInterestRate = remoteToken.getUserInterestRate(user);

        // return values for testing
        result.sourceBalanceBefore = localBalanceBefore;
        result.sourceBalanceAfter = localBalanceAfter;
        result.destinationBalanceBefore = remoteBalanceBefore;
        result.destinationBalanceAfter = remoteBalanceAfter;
        result.sourceInterestRate = localUserInterestRate;
        result.destinationInterestRate = remoteUserInterestRate;
    }

    ////////////////////////////////////
    ////////////// TESTS ///////////////
    ////////////////////////////////////

    function testBridgeAllTokens() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        BridgeResult memory firstBridge = bridgeTokens(
            SEND_VALUE,
            sepoliaFork,
            optSepoliaFork,
            sepoliaNetworkDetails,
            optSepoliaNetworkDetails,
            sepoliaToken,
            optSepoliaToken
        );
        assertEq(firstBridge.sourceBalanceBefore, SEND_VALUE);
        assertEq(firstBridge.sourceBalanceAfter, 0);
        assertEq(firstBridge.destinationBalanceBefore, 0);
        assertEq(firstBridge.destinationBalanceAfter, SEND_VALUE);
        assertEq(firstBridge.sourceInterestRate, firstBridge.destinationInterestRate);

        vm.selectFork(optSepoliaFork);
        vm.warp(block.timestamp + 30 minutes);
        uint256 balanceAfterTimePassed = optSepoliaToken.balanceOf(user);
        BridgeResult memory secondBridge = bridgeTokens(
            balanceAfterTimePassed,
            optSepoliaFork,
            sepoliaFork,
            optSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            optSepoliaToken,
            sepoliaToken
        );
        assertEq(secondBridge.sourceBalanceBefore, balanceAfterTimePassed);
        assertEq(secondBridge.sourceBalanceAfter, 0);
        assertEq(secondBridge.destinationBalanceBefore, 0);
        assertEq(secondBridge.destinationBalanceAfter, balanceAfterTimePassed);
        assertEq(secondBridge.sourceInterestRate, secondBridge.destinationInterestRate);
    }

    function testBridgePartialBalance(uint256 amountToBridge) public {
        amountToBridge = bound(amountToBridge, 1, SEND_VALUE);

        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();
        BridgeResult memory firstBridge = bridgeTokens(
            amountToBridge,
            sepoliaFork,
            optSepoliaFork,
            sepoliaNetworkDetails,
            optSepoliaNetworkDetails,
            sepoliaToken,
            optSepoliaToken
        );
        assertEq(firstBridge.sourceBalanceBefore, SEND_VALUE);
        assertEq(firstBridge.sourceBalanceAfter, SEND_VALUE - amountToBridge);
        assertEq(firstBridge.destinationBalanceBefore, 0);
        assertEq(firstBridge.destinationBalanceAfter, amountToBridge);
        assertEq(firstBridge.sourceInterestRate, firstBridge.destinationInterestRate);

        vm.selectFork(optSepoliaFork);
        vm.warp(block.timestamp + 30 minutes);
        uint256 balanceAfterTimePassed = optSepoliaToken.balanceOf(user);
        BridgeResult memory secondBridge = bridgeTokens(
            amountToBridge,
            optSepoliaFork,
            sepoliaFork,
            optSepoliaNetworkDetails,
            sepoliaNetworkDetails,
            optSepoliaToken,
            sepoliaToken
        );
        assertEq(secondBridge.sourceBalanceBefore, balanceAfterTimePassed);
        assertEq(secondBridge.sourceBalanceAfter, balanceAfterTimePassed - amountToBridge);
        assertEq(secondBridge.destinationBalanceAfter, secondBridge.destinationBalanceBefore + amountToBridge);
        assertEq(secondBridge.sourceInterestRate, secondBridge.destinationInterestRate);
    }

    function test_RevertWhen_RemoteChainIsNotConfigured() public {
        vm.selectFork(sepoliaFork);
        vm.deal(user, SEND_VALUE);
        vm.prank(user);
        Vault(payable(address(vault))).deposit{value: SEND_VALUE}();

        // Remove optSepoliaPool
        uint64[] memory chainToRemove = new uint64[](1);
        chainToRemove[0] = optSepoliaNetworkDetails.chainSelector;
        vm.prank(owner);
        sepoliaPool.applyChainUpdates(chainToRemove, new TokenPool.ChainUpdate[](0));

        // Attempt to bridge
        _sendBridgeExpectingRevert(
            SEND_VALUE,
            sepoliaFork,
            optSepoliaFork,
            sepoliaNetworkDetails,
            optSepoliaNetworkDetails,
            sepoliaToken,
            optSepoliaToken
        );
    }

    function testRemotePoolsConfigured() public {
        vm.selectFork(sepoliaFork);
        assertEq(
            sepoliaPool.getRemoteToken(optSepoliaNetworkDetails.chainSelector), abi.encode(address(optSepoliaToken))
        );

        vm.selectFork(optSepoliaFork);
        assertEq(optSepoliaPool.getRemoteToken(sepoliaNetworkDetails.chainSelector), abi.encode(address(sepoliaToken)));
    }

    function testPoolsAreRegistered() public {
        vm.selectFork(sepoliaFork);
        assertEq(
            TokenAdminRegistry(sepoliaNetworkDetails.tokenAdminRegistryAddress).getPool(address(sepoliaToken)),
            address(sepoliaPool)
        );

        vm.selectFork(optSepoliaFork);
        assertEq(
            TokenAdminRegistry(optSepoliaNetworkDetails.tokenAdminRegistryAddress).getPool(address(optSepoliaToken)),
            address(optSepoliaPool)
        );
    }

    function testPoolsHaveMintAndBurnRole() public {
        vm.selectFork(sepoliaFork);
        assertTrue(sepoliaToken.hasRole(sepoliaToken.MINT_AND_BURN_ROLE(), address(sepoliaPool)));

        vm.selectFork(optSepoliaFork);
        assertTrue(optSepoliaToken.hasRole(optSepoliaToken.MINT_AND_BURN_ROLE(), address(optSepoliaPool)));
    }

    ////////////////////////////////////
    ///////////// HELPERS //////////////
    ////////////////////////////////////

    function _sendBridgeExpectingRevert(
        uint256 amountToBridge,
        uint256 localFork,
        uint256 remoteFork,
        Register.NetworkDetails memory localNetworkDetails,
        Register.NetworkDetails memory remoteNetworkDetails,
        RebaseToken localToken,
        RebaseToken remoteToken
    ) internal {
        vm.selectFork(localFork);
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(localToken), amount: amountToBridge});

        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(user),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: localNetworkDetails.linkAddress,
            extraArgs: Client._argsToBytes(
                Client.GenericExtraArgsV2({gasLimit: 200_000, allowOutOfOrderExecution: false})
            )
        });

        uint256 fee =
            IRouterClient(localNetworkDetails.routerAddress).getFee(remoteNetworkDetails.chainSelector, message);
        ccipLocalSimulatorFork.requestLinkFromFaucet(user, fee);

        vm.prank(user);
        IERC20(localNetworkDetails.linkAddress).approve(localNetworkDetails.routerAddress, fee);
        vm.prank(user);
        IERC20(address(localToken)).approve(localNetworkDetails.routerAddress, amountToBridge);

        vm.prank(user);
        vm.expectRevert();
        IRouterClient(localNetworkDetails.routerAddress).ccipSend(remoteNetworkDetails.chainSelector, message);
    }
}
