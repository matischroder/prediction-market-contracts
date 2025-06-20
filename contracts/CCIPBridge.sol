// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./chainlink/ccip/interfaces/IRouterClient.sol";
import "./chainlink/ccip/libraries/Client.sol";
import "./chainlink/interfaces/LinkTokenInterface.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract CCIPBridge {
    IRouterClient private immutable i_router;
    LinkTokenInterface private immutable i_linkToken;
    
    mapping(uint64 => bool) public allowedDestinationChains;
    
    event MessageSent(bytes32 messageId, uint64 destinationChainSelector, address receiver, uint256 amount);
    
    constructor(address _router, address _link) {
        i_router = IRouterClient(_router);
        i_linkToken = LinkTokenInterface(_link);
    }
    
    function allowDestinationChain(uint64 _destinationChainSelector, bool allowed) external {
        allowedDestinationChains[_destinationChainSelector] = allowed;
    }
    
    function sendTokensPayLINK(
        uint64 _destinationChainSelector,
        address _receiver,
        address _token,
        uint256 _amount
    ) external returns (bytes32 messageId) {
        require(allowedDestinationChains[_destinationChainSelector], "Destination chain not allowed");
        
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({
            token: _token,
            amount: _amount
        });
        
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiver),
            data: "",
            tokenAmounts: tokenAmounts,
            extraArgs: Client._argsToBytes(
                Client.EVMExtraArgsV1({gasLimit: 200_000})
            ),
            feeToken: address(i_linkToken)
        });
        
        uint256 fees = i_router.getFee(_destinationChainSelector, abi.encode(message));
        
        IERC20(_token).transferFrom(msg.sender, address(this), _amount);
        IERC20(_token).approve(address(i_router), _amount);
        
        i_linkToken.approve(address(i_router), fees);
        
        messageId = i_router.ccipSend(_destinationChainSelector, abi.encode(message));
        
        emit MessageSent(messageId, _destinationChainSelector, _receiver, _amount);
        
        return messageId;
    }
}
