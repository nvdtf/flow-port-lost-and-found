import "FungibleToken"
import "FungibleTokenMetadataViews"
import "LostAndFound"

access(all) struct Result {
    access(all) let CanReceive: Bool
    access(all) let StorageCost: UFix64
    init(canReceive: Bool, storageCost: UFix64) {
        self.CanReceive = canReceive
        self.StorageCost = storageCost
    }
}

// Checks if the receiver can receive the given amount of tokens from the sender. If the receiver cannot receive the tokens,
// the script will estimate the cost of depositing tokens into the LostAndFound contract.
access(all) fun main(sender: Address, contractAddress: Address, contractName: String, amount: UFix64, receiver: Address): Result {

    var canReceive = true
    var storageCost = 0.0

    // find FT vault data from deployed contract
    let resolverRef = getAccount(contractAddress)
            .contracts.borrow<&{FungibleToken}>(name: contractName)
            ?? panic("Could not borrow a reference to the fungible token contract")

    let ftVaultData = resolverRef.resolveContractView(
        resourceType: nil,
        viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
    ) as! FungibleTokenMetadataViews.FTVaultData?
        ?? panic("Could not resolve the FTVaultData view for the given Fungible token contract")

    // check receiver has a vault
    let receiverAccount = getAccount(receiver)
    let collectionRef = receiverAccount.capabilities.borrow<&{FungibleToken.Vault}>(
            ftVaultData.receiverPath
        )
    if collectionRef == nil || !collectionRef!.isInstance(Type<@{FungibleToken.Vault}>()){

        canReceive = false

        // if cannot receive, estimate the cost of depositing tokens into the LostAndFound contract
        let senderAccount = getAuthAccount<auth(Storage) &Account>(sender)
        let c = senderAccount.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: ftVaultData.storagePath)
            ?? panic("collection not found")
        let ft <- c.withdraw(amount: amount)
        let estimate <- LostAndFound.estimateDeposit(redeemer: receiver, item: <-ft, memo: nil, display: nil)
        let item <- estimate.withdraw()
        c!.deposit(from: <- (item as! @{FungibleToken.Vault}))
        storageCost = estimate.storageFee * 1.2
        destroy estimate
    }

    return Result(
        canReceive: canReceive,
        storageCost: storageCost,
    )
}