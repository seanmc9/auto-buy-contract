// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "@openzeppelin/token/ERC20/ERC20.sol";
import "@openzeppelin/access/Ownable.sol";
import "@v3-core/interfaces/IUniswapV3Pool.sol";
import "./interfaces/IWETH9.sol";

contract AutoBuyContract is Ownable {
    uint160 internal constant MIN_SQRT_RATIO = 4295128739; // (from TickMath) The minimum value that can be returned from getSqrtRatioAtTick
    uint256 constant MAX_INT = 2**256 - 1;

    IWETH9 immutable public WETH_CONTRACT;

    IUniswapV3Pool public pool;
    address public proceedsDestination;

    error PoolNotMadeYet();
    error UnauthorizedPool();

    constructor(IWETH9 weth_contract_, IUniswapV3Pool pool_, address proceedsDestination_) Ownable() {
        WETH_CONTRACT = weth_contract_;
        pool = pool_;
        proceedsDestination = proceedsDestination_;
    }

    /**
     * @dev This pool needs to have the token this contract should buy as token1, and WETH as token0.
     */
    function setPool(IUniswapV3Pool pool_) public onlyOwner {
        pool = pool_;
    }

    /**
     * @dev Set where the proceeds of the swaps should go.
     */
    function setProceedsDestination(address proceedsDestination_) public onlyOwner {
        proceedsDestination = proceedsDestination_;
    }

    /// credit: https://github.com/jbx-protocol/juice-buyback/blob/b76f84b8bc55fad2f58ade2b304434cac52efc55/contracts/JBBuybackDelegate.sol#L323
    /// @notice The Uniswap V3 pool callback where the token transfer is expected to happen.
    /// @param _amount0Delta The amount of token 0 being used for the swap.
    /// @param _amount1Delta The amount of token 1 being used for the swap.
    /// @param _data Data passed in by the swap operation.
    function uniswapV3SwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data)
        external
    {
        // Make sure this call is being made from within the swap execution.
        if (msg.sender != address(pool)) revert UnauthorizedPool();

        // Keep a reference to the amount of tokens that should be sent to fulfill the swap (the positive delta)
        uint256 _amountToSendToPool = _amount0Delta < 0 ? uint256(_amount1Delta) : uint256(_amount0Delta);

        // Wrap ETH into WETH
        WETH_CONTRACT.deposit{value: _amountToSendToPool}();

        // Transfer the token to the pool.
        WETH_CONTRACT.transfer(msg.sender, _amountToSendToPool);
    }

    receive() external payable {
        // Make sure the pool exists. credit: https://github.com/jbx-protocol/juice-buyback/blob/b76f84b8bc55fad2f58ade2b304434cac52efc55/contracts/JBBuybackDelegate.sol#L485
        try pool.slot0() returns (uint160, int24, uint16, uint16, uint16, uint8, bool unlocked) {
            // If the pool hasn't been initialized, return an empty quote.
            if (!unlocked) revert PoolNotMadeYet();
        } catch {
            // If the address is invalid or if the pool has not yet been deployed, return an empty quote.
            revert PoolNotMadeYet();
        }

        pool.swap(proceedsDestination, true, int256(msg.value), MIN_SQRT_RATIO + 1, "");
    }
}