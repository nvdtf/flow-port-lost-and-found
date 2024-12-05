import "NonFungibleToken"
import "MetadataViews"
import "LostAndFound"

access(all) struct Result {
    access(all) let CanReceive: Bool
    access(all) let StorageCost: UFix64
    init(canReceive: Bool, storageCost: UFix64) {
        self.CanReceive = canReceive
        self.StorageCost = storageCost
    }
}

// Checks if the receiver can receive the given NFT from the sender. If the receiver cannot receive the NFT,
// the script will estimate the cost of depositing the NFT into the LostAndFound contract.
access(all) fun main(sender: Address, contractAddress: Address, contractName: String, nftID: UInt64, receiver: Address): Result {

    var canReceive = true
    var storageCost = 0.0

    // find NFT collection data from deployed contract
    let resolverRef = getAccount(contractAddress)
        .contracts.borrow<&{NonFungibleToken}>(name: contractName)
        ?? panic("Could not borrow a reference to the non-fungible token contract")

    let collectionData = resolverRef.resolveContractView(
            resourceType: nil,
            viewType: Type<MetadataViews.NFTCollectionData>()
        ) as! MetadataViews.NFTCollectionData?
        ?? panic("Could not resolve the NFTCollectionData view for the given non-fungible token contract")

    // check receiver can receive the NFT
    let receiverAccount = getAccount(receiver)
    let collectionRef = receiverAccount.capabilities.borrow<&{NonFungibleToken.Collection}>(
            collectionData.publicPath
        )

    if collectionRef == nil || !collectionRef!.isInstance(Type<@{NonFungibleToken.Collection}>()){

        canReceive = false

        // if cannot receive, estimate the cost of depositing the NFT into the LostAndFound contract
        let senderAccount = getAuthAccount<auth(Storage) &Account>(sender)
        let c = senderAccount.storage.borrow<auth(NonFungibleToken.Withdraw) &{NonFungibleToken.Collection}>(from: collectionData.storagePath)
            ?? panic("collection not found")
        let nft <- c.withdraw(withdrawID: nftID)
        let estimate <- LostAndFound.estimateDeposit(redeemer: receiver, item: <-nft, memo: nil, display: nil)
        let item <- estimate.withdraw()
        c!.deposit(token: <- (item as! @{NonFungibleToken.NFT}))
        storageCost = estimate.storageFee * 1.2
        destroy estimate
    }

    return Result(
        canReceive: canReceive,
        storageCost: storageCost,
    )
}