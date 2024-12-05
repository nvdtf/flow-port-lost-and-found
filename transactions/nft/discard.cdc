import "NonFungibleToken"
import "MetadataViews"
import "Burner"

import "LostAndFound"

// Discards a non-fungible token ticket from the given redeemer's inbox
transaction(contractAddress: Address, contractName: String, ticketID: UInt64) {
    prepare(acct: auth(Storage, Capabilities) &Account) {

        // Find the NFT collection data from the deployed contract
        let resolverRef = getAccount(contractAddress)
            .contracts.borrow<&{NonFungibleToken}>(name: contractName)
            ?? panic("Could not borrow a reference to the non-fungible token contract")

        let collectionData = resolverRef.resolveContractView(
                resourceType: nil,
                viewType: Type<MetadataViews.NFTCollectionData>()
            ) as! MetadataViews.NFTCollectionData?
            ?? panic("Could not resolve the NFTCollectionData view for the given non-fungible token contract")

        // To discard a ticket, we need to first redeem it and then discard it
        // so the account must have an initialized collection
        var initialized = false
        if acct.storage.borrow<&AnyResource>(from: collectionData.storagePath) == nil {

            // Create a new empty collection if not initialized
            let emptyCollection <- collectionData.createEmptyCollection()
            acct.storage.save(<-emptyCollection, to: collectionData.storagePath)
            let collectionCap = acct.capabilities.storage.issue<&{NonFungibleToken.Collection}>(
                    collectionData.storagePath
                )
            acct.capabilities.publish(collectionCap, at: collectionData.publicPath)
            initialized = true
        }

        let cap = acct.capabilities.get<&{NonFungibleToken.CollectionPublic}>(collectionData.publicPath)
        let manager = LostAndFound.borrowShelfManager()
        let shelf = manager.borrowShelf(redeemer: acct.address)!
        let typeIdentifier = "A.".concat(contractAddress.toString().slice(from: 2, upTo: contractAddress.toString().length)).concat(".").concat(contractName).concat(".NFT")
        let ticketType = CompositeType(typeIdentifier) ?? panic("Could not create CompositeType for ".concat(typeIdentifier))
        let bin = shelf.borrowBin(type: ticketType)!
        let ticket = bin.borrowTicket(id: ticketID)!
        let nftID = ticket.getNonFungibleTokenID()!

        shelf.redeem(type: ticketType, ticketID: ticketID, receiver: cap)

        // discard and destroy
        let collectionRef = acct.storage.borrow<auth(NonFungibleToken.Withdraw) &{NonFungibleToken.Collection}>(
                from: collectionData.storagePath
            ) ?? panic("The signer does not store an ExampleNFT.Collection object at the path "
                        .concat(collectionData.storagePath.toString()))

        let nft <- collectionRef.withdraw(withdrawID: nftID)
        Burner.burn(<-nft)

        // If we initialized the collection, uninitialize it
        if initialized {
            let r <- acct.storage.load<@AnyResource>(from: collectionData.storagePath)
            destroy r
            acct.capabilities.unpublish(collectionData.publicPath)
        }

    }
}