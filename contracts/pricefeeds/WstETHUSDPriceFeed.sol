// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.15;

import "../vendor/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";
import "../IPriceFeed.sol";
import "../IWstETH.sol";

/**
 * @title wstETH to USD price feed
 * @notice A custom price feed that calculates the price for wstETH / USD using capped stETH price
 * @author Compound
 */
contract WstETHToUSDPriceFeed is IPriceFeed {
    /** Custom errors **/
    error BadDecimals();
    error InvalidInt256();

    /// @notice Version of the price feed
    uint public constant override version = 1;

    /// @notice Description of the price feed
    string public constant override description = "Custom price feed for wstETH / USD";

    /// @notice Number of decimals for returned prices
    uint8 public immutable override decimals;

    /// @notice Chainlink stETH / ETH price feed
    address public immutable stETHtoETHPriceFeed;

    /// @notice Number of decimals for the stETH / ETH price feed
    uint public immutable stETHToETHPriceFeedDecimals;

    /// @notice Chainlink ETH / USD price feed
    address public immutable ETHtoUSDPriceFeed;

    /// @notice Number of decimals for the ETH / USD price feed
    uint public immutable ETHToUSDPriceFeedDecimals;

    /// @notice WstETH contract address
    address public immutable wstETH;

    /// @notice Scale for WstETH contract
    int public immutable wstETHScale;

    /// @notice Capped stETH to ETH value
    int public immutable priceCap;

    constructor(address stETHtoETHPriceFeed_, address ETHtoUSDPriceFeed_, address wstETH_, uint8 decimals_) {
        stETHtoETHPriceFeed = stETHtoETHPriceFeed_;
        stETHToETHPriceFeedDecimals = AggregatorV3Interface(stETHtoETHPriceFeed_).decimals();

        // Note: stETH / ETH price feed has 18 decimals so `decimals_` should always be less than or equals to that
        if (decimals_ > stETHToETHPriceFeedDecimals) revert BadDecimals();
        decimals = decimals_;

        // Note : Caps stETH price at 1 ETH
        priceCap = int256(10 ** stETHToETHPriceFeedDecimals);

        ETHtoUSDPriceFeed = ETHtoUSDPriceFeed_;
        ETHToUSDPriceFeedDecimals = AggregatorV3Interface(ETHtoUSDPriceFeed_).decimals();

        wstETH = wstETH_;
        // Note: Safe to convert directly to an int256 because wstETH.decimals == 18
        wstETHScale = int256(10 ** IWstETH(wstETH).decimals());
    }

    function signed256(uint256 n) internal pure returns (int256) {
        if (n > uint256(type(int256).max)) revert InvalidInt256();
        return int256(n);
    }

    /**
     * @notice WstETH price for the latest round
     * @return roundId Round id from the stETH price feed
     * @return answer Latest price for wstETH / USD
     * @return startedAt Timestamp when the round was started; passed on from stETH price feed
     * @return updatedAt Timestamp when the round was last updated; passed on from stETH price feed
     * @return answeredInRound Round id in which the answer was computed; passed on from stETH price feed
     **/
    function latestRoundData() override external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        (uint80 roundId_, int256 stETHtoETHFeedPrice, uint256 startedAt_, uint256 updatedAt_, uint80 answeredInRound_) = AggregatorV3Interface(stETHtoETHPriceFeed).latestRoundData();
        (, int256 ETHtoUSDPrice,,,) = AggregatorV3Interface(ETHtoUSDPriceFeed).latestRoundData();

        int256 stETHtoETHPrice = stETHtoETHFeedPrice > priceCap ? priceCap : stETHtoETHFeedPrice;

        uint256 tokensPerStEth = IWstETH(wstETH).tokensPerStEth();
        
        int256 price = stETHtoETHPrice * ETHtoUSDPrice * wstETHScale / signed256(tokensPerStEth) / int256(10**ETHToUSDPriceFeedDecimals);
        
        // Note: The stETHtoETH price feed should always have an equal or larger amount of decimals than this price feed (enforced by validation in constructor)
        int256 scaledPrice = price / int256(10 ** (stETHToETHPriceFeedDecimals - decimals));
        return (roundId_, scaledPrice, startedAt_, updatedAt_, answeredInRound_);
    }
}
