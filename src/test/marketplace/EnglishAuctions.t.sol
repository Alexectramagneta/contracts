// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.0;

// Test helper imports
import { BaseTest, IERC721Receiver } from "../utils/BaseTest.sol";

// Test contracts and interfaces
import "contracts/plugin/interface/IPlugin.sol";
import { PluginRegistry } from "contracts/plugin/PluginRegistry.sol";
import { TWRouter } from "contracts/plugin/TWRouter.sol";
import { MarketplaceV3 } from "contracts/marketplace/entrypoint/MarketplaceV3.sol";
import { EnglishAuctionsLogic } from "contracts/marketplace/english-auctions/EnglishAuctionsLogic.sol";
import { TWProxy } from "contracts/TWProxy.sol";

import { PermissionsEnumerable, Permissions } from "contracts/plugin/utils/PermissionsEnumerable.sol";
import { MetaTx } from "contracts/plugin/utils/impl/MetaTx.sol";
import "contracts/openzeppelin-presets/metatx/ERC2771Context.sol";
import "contracts/plugin/utils/impl/ContractMetadataImpl.sol";
import "contracts/plugin/utils/impl/PlatformFeeImpl.sol";

import { IEnglishAuctions } from "contracts/marketplace/IMarketplace.sol";

contract MarketplaceEnglishAuctionsTest is BaseTest {
    address private registryDeployer;

    PluginRegistry private pluginRegistry;

    mapping(uint256 => IPlugin.Plugin) private plugins;

    // Target contract
    address public marketplace;

    // Participants
    address public adminDeployer;
    address public marketplaceDeployer;
    address public seller;
    address public buyer;

    function setUp() public override {
        super.setUp();

        adminDeployer = getActor(0);
        marketplaceDeployer = getActor(1);
        seller = getActor(2);
        buyer = getActor(3);
        registryDeployer = getActor(4);

        vm.prank(registryDeployer);
        pluginRegistry = new PluginRegistry(registryDeployer);

        setupMarketplace(adminDeployer, marketplaceDeployer);
    }

    function setupMarketplace(address _adminDeployer, address _marketplaceDeployer) private {
        string[] memory pluginNames = new string[](5);

        // Deploy plugins

        // Plugin: ERC2771Context
        address erc2771Context = address(new MetaTx(forwarders()));

        plugins[0].metadata = IPlugin.PluginMetadata({
            name: "ERC2771Context",
            metadataURI: "ipfs://ERC2771Context",
            implementation: erc2771Context
        });

        plugins[0].functions.push(
            IPlugin.PluginFunction(ERC2771Context.isTrustedForwarder.selector, "isTrustedForwarder(address)")
        );
        pluginNames[0] = plugins[0].metadata.name;

        // Plugin: PermissionsEnumerable
        address permissions = address(new PermissionsEnumerable());

        plugins[1].metadata = IPlugin.PluginMetadata({
            name: "PermissionsEnumerable",
            metadataURI: "ipfs://PermissionsEnumerable",
            implementation: permissions
        });

        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.hasRole.selector, "hasRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.hasRoleWithSwitch.selector, "hasRoleWithSwitch(bytes32,address)")
        );
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.getRoleAdmin.selector, "getRoleAdmin(bytes32)"));
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.grantRole.selector, "grantRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.revokeRole.selector, "revokeRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.renounceRole.selector, "renounceRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMember.selector, "getRoleMember(bytes32,uint256)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMemberCount.selector, "getRoleMemberCount(bytes32)")
        );
        pluginNames[1] = plugins[1].metadata.name;

        // Plugin: ContractMetadata
        address contractMetadata = address(new ContractMetadataImpl());

        plugins[2].metadata = IPlugin.PluginMetadata({
            name: "ContractMetadata",
            metadataURI: "ipfs://ContractMetadata",
            implementation: contractMetadata
        });

        plugins[2].functions.push(IPlugin.PluginFunction(ContractMetadata.contractURI.selector, "contractURI()"));
        plugins[2].functions.push(
            IPlugin.PluginFunction(ContractMetadata.setContractURI.selector, "setContractURI(string)")
        );
        pluginNames[2] = plugins[2].metadata.name;

        // Plugin: PlatformFee
        address platformFee = address(new PlatformFeeImpl());

        plugins[3].metadata = IPlugin.PluginMetadata({
            name: "PlatformFee",
            metadataURI: "ipfs://PlatformFee",
            implementation: platformFee
        });

        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.getPlatformFeeInfo.selector, "getPlatformFeeInfo()")
        );
        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.setPlatformFeeInfo.selector, "setPlatformFeeInfo(address,uint256)")
        );
        pluginNames[3] = plugins[3].metadata.name;

        // [1] Index `EnglishAuctions` functions in `Plugin`
        plugins[4].metadata = IPlugin.PluginMetadata({
            name: "EnglishAuctionsLogic",
            metadataURI: "ipfs://direct",
            implementation: address(new EnglishAuctionsLogic(address(weth)))
        });
        pluginNames[4] = plugins[4].metadata.name;

        IPlugin.PluginFunction[] memory pluginFunctions = new IPlugin.PluginFunction[](12);
        pluginFunctions[0] = IPlugin.PluginFunction(EnglishAuctionsLogic.totalAuctions.selector, "totalAuctions()");
        pluginFunctions[1] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.createAuction.selector,
            "createAuction((address,uint256,uint256,address,uint256,uint256,uint64,uint64,uint64,uint64))"
        );
        pluginFunctions[2] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.cancelAuction.selector,
            "cancelAuction(uint256)"
        );
        pluginFunctions[3] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionPayout.selector,
            "collectAuctionPayout(uint256)"
        );
        pluginFunctions[4] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionTokens.selector,
            "collectAuctionTokens(uint256)"
        );
        pluginFunctions[5] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.bidInAuction.selector,
            "bidInAuction(uint256,uint256)"
        );
        pluginFunctions[6] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isNewWinningBid.selector,
            "isNewWinningBid(uint256,uint256)"
        );
        pluginFunctions[7] = IPlugin.PluginFunction(EnglishAuctionsLogic.getAuction.selector, "getAuction(uint256)");
        pluginFunctions[8] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllAuctions.selector,
            "getAllAuctions(uint256,uint256)"
        );
        pluginFunctions[9] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllValidAuctions.selector,
            "getAllValidAuctions(uint256,uint256)"
        );
        pluginFunctions[10] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getWinningBid.selector,
            "getWinningBid(uint256)"
        );
        pluginFunctions[11] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isAuctionExpired.selector,
            "isAuctionExpired(uint256)"
        );

        for (uint256 i = 0; i < pluginFunctions.length; i++) {
            plugins[4].functions.push(pluginFunctions[i]);
        }

        // [2] Add plugin to registry
        vm.startPrank(registryDeployer);
        pluginRegistry.addPlugin(plugins[0]);
        pluginRegistry.addPlugin(plugins[1]);
        pluginRegistry.addPlugin(plugins[2]);
        pluginRegistry.addPlugin(plugins[3]);
        pluginRegistry.addPlugin(plugins[4]);
        vm.stopPrank();

        // [3] Deploy `MarketplaceV3` implementation
        vm.startPrank(_adminDeployer);
        MarketplaceV3 router = new MarketplaceV3(address(pluginRegistry), pluginNames);
        vm.stopPrank();

        // [4] Deploy proxy pointing to `MarkeptlaceV3` implementation
        vm.prank(_marketplaceDeployer);
        marketplace = address(
            new TWProxy(
                address(router),
                abi.encodeCall(
                    MarketplaceV3.initialize,
                    (_marketplaceDeployer, "", new address[](0), _marketplaceDeployer, 0)
                )
            )
        );

        // [5] Setup roles for seller and assets
        vm.startPrank(_marketplaceDeployer);
        Permissions(marketplace).revokeRole(keccak256("ASSET_ROLE"), address(0));
        Permissions(marketplace).revokeRole(keccak256("LISTER_ROLE"), address(0));
        Permissions(marketplace).grantRole(keccak256("LISTER_ROLE"), seller);
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc721));
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc1155));

        vm.stopPrank();

        vm.label(address(router), "MarketplaceV3_Impl");
        vm.label(marketplace, "Marketplace");
        vm.label(seller, "Seller");
        vm.label(buyer, "Buyer");
        vm.label(address(erc721), "ERC721_Token");
        vm.label(address(erc1155), "ERC1155_Token");
    }

    function _setupERC721BalanceForSeller(address _seller, uint256 _numOfTokens) private {
        erc721.mint(_seller, _numOfTokens);
    }

    function test_state_initial() public {
        uint256 totoalAuctions = EnglishAuctionsLogic(marketplace).totalAuctions();
        assertEq(totoalAuctions, 0);
    }

    /*///////////////////////////////////////////////////////////////
                            Create Auction
    //////////////////////////////////////////////////////////////*/

    function test_state_createAuction() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        uint256 auctionId = EnglishAuctionsLogic(marketplace).createAuction(auctionParams);

        // Test consequent state of the contract.

        // Marketplace is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);

        // Total listings incremented
        assertEq(EnglishAuctionsLogic(marketplace).totalAuctions(), 1);

        // Fetch listing and verify state.
        IEnglishAuctions.Auction memory auction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        assertEq(auction.auctionId, auctionId);
        assertEq(auction.auctionCreator, seller);
        assertEq(auction.assetContract, assetContract);
        assertEq(auction.tokenId, tokenId);
        assertEq(auction.quantity, quantity);
        assertEq(auction.currency, currency);
        assertEq(auction.minimumBidAmount, minimumBidAmount);
        assertEq(auction.buyoutBidAmount, buyoutBidAmount);
        assertEq(auction.timeBufferInSeconds, timeBufferInSeconds);
        assertEq(auction.bidBufferBps, bidBufferBps);
        assertEq(auction.startTimestamp, startTimestamp);
        assertEq(auction.endTimestamp, endTimestamp);
        assertEq(uint256(auction.tokenType), uint256(IEnglishAuctions.TokenType.ERC721));
    }

    function test_revert_createAuction_notOwnerOfAuctionedToken() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Don't mint to 'token to be auctioned' to the seller.
        address someWallet = getActor(1000);
        _setupERC721BalanceForSeller(someWallet, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), someWallet, tokenIds);
        assertIsNotOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(someWallet);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("ERC721: transfer from incorrect owner");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_notApprovedMarketplaceToTransferToken() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Don't approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, false);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("ERC721: caller is not token owner nor approved");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_auctioningZeroQuantity() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 0;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("Marketplace: auctioning zero quantity.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_invalidQuantity() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 2; // Listing more than `1` quantity
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("Marketplace: auctioning invalid quantity.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_noBidOrTimeBuffer() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 0;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("Marketplace: no time-buffer.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);

        timeBufferInSeconds = 10 seconds;
        bidBufferBps = 0;

        auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("Marketplace: no bid-buffer.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_invalidBidAmounts() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 10 ether; // set minimumBidAmount greater than buyoutBidAmount
        uint256 buyoutBidAmount = 1 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("Marketplace: invalid bid amounts.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_invalidStartTimestamp() public {
        uint256 blockTimestamp = 100 minutes;
        // Set block.timestamp
        vm.warp(blockTimestamp);

        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = uint64(blockTimestamp - 61 minutes); // start time is less than block timestamp.
        uint64 endTimestamp = startTimestamp + 1;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("Marketplace: invalid timestamps.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_invalidEndTimestamp() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = startTimestamp - 1;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        vm.expectRevert("Marketplace: invalid timestamps.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_invalidAssetContract() public {
        // Sample auction parameters.
        address assetContract = address(erc20);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = startTimestamp - 1;

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        // Grant ERC20 token asset role.
        vm.prank(marketplaceDeployer);
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc20));

        vm.prank(seller);
        vm.expectRevert("Marketplace: auctioned token must be ERC1155 or ERC721.");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_noListerRoleWhenRestrictionsActive() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        // Revoke LISTER_ROLE from seller.
        vm.startPrank(marketplaceDeployer);
        assertEq(Permissions(marketplace).hasRole(keccak256("LISTER_ROLE"), address(0)), false);
        Permissions(marketplace).revokeRole(keccak256("LISTER_ROLE"), seller);
        assertEq(Permissions(marketplace).hasRole(keccak256("LISTER_ROLE"), seller), false);

        vm.stopPrank();

        vm.prank(seller);
        vm.expectRevert("!LISTER_ROLE");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_revert_createAuction_noAssetRoleWhenRestrictionsActive() public {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        // Revoke ASSET_ROLE from token to list.
        vm.startPrank(marketplaceDeployer);
        assertEq(Permissions(marketplace).hasRole(keccak256("ASSET_ROLE"), address(0)), false);
        Permissions(marketplace).revokeRole(keccak256("ASSET_ROLE"), address(erc721));
        assertEq(Permissions(marketplace).hasRole(keccak256("ASSET_ROLE"), address(erc721)), false);

        vm.stopPrank();

        vm.prank(seller);
        vm.expectRevert("!ASSET_ROLE");
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    /*///////////////////////////////////////////////////////////////
                            Cancel Auction
    //////////////////////////////////////////////////////////////*/

    function _setup_newAuction() private returns (uint256 auctionId) {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        auctionId = EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function _setup_newAuction_nativeToken() private returns (uint256 auctionId) {
        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = NATIVE_TOKEN;
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        auctionId = EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_state_cancelAuction() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.prank(seller);
        EnglishAuctionsLogic(marketplace).cancelAuction(auctionId);

        // Test consequent states.

        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Total auction count should include deleted auctions too
        assertEq(EnglishAuctionsLogic(marketplace).totalAuctions(), 1);

        // status should be `CANCELLED`
        IEnglishAuctions.Auction memory cancelledAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);
        assertTrue(cancelledAuction.status == IEnglishAuctions.Status.CANCELLED);
    }

    function test_revert_cancelAuction_bidsAlreadyMade() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();

        vm.prank(seller);
        vm.expectRevert("Marketplace: bids already made.");
        EnglishAuctionsLogic(marketplace).cancelAuction(auctionId);
    }

    /*///////////////////////////////////////////////////////////////
                            Bid In Auction
    //////////////////////////////////////////////////////////////*/

    function test_state_bidInAuction_firstBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 1 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 1 ether);
    }

    function test_state_bidInAuction_secondBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place first bid
        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 1 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 1 ether);

        // place second winning bid
        erc20.mint(address(0x345), 2 ether);
        vm.startPrank(address(0x345));
        erc20.approve(marketplace, 2 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 2 ether);
        vm.stopPrank();

        (bidder, currency, bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(auctionId);

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 2 ether);
        assertEq(erc20.balanceOf(buyer), 1 ether);
        assertEq(erc20.balanceOf(address(0x345)), 0);
        assertEq(address(0x345), bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 2 ether);
    }

    function test_state_bidInAuction_buyoutBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place first bid
        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 1 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 1 ether);

        // place buyout bid
        erc20.mint(address(0x345), 10 ether);
        vm.startPrank(address(0x345));
        erc20.approve(marketplace, 10 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 10 ether);
        vm.stopPrank();

        (bidder, currency, bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(auctionId);

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), address(0x345), tokenIds);
        assertEq(erc20.balanceOf(marketplace), 10 ether);
        assertEq(erc20.balanceOf(buyer), 1 ether);
        assertEq(erc20.balanceOf(address(0x345)), 0);
        assertEq(address(0x345), bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 10 ether);
    }

    function test_revert_bidInAuction_inactiveAuction() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        // place bid before start-time
        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        vm.expectRevert("Marketplace: inactive auction.");
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();

        // place bid after end-time
        vm.warp(existingAuction.endTimestamp);

        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        vm.expectRevert("Marketplace: inactive auction.");
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();
    }

    function test_revert_bidInAuction_notOwnerOfBidTokens() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();
    }

    function test_revert_bidInAuction_notApprovedMarketplaceToTransferToken() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        vm.expectRevert("ERC20: insufficient allowance");
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();
    }

    function test_revert_bidInAuction_notNewWinningBid_firstBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place first bid less than minimum bid amount
        erc20.mint(buyer, 0.5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 0.5 ether);
        vm.expectRevert("Marketplace: not winning bid.");
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 0.5 ether);
        vm.stopPrank();
    }

    function test_revert_bidInAuction_notNewWinningBid_secondBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place first bid
        erc20.mint(buyer, 1 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 1 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 1 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 1 ether);

        // place second bid less-than/equal-to previous winning bid
        erc20.mint(address(0x345), 1 ether);
        vm.startPrank(address(0x345));
        erc20.approve(marketplace, 1 ether);
        vm.expectRevert("Marketplace: not winning bid.");
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 1 ether);
        vm.stopPrank();
    }

    function test_state_bidInAuction_nativeToken() public {
        uint256 auctionId = _setup_newAuction_nativeToken();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        vm.deal(buyer, 10 ether);
        vm.startPrank(buyer);
        EnglishAuctionsLogic(marketplace).bidInAuction{ value: 1 ether }(auctionId, 1 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(weth.balanceOf(marketplace), 1 ether);
        assertEq(buyer.balance, 9 ether);
        assertEq(buyer, bidder);
        assertEq(currency, NATIVE_TOKEN);
        assertEq(bidAmount, 1 ether);
    }

    /*///////////////////////////////////////////////////////////////
                        Collect Auction Payout
    //////////////////////////////////////////////////////////////*/

    function test_state_collectAuctionPayout_buyoutBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place buyout bid
        erc20.mint(buyer, 10 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 10 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 10 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), buyer, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 10 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 10 ether);

        // collect auction payout
        vm.prank(seller);
        EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);

        assertEq(erc20.balanceOf(marketplace), 0);
        assertEq(erc20.balanceOf(seller), 10 ether);
    }

    function test_state_collectAuctionPayout_afterAuctionEnds() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 5 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 5 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 5 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 5 ether);

        vm.warp(existingAuction.endTimestamp);

        // collect auction payout
        vm.prank(seller);
        EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);

        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 0);
        assertEq(erc20.balanceOf(seller), 5 ether);
    }

    function test_revert_collectAuctionPayout_auctionNotExpired() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 5 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 5 ether);
        vm.stopPrank();

        // collect auction payout before auction has ended
        vm.prank(seller);
        vm.expectRevert("Marketplace: auction still active.");
        EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);
    }

    function test_revert_collectAuctionPayout_noBidsInAuction() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.endTimestamp);

        // collect auction payout without any bids made
        vm.prank(seller);
        vm.expectRevert("Marketplace: no bids were made.");
        EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);
    }

    /*///////////////////////////////////////////////////////////////
                        Collect Auction Tokens
    //////////////////////////////////////////////////////////////*/

    function test_state_collectAuctionTokens() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 5 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 5 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 5 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 5 ether);

        vm.warp(existingAuction.endTimestamp);

        // collect auction tokens
        vm.prank(buyer);
        EnglishAuctionsLogic(marketplace).collectAuctionTokens(auctionId);

        assertIsOwnerERC721(address(erc721), buyer, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 5 ether);
    }

    function test_revert_collectAuctionTokens_auctionNotExpired() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 5 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 5 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Test consequent states.
        // Seller is owner of token.
        assertIsOwnerERC721(address(erc721), marketplace, tokenIds);
        assertEq(erc20.balanceOf(marketplace), 5 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 5 ether);

        // collect auction tokens before auction has ended
        vm.prank(buyer);
        vm.expectRevert("Marketplace: auction still active.");
        EnglishAuctionsLogic(marketplace).collectAuctionTokens(auctionId);
    }

    /*///////////////////////////////////////////////////////////////
                            View functions
    //////////////////////////////////////////////////////////////*/

    function test_state_isNewWinningBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 5 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 5 ether);
        vm.stopPrank();

        // check if new winning bid
        assertTrue(EnglishAuctionsLogic(marketplace).isNewWinningBid(auctionId, 6 ether));
        assertFalse(EnglishAuctionsLogic(marketplace).isNewWinningBid(auctionId, 5 ether));
        assertFalse(EnglishAuctionsLogic(marketplace).isNewWinningBid(auctionId, 4 ether));
    }

    function test_revert_isNewWinningBid() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = existingAuction.tokenId;

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc721));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 5 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 5 ether);
        vm.stopPrank();

        // check winning bid for a non-existent auction
        vm.expectRevert("Marketplace: invalid auction.");
        EnglishAuctionsLogic(marketplace).isNewWinningBid(auctionId + 1, 6 ether);
    }

    function test_state_getAllAuctions() public {
        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 6);

        uint256[] memory auctionIds = new uint256[](5);
        uint256[] memory tokenIds = new uint256[](5);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = uint64(block.timestamp);
        uint64 endTimestamp = startTimestamp + 200;

        IEnglishAuctions.AuctionParameters memory auctionParams;

        for (uint256 i = 0; i < 5; i += 1) {
            tokenIds[i] = i;

            // Auction tokens.
            auctionParams = IEnglishAuctions.AuctionParameters(
                assetContract,
                tokenIds[i],
                quantity,
                currency,
                minimumBidAmount,
                buyoutBidAmount,
                timeBufferInSeconds,
                bidBufferBps,
                startTimestamp,
                endTimestamp
            );

            vm.prank(seller);
            auctionIds[i] = EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
        }

        IEnglishAuctions.Auction[] memory activeAuctions = EnglishAuctionsLogic(marketplace).getAllAuctions(0, 4);
        assertEq(activeAuctions.length, 5);

        for (uint256 i = 0; i < 5; i += 1) {
            assertEq(activeAuctions[i].auctionId, auctionIds[i]);
            assertEq(activeAuctions[i].auctionCreator, seller);
            assertEq(activeAuctions[i].assetContract, assetContract);
            assertEq(activeAuctions[i].tokenId, tokenIds[i]);
            assertEq(activeAuctions[i].quantity, quantity);
            assertEq(activeAuctions[i].currency, currency);
            assertEq(activeAuctions[i].minimumBidAmount, minimumBidAmount);
            assertEq(activeAuctions[i].buyoutBidAmount, buyoutBidAmount);
            assertEq(activeAuctions[i].timeBufferInSeconds, timeBufferInSeconds);
            assertEq(activeAuctions[i].bidBufferBps, bidBufferBps);
            assertEq(activeAuctions[i].startTimestamp, startTimestamp);
            assertEq(activeAuctions[i].endTimestamp, endTimestamp);
            assertEq(uint256(activeAuctions[i].tokenType), uint256(IEnglishAuctions.TokenType.ERC721));
        }
    }

    function test_state_getAllValidAuctions() public {
        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 6);

        uint256[] memory auctionIds = new uint256[](5);
        uint256[] memory tokenIds = new uint256[](5);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = uint64(block.timestamp);
        uint64 endTimestamp = startTimestamp + 200;

        IEnglishAuctions.AuctionParameters memory auctionParams;

        for (uint256 i = 0; i < 5; i += 1) {
            tokenIds[i] = i;

            // Auction tokens.
            auctionParams = IEnglishAuctions.AuctionParameters(
                assetContract,
                tokenIds[i],
                quantity,
                currency,
                minimumBidAmount,
                buyoutBidAmount,
                timeBufferInSeconds,
                bidBufferBps,
                startTimestamp,
                endTimestamp
            );

            vm.prank(seller);
            auctionIds[i] = EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
        }

        IEnglishAuctions.Auction[] memory activeAuctions = EnglishAuctionsLogic(marketplace).getAllValidAuctions(0, 4);
        assertEq(activeAuctions.length, 5);

        for (uint256 i = 0; i < 5; i += 1) {
            assertEq(activeAuctions[i].auctionId, auctionIds[i]);
            assertEq(activeAuctions[i].auctionCreator, seller);
            assertEq(activeAuctions[i].assetContract, assetContract);
            assertEq(activeAuctions[i].tokenId, tokenIds[i]);
            assertEq(activeAuctions[i].quantity, quantity);
            assertEq(activeAuctions[i].currency, currency);
            assertEq(activeAuctions[i].minimumBidAmount, minimumBidAmount);
            assertEq(activeAuctions[i].buyoutBidAmount, buyoutBidAmount);
            assertEq(activeAuctions[i].timeBufferInSeconds, timeBufferInSeconds);
            assertEq(activeAuctions[i].bidBufferBps, bidBufferBps);
            assertEq(activeAuctions[i].startTimestamp, startTimestamp);
            assertEq(activeAuctions[i].endTimestamp, endTimestamp);
            assertEq(uint256(activeAuctions[i].tokenType), uint256(IEnglishAuctions.TokenType.ERC721));
        }

        // create an inactive auction, and check the auctions returned
        auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            5,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp + 100,
            endTimestamp
        );

        vm.prank(seller);
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams);

        activeAuctions = EnglishAuctionsLogic(marketplace).getAllValidAuctions(0, 5);
        assertEq(activeAuctions.length, 5);
    }

    function test_state_isAuctionExpired() public {
        uint256 auctionId = _setup_newAuction();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        vm.warp(existingAuction.endTimestamp);
        assertTrue(EnglishAuctionsLogic(marketplace).isAuctionExpired(auctionId));
    }

    function test_revert_isAuctionExpired() public {
        uint256 auctionId = _setup_newAuction();

        vm.expectRevert("Marketplace: invalid auction.");
        EnglishAuctionsLogic(marketplace).isAuctionExpired(auctionId + 1);
    }
}

contract BreitwieserTheCreator is BaseTest, IERC721Receiver {
    address private registryDeployer;

    PluginRegistry private pluginRegistry;

    mapping(uint256 => IPlugin.Plugin) private plugins;

    // Target contract
    address public marketplace;

    // Participants
    address public adminDeployer;
    address public marketplaceDeployer;
    address public seller;
    address public buyer;

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function setUp() public override {
        super.setUp();

        adminDeployer = getActor(0);
        marketplaceDeployer = getActor(1);
        seller = getActor(2);
        buyer = getActor(3);
        registryDeployer = getActor(4);

        vm.prank(registryDeployer);
        pluginRegistry = new PluginRegistry(registryDeployer);

        setupMarketplaceEnglish(adminDeployer, marketplaceDeployer);
    }

    function _setupERC721BalanceForSeller(address _seller, uint256 _numOfTokens) private {
        erc721.mint(_seller, _numOfTokens);
    }

    function setupMarketplaceEnglish(address _adminDeployer, address _marketplaceDeployer) private {
        string[] memory pluginNames = new string[](5);

        // Deploy plugins

        // Plugin: ERC2771Context
        address erc2771Context = address(new MetaTx(forwarders()));

        plugins[0].metadata = IPlugin.PluginMetadata({
            name: "ERC2771Context",
            metadataURI: "ipfs://ERC2771Context",
            implementation: erc2771Context
        });

        plugins[0].functions.push(
            IPlugin.PluginFunction(ERC2771Context.isTrustedForwarder.selector, "isTrustedForwarder(address)")
        );
        pluginNames[0] = plugins[0].metadata.name;

        // Plugin: PermissionsEnumerable
        address permissions = address(new PermissionsEnumerable());

        plugins[1].metadata = IPlugin.PluginMetadata({
            name: "PermissionsEnumerable",
            metadataURI: "ipfs://PermissionsEnumerable",
            implementation: permissions
        });

        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.hasRole.selector, "hasRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.hasRoleWithSwitch.selector, "hasRoleWithSwitch(bytes32,address)")
        );
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.getRoleAdmin.selector, "getRoleAdmin(bytes32)"));
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.grantRole.selector, "grantRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.revokeRole.selector, "revokeRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.renounceRole.selector, "renounceRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMember.selector, "getRoleMember(bytes32,uint256)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMemberCount.selector, "getRoleMemberCount(bytes32)")
        );
        pluginNames[1] = plugins[1].metadata.name;

        // Plugin: ContractMetadata
        address contractMetadata = address(new ContractMetadataImpl());

        plugins[2].metadata = IPlugin.PluginMetadata({
            name: "ContractMetadata",
            metadataURI: "ipfs://ContractMetadata",
            implementation: contractMetadata
        });

        plugins[2].functions.push(IPlugin.PluginFunction(ContractMetadata.contractURI.selector, "contractURI()"));
        plugins[2].functions.push(
            IPlugin.PluginFunction(ContractMetadata.setContractURI.selector, "setContractURI(string)")
        );
        pluginNames[2] = plugins[2].metadata.name;

        // Plugin: PlatformFee
        address platformFee = address(new PlatformFeeImpl());

        plugins[3].metadata = IPlugin.PluginMetadata({
            name: "PlatformFee",
            metadataURI: "ipfs://PlatformFee",
            implementation: platformFee
        });

        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.getPlatformFeeInfo.selector, "getPlatformFeeInfo()")
        );
        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.setPlatformFeeInfo.selector, "setPlatformFeeInfo(address,uint256)")
        );
        pluginNames[3] = plugins[3].metadata.name;

        // [1] Index `EnglishAuctions` functions in `Plugin`
        plugins[4].metadata = IPlugin.PluginMetadata({
            name: "EnglishAuctionsLogic",
            metadataURI: "ipfs://direct",
            implementation: address(new EnglishAuctionsLogic(address(weth)))
        });
        pluginNames[4] = plugins[4].metadata.name;

        IPlugin.PluginFunction[] memory pluginFunctions = new IPlugin.PluginFunction[](12);
        pluginFunctions[0] = IPlugin.PluginFunction(EnglishAuctionsLogic.totalAuctions.selector, "totalAuctions()");
        pluginFunctions[1] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.createAuction.selector,
            "createAuction((address,uint256,uint256,address,uint256,uint256,uint64,uint64,uint64,uint64))"
        );
        pluginFunctions[2] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.cancelAuction.selector,
            "cancelAuction(uint256)"
        );
        pluginFunctions[3] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionPayout.selector,
            "collectAuctionPayout(uint256)"
        );
        pluginFunctions[4] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionTokens.selector,
            "collectAuctionTokens(uint256)"
        );
        pluginFunctions[5] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.bidInAuction.selector,
            "bidInAuction(uint256,uint256)"
        );
        pluginFunctions[6] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isNewWinningBid.selector,
            "isNewWinningBid(uint256,uint256)"
        );
        pluginFunctions[7] = IPlugin.PluginFunction(EnglishAuctionsLogic.getAuction.selector, "getAuction(uint256)");
        pluginFunctions[8] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllAuctions.selector,
            "getAllAuctions(uint256,uint256)"
        );
        pluginFunctions[9] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllValidAuctions.selector,
            "getAllValidAuctions(uint256,uint256)"
        );
        pluginFunctions[10] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getWinningBid.selector,
            "getWinningBid(uint256)"
        );
        pluginFunctions[11] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isAuctionExpired.selector,
            "isAuctionExpired(uint256)"
        );

        for (uint256 i = 0; i < pluginFunctions.length; i++) {
            plugins[4].functions.push(pluginFunctions[i]);
        }

        // [2] Add plugin to registry
        vm.startPrank(registryDeployer);
        pluginRegistry.addPlugin(plugins[0]);
        pluginRegistry.addPlugin(plugins[1]);
        pluginRegistry.addPlugin(plugins[2]);
        pluginRegistry.addPlugin(plugins[3]);
        pluginRegistry.addPlugin(plugins[4]);
        vm.stopPrank();

        // [3] Deploy `MarketplaceV3` implementation
        vm.startPrank(_adminDeployer);
        MarketplaceV3 router = new MarketplaceV3(address(pluginRegistry), pluginNames);
        vm.stopPrank();

        // [4] Deploy proxy pointing to `MarkeptlaceV3` implementation
        vm.prank(_marketplaceDeployer);
        marketplace = address(
            new TWProxy(
                address(router),
                abi.encodeCall(
                    MarketplaceV3.initialize,
                    (_marketplaceDeployer, "", new address[](0), _marketplaceDeployer, 0)
                )
            )
        );

        // [5] Setup roles for seller and assets
        vm.startPrank(_marketplaceDeployer);
        Permissions(marketplace).revokeRole(keccak256("ASSET_ROLE"), address(0));
        Permissions(marketplace).revokeRole(keccak256("LISTER_ROLE"), address(0));
        Permissions(marketplace).grantRole(keccak256("LISTER_ROLE"), seller);
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc721));
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc1155));

        vm.stopPrank();

        vm.label(address(router), "MarketplaceV3_Impl");
        vm.label(marketplace, "Marketplace");
        vm.label(seller, "Seller");
        vm.label(buyer, "Buyer");
        vm.label(address(erc721), "ERC721_Token");
        vm.label(address(erc1155), "ERC1155_Token");
    }

    function test_rob_as_creator() public {
        ///////////////////////////// Setup: dummy NFT  ////////////////////////////

        // Sample auction parameters.
        address assetContract = address(erc721);
        uint256 tokenId = 0;
        uint256 quantity = 1;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 50 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 0;
        uint64 endTimestamp = 200;

        // Mint the ERC721 tokens to seller. These tokens will be auctioned.
        _setupERC721BalanceForSeller(seller, 1);

        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;
        assertIsOwnerERC721(address(erc721), seller, tokenIds);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc721.setApprovalForAll(marketplace, true);

        ////////////////////////////// Setup: auction tokens //////////////////////////////////
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );
        vm.prank(seller);
        uint256 auctionId = EnglishAuctionsLogic(marketplace).createAuction(auctionParams);

        /////////////////////////// Setup: marketplace has currency /////////////
        uint256 mbalance = 100 ether;
        erc20.mint(marketplace, mbalance);

        /////////////////////////// Attack: win to drain ///////////////////////////////////////////

        // 1. Buy out the token.
        assertEq(erc20.balanceOf(seller), 0);
        erc20.mint(seller, buyoutBidAmount);
        assertEq(erc20.balanceOf(seller), buyoutBidAmount);

        vm.startPrank(seller);

        erc20.approve(marketplace, buyoutBidAmount);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, buyoutBidAmount);

        // 2. Collect their own bid.
        EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);
        assertEq(erc20.balanceOf(seller), buyoutBidAmount);

        // 3. Profit. (FIXED)

        vm.expectRevert("Marketplace: payout already completed.");
        EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);
        // EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);
        // assertEq(erc20.balanceOf(seller), buyoutBidAmount + mbalance);
    }
}

contract BreitwieserTheBidder is BaseTest {
    address private registryDeployer;

    PluginRegistry private pluginRegistry;

    mapping(uint256 => IPlugin.Plugin) private plugins;

    // Target contract
    address public marketplace;

    // Participants
    address public adminDeployer;
    address public marketplaceDeployer;
    address public seller;
    address public buyer;

    function setUp() public override {
        super.setUp();

        adminDeployer = getActor(0);
        marketplaceDeployer = getActor(1);
        seller = getActor(2);
        buyer = getActor(3);
        registryDeployer = getActor(4);

        vm.prank(registryDeployer);
        pluginRegistry = new PluginRegistry(registryDeployer);

        setupMarketplaceEnglish(adminDeployer, marketplaceDeployer);
    }

    function _setupERC721BalanceForSeller(address _seller, uint256 _numOfTokens) private {
        erc721.mint(_seller, _numOfTokens);
    }

    function setupMarketplaceEnglish(address _adminDeployer, address _marketplaceDeployer) private {
        string[] memory pluginNames = new string[](5);

        // Deploy plugins

        // Plugin: ERC2771Context
        address erc2771Context = address(new MetaTx(forwarders()));

        plugins[0].metadata = IPlugin.PluginMetadata({
            name: "ERC2771Context",
            metadataURI: "ipfs://ERC2771Context",
            implementation: erc2771Context
        });

        plugins[0].functions.push(
            IPlugin.PluginFunction(ERC2771Context.isTrustedForwarder.selector, "isTrustedForwarder(address)")
        );
        pluginNames[0] = plugins[0].metadata.name;

        // Plugin: PermissionsEnumerable
        address permissions = address(new PermissionsEnumerable());

        plugins[1].metadata = IPlugin.PluginMetadata({
            name: "PermissionsEnumerable",
            metadataURI: "ipfs://PermissionsEnumerable",
            implementation: permissions
        });

        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.hasRole.selector, "hasRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.hasRoleWithSwitch.selector, "hasRoleWithSwitch(bytes32,address)")
        );
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.getRoleAdmin.selector, "getRoleAdmin(bytes32)"));
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.grantRole.selector, "grantRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.revokeRole.selector, "revokeRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.renounceRole.selector, "renounceRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMember.selector, "getRoleMember(bytes32,uint256)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMemberCount.selector, "getRoleMemberCount(bytes32)")
        );
        pluginNames[1] = plugins[1].metadata.name;

        // Plugin: ContractMetadata
        address contractMetadata = address(new ContractMetadataImpl());

        plugins[2].metadata = IPlugin.PluginMetadata({
            name: "ContractMetadata",
            metadataURI: "ipfs://ContractMetadata",
            implementation: contractMetadata
        });

        plugins[2].functions.push(IPlugin.PluginFunction(ContractMetadata.contractURI.selector, "contractURI()"));
        plugins[2].functions.push(
            IPlugin.PluginFunction(ContractMetadata.setContractURI.selector, "setContractURI(string)")
        );
        pluginNames[2] = plugins[2].metadata.name;

        // Plugin: PlatformFee
        address platformFee = address(new PlatformFeeImpl());

        plugins[3].metadata = IPlugin.PluginMetadata({
            name: "PlatformFee",
            metadataURI: "ipfs://PlatformFee",
            implementation: platformFee
        });

        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.getPlatformFeeInfo.selector, "getPlatformFeeInfo()")
        );
        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.setPlatformFeeInfo.selector, "setPlatformFeeInfo(address,uint256)")
        );
        pluginNames[3] = plugins[3].metadata.name;

        // [1] Index `EnglishAuctions` functions in `Plugin`
        plugins[4].metadata = IPlugin.PluginMetadata({
            name: "EnglishAuctionsLogic",
            metadataURI: "ipfs://direct",
            implementation: address(new EnglishAuctionsLogic(address(weth)))
        });
        pluginNames[4] = plugins[4].metadata.name;

        IPlugin.PluginFunction[] memory pluginFunctions = new IPlugin.PluginFunction[](12);
        pluginFunctions[0] = IPlugin.PluginFunction(EnglishAuctionsLogic.totalAuctions.selector, "totalAuctions()");
        pluginFunctions[1] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.createAuction.selector,
            "createAuction((address,uint256,uint256,address,uint256,uint256,uint64,uint64,uint64,uint64))"
        );
        pluginFunctions[2] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.cancelAuction.selector,
            "cancelAuction(uint256)"
        );
        pluginFunctions[3] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionPayout.selector,
            "collectAuctionPayout(uint256)"
        );
        pluginFunctions[4] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionTokens.selector,
            "collectAuctionTokens(uint256)"
        );
        pluginFunctions[5] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.bidInAuction.selector,
            "bidInAuction(uint256,uint256)"
        );
        pluginFunctions[6] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isNewWinningBid.selector,
            "isNewWinningBid(uint256,uint256)"
        );
        pluginFunctions[7] = IPlugin.PluginFunction(EnglishAuctionsLogic.getAuction.selector, "getAuction(uint256)");
        pluginFunctions[8] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllAuctions.selector,
            "getAllAuctions(uint256,uint256)"
        );
        pluginFunctions[9] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllValidAuctions.selector,
            "getAllValidAuctions(uint256,uint256)"
        );
        pluginFunctions[10] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getWinningBid.selector,
            "getWinningBid(uint256)"
        );
        pluginFunctions[11] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isAuctionExpired.selector,
            "isAuctionExpired(uint256)"
        );

        for (uint256 i = 0; i < pluginFunctions.length; i++) {
            plugins[4].functions.push(pluginFunctions[i]);
        }

        // [2] Add plugin to registry
        vm.startPrank(registryDeployer);
        pluginRegistry.addPlugin(plugins[0]);
        pluginRegistry.addPlugin(plugins[1]);
        pluginRegistry.addPlugin(plugins[2]);
        pluginRegistry.addPlugin(plugins[3]);
        pluginRegistry.addPlugin(plugins[4]);
        vm.stopPrank();

        // [3] Deploy `MarketplaceV3` implementation
        vm.startPrank(_adminDeployer);
        MarketplaceV3 router = new MarketplaceV3(address(pluginRegistry), pluginNames);
        vm.stopPrank();

        // [4] Deploy proxy pointing to `MarkeptlaceV3` implementation
        vm.prank(_marketplaceDeployer);
        marketplace = address(
            new TWProxy(
                address(router),
                abi.encodeCall(
                    MarketplaceV3.initialize,
                    (_marketplaceDeployer, "", new address[](0), _marketplaceDeployer, 0)
                )
            )
        );

        // [5] Setup roles for seller and assets
        vm.startPrank(_marketplaceDeployer);
        Permissions(marketplace).revokeRole(keccak256("ASSET_ROLE"), address(0));
        Permissions(marketplace).revokeRole(keccak256("LISTER_ROLE"), address(0));
        Permissions(marketplace).grantRole(keccak256("LISTER_ROLE"), seller);
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc721));
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc1155));

        vm.stopPrank();

        vm.label(address(router), "MarketplaceV3_Impl");
        vm.label(marketplace, "Marketplace");
        vm.label(seller, "Seller");
        vm.label(buyer, "Buyer");
        vm.label(address(erc721), "ERC721_Token");
        vm.label(address(erc1155), "ERC1155_Token");
    }

    function test_rob_as_bidder() public {
        address attacker = address(0xbeef);
        vm.prank(marketplaceDeployer);
        Permissions(marketplace).grantRole(keccak256("LISTER_ROLE"), attacker);

        // Condition: multiple copies in circulation and attacker has at least 1.
        uint256 tokenId = 999;
        uint256 quantity = 2;
        // Victim.
        erc1155.mint(seller, tokenId, 1);
        erc1155.mint(attacker, tokenId, 1);

        ////////////////// Setup: auction 1 //////////////////

        IEnglishAuctions.AuctionParameters memory auctionParams1;
        {
            address assetContract = address(erc1155);
            address currency = address(erc20);
            uint256 minimumBidAmount = 1 ether;
            uint256 buyoutBidAmount = 10 ether;
            uint256 quantity = 1;
            uint64 timeBufferInSeconds = 10 seconds;
            uint64 bidBufferBps = 1000;
            uint64 startTimestamp = 0;
            uint64 endTimestamp = 200;
            auctionParams1 = IEnglishAuctions.AuctionParameters(
                assetContract,
                tokenId,
                quantity,
                currency,
                minimumBidAmount,
                buyoutBidAmount,
                timeBufferInSeconds,
                bidBufferBps,
                startTimestamp,
                endTimestamp
            );
        }

        vm.startPrank(seller);

        erc1155.setApprovalForAll(marketplace, true);
        EnglishAuctionsLogic(marketplace).createAuction(auctionParams1);

        assertEq(erc1155.balanceOf(marketplace, tokenId), 1, "Marketplace should have the token.");

        vm.stopPrank();

        ////////////////// Attack: auction the 2nd and steal the 1st token //////////////////

        // 1. Set up auction.
        erc20.mint(attacker, 1);

        vm.startPrank(attacker);

        erc1155.setApprovalForAll(marketplace, true);

        IEnglishAuctions.AuctionParameters memory auctionParams2;
        {
            address assetContract = address(erc1155);
            address currency = address(erc20);
            uint256 minimumBidAmount = 1;
            uint256 buyoutBidAmount = 1;
            uint64 timeBufferInSeconds = 10 seconds;
            uint64 bidBufferBps = 1000;
            uint64 startTimestamp = 0;
            uint64 endTimestamp = 200;
            auctionParams2 = IEnglishAuctions.AuctionParameters(
                assetContract,
                tokenId,
                1,
                currency,
                minimumBidAmount,
                buyoutBidAmount,
                timeBufferInSeconds,
                bidBufferBps,
                startTimestamp,
                endTimestamp
            );
        }
        uint256 auctionId2 = EnglishAuctionsLogic(marketplace).createAuction(auctionParams2);

        assertEq(erc1155.balanceOf(marketplace, tokenId), 2, "Marketplace should have 2 tokens.");

        // 2. Bid and collect back token.
        erc20.increaseAllowance(marketplace, 1);
        // Bid a small amount: 1 wei.
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId2, 1);

        assertEq(erc1155.balanceOf(attacker, tokenId), 1, "Attack should have collected back their token.");

        // Note: Attacker does not collect payout, it sets auction quantity to 0 and prevent further token collections.

        // 3. Fixed: Profit.
        assertEq(erc1155.balanceOf(marketplace, tokenId), 1);

        vm.expectRevert("Marketplace: payout already completed.");
        EnglishAuctionsLogic(marketplace).collectAuctionTokens(auctionId2);

        // assertEq(erc1155.balanceOf(attacker, tokenId), 2, "Attacker should have collected the 2nd token for free.");

        vm.stopPrank();
    }
}

contract IssueC3_MarketplaceEnglishAuctionsTest is BaseTest {
    address private registryDeployer;

    PluginRegistry private pluginRegistry;

    mapping(uint256 => IPlugin.Plugin) private plugins;

    // Target contract
    address public marketplace;

    // Participants
    address public adminDeployer;
    address public marketplaceDeployer;
    address public seller;
    address public buyer;

    function setUp() public override {
        super.setUp();

        adminDeployer = getActor(0);
        marketplaceDeployer = getActor(1);
        seller = getActor(2);
        buyer = getActor(3);
        registryDeployer = getActor(4);

        vm.prank(registryDeployer);
        pluginRegistry = new PluginRegistry(registryDeployer);

        setupMarketplace(adminDeployer, marketplaceDeployer);
    }

    function setupMarketplace(address _adminDeployer, address _marketplaceDeployer) private {
        string[] memory pluginNames = new string[](5);

        // Deploy plugins

        // Plugin: ERC2771Context
        address erc2771Context = address(new MetaTx(forwarders()));

        plugins[0].metadata = IPlugin.PluginMetadata({
            name: "ERC2771Context",
            metadataURI: "ipfs://ERC2771Context",
            implementation: erc2771Context
        });

        plugins[0].functions.push(
            IPlugin.PluginFunction(ERC2771Context.isTrustedForwarder.selector, "isTrustedForwarder(address)")
        );
        pluginNames[0] = plugins[0].metadata.name;

        // Plugin: PermissionsEnumerable
        address permissions = address(new PermissionsEnumerable());

        plugins[1].metadata = IPlugin.PluginMetadata({
            name: "PermissionsEnumerable",
            metadataURI: "ipfs://PermissionsEnumerable",
            implementation: permissions
        });

        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.hasRole.selector, "hasRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.hasRoleWithSwitch.selector, "hasRoleWithSwitch(bytes32,address)")
        );
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.getRoleAdmin.selector, "getRoleAdmin(bytes32)"));
        plugins[1].functions.push(IPlugin.PluginFunction(Permissions.grantRole.selector, "grantRole(bytes32,address)"));
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.revokeRole.selector, "revokeRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(Permissions.renounceRole.selector, "renounceRole(bytes32,address)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMember.selector, "getRoleMember(bytes32,uint256)")
        );
        plugins[1].functions.push(
            IPlugin.PluginFunction(PermissionsEnumerable.getRoleMemberCount.selector, "getRoleMemberCount(bytes32)")
        );
        pluginNames[1] = plugins[1].metadata.name;

        // Plugin: ContractMetadata
        address contractMetadata = address(new ContractMetadataImpl());

        plugins[2].metadata = IPlugin.PluginMetadata({
            name: "ContractMetadata",
            metadataURI: "ipfs://ContractMetadata",
            implementation: contractMetadata
        });

        plugins[2].functions.push(IPlugin.PluginFunction(ContractMetadata.contractURI.selector, "contractURI()"));
        plugins[2].functions.push(
            IPlugin.PluginFunction(ContractMetadata.setContractURI.selector, "setContractURI(string)")
        );
        pluginNames[2] = plugins[2].metadata.name;

        // Plugin: PlatformFee
        address platformFee = address(new PlatformFeeImpl());

        plugins[3].metadata = IPlugin.PluginMetadata({
            name: "PlatformFee",
            metadataURI: "ipfs://PlatformFee",
            implementation: platformFee
        });

        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.getPlatformFeeInfo.selector, "getPlatformFeeInfo()")
        );
        plugins[3].functions.push(
            IPlugin.PluginFunction(PlatformFee.setPlatformFeeInfo.selector, "setPlatformFeeInfo(address,uint256)")
        );
        pluginNames[3] = plugins[3].metadata.name;

        // [1] Index `EnglishAuctions` functions in `Plugin`
        plugins[4].metadata = IPlugin.PluginMetadata({
            name: "EnglishAuctionsLogic",
            metadataURI: "ipfs://direct",
            implementation: address(new EnglishAuctionsLogic(address(weth)))
        });
        pluginNames[4] = plugins[4].metadata.name;

        IPlugin.PluginFunction[] memory pluginFunctions = new IPlugin.PluginFunction[](12);
        pluginFunctions[0] = IPlugin.PluginFunction(EnglishAuctionsLogic.totalAuctions.selector, "totalAuctions()");
        pluginFunctions[1] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.createAuction.selector,
            "createAuction((address,uint256,uint256,address,uint256,uint256,uint64,uint64,uint64,uint64))"
        );
        pluginFunctions[2] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.cancelAuction.selector,
            "cancelAuction(uint256)"
        );
        pluginFunctions[3] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionPayout.selector,
            "collectAuctionPayout(uint256)"
        );
        pluginFunctions[4] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.collectAuctionTokens.selector,
            "collectAuctionTokens(uint256)"
        );
        pluginFunctions[5] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.bidInAuction.selector,
            "bidInAuction(uint256,uint256)"
        );
        pluginFunctions[6] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isNewWinningBid.selector,
            "isNewWinningBid(uint256,uint256)"
        );
        pluginFunctions[7] = IPlugin.PluginFunction(EnglishAuctionsLogic.getAuction.selector, "getAuction(uint256)");
        pluginFunctions[8] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllAuctions.selector,
            "getAllAuctions(uint256,uint256)"
        );
        pluginFunctions[9] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getAllValidAuctions.selector,
            "getAllValidAuctions(uint256,uint256)"
        );
        pluginFunctions[10] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.getWinningBid.selector,
            "getWinningBid(uint256)"
        );
        pluginFunctions[11] = IPlugin.PluginFunction(
            EnglishAuctionsLogic.isAuctionExpired.selector,
            "isAuctionExpired(uint256)"
        );

        for (uint256 i = 0; i < pluginFunctions.length; i++) {
            plugins[4].functions.push(pluginFunctions[i]);
        }

        // [2] Add plugin to registry
        vm.startPrank(registryDeployer);
        pluginRegistry.addPlugin(plugins[0]);
        pluginRegistry.addPlugin(plugins[1]);
        pluginRegistry.addPlugin(plugins[2]);
        pluginRegistry.addPlugin(plugins[3]);
        pluginRegistry.addPlugin(plugins[4]);
        vm.stopPrank();

        // [3] Deploy `MarketplaceV3` implementation
        vm.startPrank(_adminDeployer);
        MarketplaceV3 router = new MarketplaceV3(address(pluginRegistry), pluginNames);
        vm.stopPrank();

        // [4] Deploy proxy pointing to `MarkeptlaceV3` implementation
        vm.prank(_marketplaceDeployer);
        marketplace = address(
            new TWProxy(
                address(router),
                abi.encodeCall(
                    MarketplaceV3.initialize,
                    (_marketplaceDeployer, "", new address[](0), _marketplaceDeployer, 0)
                )
            )
        );

        // [5] Setup roles for seller and assets
        vm.startPrank(_marketplaceDeployer);
        Permissions(marketplace).revokeRole(keccak256("ASSET_ROLE"), address(0));
        Permissions(marketplace).revokeRole(keccak256("LISTER_ROLE"), address(0));
        Permissions(marketplace).grantRole(keccak256("LISTER_ROLE"), seller);
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc721));
        Permissions(marketplace).grantRole(keccak256("ASSET_ROLE"), address(erc1155));

        vm.stopPrank();

        vm.label(address(router), "MarketplaceV3_Impl");
        vm.label(marketplace, "Marketplace");
        vm.label(seller, "Seller");
        vm.label(buyer, "Buyer");
        vm.label(address(erc721), "ERC721_Token");
        vm.label(address(erc1155), "ERC1155_Token");
    }

    function _setupERC1155BalanceForSeller(address _seller, uint256 _numOfTokens) private {
        erc1155.mint(_seller, 0, _numOfTokens);
    }

    function _setup_newAuction_1155() private returns (uint256 auctionId) {
        // Sample auction parameters.
        address assetContract = address(erc1155);
        uint256 tokenId = 0;
        uint256 quantity = 2;
        address currency = address(erc20);
        uint256 minimumBidAmount = 1 ether;
        uint256 buyoutBidAmount = 10 ether;
        uint64 timeBufferInSeconds = 10 seconds;
        uint64 bidBufferBps = 1000;
        uint64 startTimestamp = 100;
        uint64 endTimestamp = 200;

        // Mint the erc1155 tokens to seller. These tokens will be auctioned.
        _setupERC1155BalanceForSeller(seller, 2);

        // Approve Marketplace to transfer token.
        vm.prank(seller);
        erc1155.setApprovalForAll(marketplace, true);

        // Auction tokens.
        IEnglishAuctions.AuctionParameters memory auctionParams = IEnglishAuctions.AuctionParameters(
            assetContract,
            tokenId,
            quantity,
            currency,
            minimumBidAmount,
            buyoutBidAmount,
            timeBufferInSeconds,
            bidBufferBps,
            startTimestamp,
            endTimestamp
        );

        vm.prank(seller);
        auctionId = EnglishAuctionsLogic(marketplace).createAuction(auctionParams);
    }

    function test_state_collectAuctionTokens_afterAuctionPayout() public {
        uint256 auctionId = _setup_newAuction_1155();
        IEnglishAuctions.Auction memory existingAuction = EnglishAuctionsLogic(marketplace).getAuction(auctionId);

        // Verify existing auction at `auctionId`
        assertEq(existingAuction.assetContract, address(erc1155));

        vm.warp(existingAuction.startTimestamp);

        // place bid
        erc20.mint(buyer, 5 ether);
        vm.startPrank(buyer);
        erc20.approve(marketplace, 5 ether);
        EnglishAuctionsLogic(marketplace).bidInAuction(auctionId, 5 ether);
        vm.stopPrank();

        (address bidder, address currency, uint256 bidAmount) = EnglishAuctionsLogic(marketplace).getWinningBid(
            auctionId
        );

        // Seller is owner of token.
        assertEq(erc20.balanceOf(marketplace), 5 ether);
        assertEq(erc20.balanceOf(buyer), 0);
        assertEq(buyer, bidder);
        assertEq(currency, address(erc20));
        assertEq(bidAmount, 5 ether);

        vm.warp(existingAuction.endTimestamp);

        // collect auction payout
        vm.prank(seller);
        EnglishAuctionsLogic(marketplace).collectAuctionPayout(auctionId);

        // collect buyer token
        vm.prank(buyer);
        EnglishAuctionsLogic(marketplace).collectAuctionTokens(auctionId);

        // token is NOT stuck in the marketplace
        assertEq(erc1155.balanceOf(marketplace, 0), 0);
        assertEq(erc1155.balanceOf(buyer, 0), 2);
    }
}
