// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {TokenPool} from "@ccip/contracts/pools/TokenPool.sol";
import {Pool} from "@ccip/contracts/libraries/Pool.sol";
import {
    IERC20
} from "@chainlink/contracts/src/v0.8/vendor/openzeppelin-solidity/v4.8.3/contracts/token/ERC20/IERC20.sol";
import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract RebaseTokenPool is TokenPool {
    /**
     * @notice Overrides the TokenPool constructor
     */
    constructor(IERC20 _token, address[] memory _allowlist, address _rmnProxy, address _router)
        TokenPool(_token, 18, _allowlist, _rmnProxy, _router)
    {}

    /**
     * @notice Locks or burns tokens on the source chain and encodes the user's
     * Interest Rate to be passed to the destination chain
     * @param lockOrBurnIn Struct containing the lock/burn parameters
     * @return lockOrBurnOut Struct containing the destination token address
     * and encoded Interest Rate as pool data
     */
    function lockOrBurn(Pool.LockOrBurnInV1 calldata lockOrBurnIn)
        public
        override
        returns (Pool.LockOrBurnOutV1 memory lockOrBurnOut)
    {
        _validateLockOrBurn(lockOrBurnIn);
        uint256 userInterestRate = IRebaseToken(address(i_token)).getUserInterestRate(lockOrBurnIn.originalSender);
        IRebaseToken(address(i_token)).burn(address(this), lockOrBurnIn.amount);

        lockOrBurnOut = Pool.LockOrBurnOutV1({
            destTokenAddress: getRemoteToken(lockOrBurnIn.remoteChainSelector),
            destPoolData: abi.encode(userInterestRate)
        });
    }

    /**
     * @notice Releases or mints tokens on the destination chain, restoring
     * the user's original Interest Rate from the source chain
     * @param releaseOrMintIn Struct containing the release/mint parameters
     * including the encoded Interest Rate from the source chain
     * @return ReleaseOrMintOutV1 struct with the destination token amount
     */
    function releaseOrMint(Pool.ReleaseOrMintInV1 calldata releaseOrMintIn)
        public
        override
        returns (Pool.ReleaseOrMintOutV1 memory)
    {
        _validateReleaseOrMint(releaseOrMintIn, releaseOrMintIn.sourceDenominatedAmount);
        uint256 userInterestRate = abi.decode(releaseOrMintIn.sourcePoolData, (uint256));
        IRebaseToken(address(i_token))
            .mint(releaseOrMintIn.receiver, releaseOrMintIn.sourceDenominatedAmount, userInterestRate);

        return Pool.ReleaseOrMintOutV1({destinationAmount: releaseOrMintIn.sourceDenominatedAmount});
    }
}
