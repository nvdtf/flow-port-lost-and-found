import "NonFungibleToken"
import "MetadataViews"

import "LostAndFound"

// Redeems a non-fungible token ticket from the given redeemer's inbox
// also initializes the redeemer's collection if it is not initialized
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

        // Check if the account is initialized
        if acct.storage.borrow<&AnyResource>(from: collectionData.storagePath) == nil {

            // Create a new empty collection if not initialized
            let emptyCollection <- collectionData.createEmptyCollection()
            acct.storage.save(<-emptyCollection, to: collectionData.storagePath)
            let collectionCap = acct.capabilities.storage.issue<&{NonFungibleToken.Collection}>(
                    collectionData.storagePath
                )
            acct.capabilities.publish(collectionCap, at: collectionData.publicPath)
        }

        // Redeem the ticket
        let cap = acct.capabilities.get<&{NonFungibleToken.CollectionPublic}>(collectionData.publicPath)
        let manager = LostAndFound.borrowShelfManager()
        let shelf = manager.borrowShelf(redeemer: acct.address)!
        let typeIdentifier = "A.".concat(contractAddress.toString().slice(from: 2, upTo: contractAddress.toString().length)).concat(".").concat(contractName).concat(".NFT")
        let ticketType = CompositeType(typeIdentifier) ?? panic("Could not create CompositeType for ".concat(typeIdentifier))
        shelf.redeem(type: ticketType, ticketID: ticketID, receiver: cap)
    }
}
