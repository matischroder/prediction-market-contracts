// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IPredictionMarket {
    function placeBet(bool position, uint256 amount) external;
    function claimPrize() external;
    function resolveMarket() external;
    function getCurrentOdds() external view returns (uint256 yesOdds, uint256 noOdds);
}
