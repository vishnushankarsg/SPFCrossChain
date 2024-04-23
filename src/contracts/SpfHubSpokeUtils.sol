// SPDX-License-Identifier: MIT

pragma solidity ^0.8.13;

import "../libraries/external/BytesLib.sol";

import "./SpfHubSpokeStructs.sol";
contract SpfHubSpokeUtils is SpfHubSpokeStructs{
    using BytesLib for bytes;

    function toCrossChainFormat(address addr) internal pure returns (bytes32) {
    return bytes32(uint256(uint160(addr)));
    }

    function fromCrossChainFormat(bytes32 whFormatAddress) internal pure returns (address) {
        if (uint256(whFormatAddress) >> 160 != 0) {
            revert ("Address format is Wrong!");
        }
        return address(uint160(uint256(whFormatAddress)));
    }

    function normalizeAmount(
        uint256 amount,
        uint8 decimals
    ) internal pure returns(uint256) {
        if (decimals > 8) {
            amount /= 10 ** (decimals - 8);
        }
        return amount;
    }

    function getDecimals(address tokenAddress) public view returns (uint8 decimals) {
    // query decimals
        (,bytes memory queriedDecimals) = address(tokenAddress).staticcall(abi.encodeWithSignature("decimals()"));
        decimals = abi.decode(queriedDecimals, (uint8));
    }

    function parcedActionEncode(Action action, bytes memory payload) internal pure returns(bytes memory){
        return abi.encode(uint8(action), bytes(payload));
    }
    
}