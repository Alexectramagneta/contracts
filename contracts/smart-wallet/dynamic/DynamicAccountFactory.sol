// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.12;

// Utils
import "../../extension/Multicall.sol";
import "../../openzeppelin-presets/proxy/Clones.sol";
import "../../openzeppelin-presets/utils/structs/EnumerableSet.sol";

// Interface
import "./../interfaces/IAccountFactory.sol";

// Smart wallet implementation
import "../utils/AccountExtension.sol";
import "./DynamicAccount.sol";

//   $$\     $$\       $$\                 $$\                         $$\
//   $$ |    $$ |      \__|                $$ |                        $$ |
// $$$$$$\   $$$$$$$\  $$\  $$$$$$\   $$$$$$$ |$$\  $$\  $$\  $$$$$$\  $$$$$$$\
// \_$$  _|  $$  __$$\ $$ |$$  __$$\ $$  __$$ |$$ | $$ | $$ |$$  __$$\ $$  __$$\
//   $$ |    $$ |  $$ |$$ |$$ |  \__|$$ /  $$ |$$ | $$ | $$ |$$$$$$$$ |$$ |  $$ |
//   $$ |$$\ $$ |  $$ |$$ |$$ |      $$ |  $$ |$$ | $$ | $$ |$$   ____|$$ |  $$ |
//   \$$$$  |$$ |  $$ |$$ |$$ |      \$$$$$$$ |\$$$$$\$$$$  |\$$$$$$$\ $$$$$$$  |
//    \____/ \__|  \__|\__|\__|       \_______| \_____\____/  \_______|\_______/

contract DynamicAccountFactory is IAccountFactory, Multicall {
    using EnumerableSet for EnumerableSet.AddressSet;

    /*///////////////////////////////////////////////////////////////
                                State
    //////////////////////////////////////////////////////////////*/

    DynamicAccount private immutable _accountImplementation;

    mapping(address => address) private accountAdmin;
    mapping(address => EnumerableSet.AddressSet) private accountsOfSigner;
    mapping(address => EnumerableSet.AddressSet) private signersOfAccount;

    /*///////////////////////////////////////////////////////////////
                            Constructor
    //////////////////////////////////////////////////////////////*/

    constructor(IEntryPoint _entrypoint) {
        address defaultExtension = address(new AccountExtension(address(_entrypoint), address(this)));
        _accountImplementation = new DynamicAccount(_entrypoint, defaultExtension);
    }

    /*///////////////////////////////////////////////////////////////
                        External functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new Account for admin.
    function createAccount(address _admin) external returns (address) {
        address impl = address(_accountImplementation);
        bytes32 salt = keccak256(abi.encode(_admin));
        address account = Clones.predictDeterministicAddress(impl, salt);

        if (account.code.length > 0) {
            return account;
        }

        account = Clones.cloneDeterministic(impl, salt);

        Account(payable(account)).initialize(_admin);

        accountAdmin[account] = _admin;

        emit AccountCreated(account, _admin);

        return account;
    }

    /// @notice Callback function for an Account to register its signers.
    function addSigner(address _signer) external {
        address account = msg.sender;
        require(accountAdmin[account] != address(0), "AccountFactory: invalid caller.");

        accountsOfSigner[_signer].add(account);
        signersOfAccount[account].add(_signer);

        emit SignerAdded(account, _signer);
    }

    /// @notice Callback function for an Account to un-register its signers.
    function removeSigner(address _signer) external {
        address account = msg.sender;
        require(accountAdmin[account] != address(0), "AccountFactory: invalid caller.");

        accountsOfSigner[_signer].remove(account);
        signersOfAccount[account].remove(_signer);

        emit SignerRemoved(account, _signer);
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the implementation of the Account.
    function accountImplementation() external view override returns (address) {
        return address(_accountImplementation);
    }

    /// @notice Returns the address of an Account that would be deployed with the given accountId as salt.
    function getAddress(address _adminSigner) public view returns (address) {
        bytes32 salt = keccak256(abi.encode(_adminSigner));
        return Clones.predictDeterministicAddress(address(_accountImplementation), salt);
    }

    /// @notice Returns the admin and all signers of an account.
    function getSignersOfAccount(address account) external view returns (address admin, address[] memory signers) {
        return (accountAdmin[account], signersOfAccount[account].values());
    }

    /// @notice Returns all accounts that the given address is a signer of.
    function getAccountsOfSigner(address signer) external view returns (address[] memory accounts) {
        return accountsOfSigner[signer].values();
    }
}