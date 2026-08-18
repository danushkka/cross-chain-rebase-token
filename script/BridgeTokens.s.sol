// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";

import {Client} from "@ccip/contracts/libraries/Client.sol";
import {IRouterClient} from "@ccip/contracts/interfaces/IRouterClient.sol";
import {
    IERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";

/**
 * @title BridgeTokens
 * @notice Bridges RebaseTokens from one chain to another via Chainlink CCIP.
 * Approves the router to spend both the fee token (LINK) and the bridged token,
 * then sends the CCIP message.
 */
contract BridgeTokens is Script {
    /**
     * @notice Runs the bridge transaction
     * @param tokenToSend Address of the RebaseToken to bridge
     * @param amountToSend Amount of tokens to bridge (in wei)
     * @param receiver Address to receive tokens on the destination chain
     * @param linkAddress Address of the LINK token on the source chain (used for fees)
     * @param routerAddress Address of the CCIP router on the source chain
     * @param destinationChainSelector CCIP chain selector of the destination chain
     */
    function run(
        address tokenToSend,
        uint256 amountToSend,
        address receiver,
        address linkAddress,
        address routerAddress,
        uint64 destinationChainSelector
    ) public {
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(tokenToSend), amount: amountToSend});

        vm.startBroadcast();
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            feeToken: linkAddress,
            extraArgs: Client._argsToBytes(Client.EVMExtraArgsV1({gasLimit: 0}))
        });

        uint256 fee = IRouterClient(routerAddress).getFee(destinationChainSelector, message);
        IERC20(linkAddress).approve(routerAddress, fee);
        IERC20(tokenToSend).approve(routerAddress, amountToSend);

        IRouterClient(routerAddress).ccipSend(destinationChainSelector, message);
        vm.stopBroadcast();
    }
}
