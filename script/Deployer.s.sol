// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {
    IERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {CCIPLocalSimulatorFork, Register} from "@chainlink/local/src/ccip/CCIPLocalSimulatorFork.sol";
import {RegistryModuleOwnerCustom} from "@ccip/contracts/tokenAdminRegistry/RegistryModuleOwnerCustom.sol";
import {TokenAdminRegistry} from "@ccip/contracts/tokenAdminRegistry/TokenAdminRegistry.sol";

import {IRebaseToken} from "../src/interfaces/IRebaseToken.sol";
import {RebaseToken} from "../src/RebaseToken.sol";
import {RebaseTokenPool} from "../src/RebaseTokenPool.sol";
import {Vault} from "../src/Vault.sol";

/**
 * @title DeployTokenAndPool
 * @notice Deploys RebaseToken and RebaseTokenPool on the current chain
 * and registers them with the CCIP token admin registry.
 *
 * Deployment sequence:
 * 1. Deploy RebaseToken
 * 2. Deploy RebaseTokenPool
 * 3. Grant MINT_AND_BURN_ROLE to the pool
 * 4. Register token admin via owner
 * 5. Accept admin role
 * 6. Link token to pool in TokenAdminRegistry
 */
contract DeployTokenAndPool is Script {
    /**
     * @notice Runs the deployment
     * @return token The deployed RebaseToken contract
     * @return pool The deployed RebaseTokenPool contract
     */
    function run() public returns (RebaseToken token, RebaseTokenPool pool) {
        CCIPLocalSimulatorFork ccipLocalSimulatorFork = new CCIPLocalSimulatorFork();
        Register.NetworkDetails memory networkDetails = ccipLocalSimulatorFork.getNetworkDetails(block.chainid);

        vm.startBroadcast();

        token = new RebaseToken();
        pool = new RebaseTokenPool(
            IERC20(address(token)), new address[](0), networkDetails.rmnProxyAddress, networkDetails.routerAddress
        );
        token.grantMintAndBurnRole(address(pool));

        RegistryModuleOwnerCustom(networkDetails.registryModuleOwnerCustomAddress).registerAdminViaOwner(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).acceptAdminRole(address(token));
        TokenAdminRegistry(networkDetails.tokenAdminRegistryAddress).setPool(address(token), address(pool));

        vm.stopBroadcast();
    }
}

/**
 * @title DeployVault
 * @notice Deploys the Vault contract and grants it MINT_AND_BURN_ROLE
 * on the RebaseToken. Only deployed on the source chain (Sepolia).
 */
contract DeployVault is Script {
    /**
     * @notice Runs the deployment
     * @param _token Address of the already-deployed RebaseToken
     * @return vault The deployed Vault contract
     */
    function run(address _token) public returns (Vault vault) {
        vm.startBroadcast();
        vault = new Vault(IRebaseToken(address(_token)));
        IRebaseToken(address(_token)).grantMintAndBurnRole(address(vault));
        vm.stopBroadcast();
    }
}
