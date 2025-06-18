// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract ProofOfReservesGuard {
    mapping(address => AggregatorV3Interface) public reserveFeeds;
    mapping(address => uint256) public minimumReserves;
    
    event ReserveFeedUpdated(address token, address feed);
    event MinimumReservesUpdated(address token, uint256 amount);
    
    function setReserveFeed(address token, address feed) external {
        reserveFeeds[token] = AggregatorV3Interface(feed);
        emit ReserveFeedUpdated(token, feed);
    }
    
    function setMinimumReserves(address token, uint256 amount) external {
        minimumReserves[token] = amount;
        emit MinimumReservesUpdated(token, amount);
    }
    
    function checkReserves(address token) external view returns (bool sufficient, uint256 reserves) {
        AggregatorV3Interface feed = reserveFeeds[token];
        require(address(feed) != address(0), "No reserve feed set");
        
        (, int256 answer,,,) = feed.latestRoundData();
        reserves = uint256(answer);
        sufficient = reserves >= minimumReserves[token];
        
        return (sufficient, reserves);
    }
}
