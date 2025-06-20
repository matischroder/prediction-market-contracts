// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

interface IRouterClient {
    function ccipSend(uint64 destinationChainSelector, bytes calldata message) external returns (bytes32);
    function getFee(uint64 destinationChainSelector, bytes calldata message) external view returns (uint256);
}
