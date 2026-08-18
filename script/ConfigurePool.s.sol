// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {RateLimiter} from "@ccip/contracts/libraries/RateLimiter.sol";

/**
 * @title ConfigurePool
 * @notice Configures a local RebaseTokenPool to communicate with
 * a remote pool on another chain via CCIP.
 * Must be run on both chains after both pools are deployed.
 */
contract ConfigurePool is Script {
    /**
     * @notice Runs the pool configuration
     * @param localPool Address of the pool on the current chain
     * @param remoteChainSelector CCIP chain selector of the destination chain
     * @param remotePool Address of the pool on the destination chain
     * @param remoteTokenAddress Address of the token on the destination chain
     * @param outboundRateLimiterIsEnabled Whether to enable outbound rate limiting
     * @param outboundRateLimiterCapacity Max tokens allowed in outbound rate limiter bucket
     * @param outboundRateLimiterRate Token refill rate per second for outbound limiter
     * @param inboundRateLimiterIsEnabled Whether to enable inbound rate limiting
     * @param inboundRateLimiterCapacity Max tokens allowed in inbound rate limiter bucket
     * @param inboundRateLimiterRate Token refill rate per second for inbound limiter
     */
    function run(
        address localPool,
        uint64 remoteChainSelector,
        address remotePool,
        address remoteTokenAddress,
        bool outboundRateLimiterIsEnabled,
        uint128 outboundRateLimiterCapacity,
        uint128 outboundRateLimiterRate,
        bool inboundRateLimiterIsEnabled,
        uint128 inboundRateLimiterCapacity,
        uint128 inboundRateLimiterRate
    ) public {
        vm.startBroadcast();

        bytes[] memory remotePoolAddresses = new bytes[](1);
        remotePoolAddresses[0] = abi.encode(remotePool);
        TokenPool.ChainUpdate[] memory chainsToAdd = new TokenPool.ChainUpdate[](1);

        chainsToAdd[0] = TokenPool.ChainUpdate({
            remoteChainSelector: remoteChainSelector,
            remotePoolAddresses: remotePoolAddresses,
            remoteTokenAddress: abi.encode(remoteTokenAddress),
            outboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: outboundRateLimiterIsEnabled,
                capacity: outboundRateLimiterCapacity,
                rate: outboundRateLimiterRate
            }),
            inboundRateLimiterConfig: RateLimiter.Config({
                isEnabled: inboundRateLimiterIsEnabled,
                capacity: inboundRateLimiterCapacity,
                rate: inboundRateLimiterRate
            })
        });

        TokenPool(localPool).applyChainUpdates(new uint64[](0), chainsToAdd);

        vm.stopBroadcast();
    }
}
