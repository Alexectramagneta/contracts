// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

interface IDelayedReveal {
    function reveal(uint256 index, bytes calldata _key) external returns (string memory revealedURI);

    function encryptDecrypt(bytes memory data, bytes calldata key) external pure returns (bytes memory result);
}