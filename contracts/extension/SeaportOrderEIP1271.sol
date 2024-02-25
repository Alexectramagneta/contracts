// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.11;

import { ERC1271 } from "../eip/ERC1271.sol";
import { SeaportOrderParser } from "./SeaportOrderParser.sol";
import { OrderParameters } from "seaport-types/src/lib/ConsiderationStructs.sol";
import { IAccountPermissions, AccountPermissionsStorage, EnumerableSet, ECDSA } from "./upgradeable/AccountPermissions.sol";

contract SeaportOrderEIP1271 is SeaportOrderParser, ERC1271 {
    using ECDSA for bytes32;
    using EnumerableSet for EnumerableSet.AddressSet;

    bytes32 private constant MSG_TYPEHASH = keccak256("AccountMessage(bytes message)");
    bytes32 private constant TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 private immutable HASHED_NAME = keccak256("Account");
    bytes32 private immutable HASHED_VERSION = keccak256("1");

    /// @notice See EIP-1271
    function isValidSignature(
        bytes32 _message,
        bytes memory _signature
    ) public view virtual override returns (bytes4 magicValue) {
        bytes32 targetDigest;
        bytes memory targetSig;

        // Handle OpenSea bulk order signatures that are >65 bytes in length.
        if (_signature.length > 65) {
            // Decode packed signature and order parameters.
            (bytes memory extractedPackedSig, OrderParameters memory orderParameters, uint256 counter) = abi.decode(
                _signature,
                (bytes, OrderParameters, uint256)
            );

            // Verify that the original digest matches the digest built with order parameters.
            bytes32 domainSeparator = _buildDomainSeparator(msg.sender);
            bytes32 orderHash = _deriveOrderHash(orderParameters, counter);

            require(
                _deriveEIP712Digest(domainSeparator, orderHash) == _message,
                "Seaport: order hash does not match the provided message."
            );

            // Build bulk signature digest
            targetDigest = _deriveEIP712Digest(domainSeparator, _computeBulkOrderProof(extractedPackedSig, orderHash));

            // Extract the signature, which is the first 65 bytes
            targetSig = new bytes(65);
            for (uint i = 0; i < 65; i++) {
                targetSig[i] = extractedPackedSig[i];
            }
        } else {
            targetDigest = getMessageHash(abi.encode(_message));
            targetSig = _signature;
        }

        address signer = targetDigest.recover(targetSig);
        AccountPermissionsStorage.Data storage data = AccountPermissionsStorage.data();

        if (data.isAdmin[signer]) {
            return MAGICVALUE;
        }

        address caller = msg.sender;
        EnumerableSet.AddressSet storage approvedTargets = data.approvedTargets[signer];

        require(
            approvedTargets.contains(caller) || (approvedTargets.length() == 1 && approvedTargets.at(0) == address(0)),
            "Account: caller not approved target."
        );

        if (isActiveSigner(signer)) {
            magicValue = MAGICVALUE;
        }
    }

    /**
     * @notice Returns the hash of message that should be signed for EIP1271 verification.
     * @param message Message to be hashed i.e. `keccak256(abi.encode(data))`
     * @return Hashed message
     */
    function getMessageHash(bytes memory message) public view returns (bytes32) {
        bytes32 messageHash = keccak256(abi.encode(MSG_TYPEHASH, keccak256(message)));
        return keccak256(abi.encodePacked("\x19\x01", _buildDomainSeparator(), messageHash));
    }

    /// @notice Returns whether the given account is an active signer on the account.
    function isActiveSigner(address signer) public view returns (bool) {
        IAccountPermissions.SignerPermissionsStatic memory permissions = AccountPermissionsStorage
            .data()
            .signerPermissions[signer];

        return
            permissions.startTimestamp <= block.timestamp &&
            block.timestamp < permissions.endTimestamp &&
            AccountPermissionsStorage.data().approvedTargets[signer].length() > 0;
    }

    function _buildDomainSeparator() private view returns (bytes32) {
        return keccak256(abi.encode(TYPEHASH, HASHED_NAME, HASHED_VERSION, block.chainid, address(this)));
    }
}