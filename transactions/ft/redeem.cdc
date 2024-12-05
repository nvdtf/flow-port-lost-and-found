import "FungibleToken"
import "FungibleTokenMetadataViews"

import "LostAndFound"

// Redeems a fungible token ticket from the given redeemer's inbox
// also initializes the redeemer's vault if it is not initialized
transaction(contractAddress: Address, contractName: String, ticketID: UInt64) {
    prepare(acct: auth(Storage, Capabilities) &Account) {

        // Find the fungible token vault data from the deployed contract
        let resolverRef = getAccount(contractAddress)
            .contracts.borrow<&{FungibleToken}>(name: contractName)
            ?? panic("Could not borrow a reference to the fungible token contract")

        let ftVaultData = resolverRef.resolveContractView(
            resourceType: nil,
            viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
        ) as! FungibleTokenMetadataViews.FTVaultData?
            ?? panic("Could not resolve the FTVaultData view for the given Fungible token contract")

        // Check if the account is initialized
        if acct.storage.borrow<&AnyResource>(from: ftVaultData.storagePath) == nil {

            // Create a new vault if not initialized
            let emptyVault <-ftVaultData.createEmptyVault()
            acct.storage.save(<-emptyVault, to: ftVaultData.storagePath)
            let vaultCap = acct.capabilities.storage.issue<&{FungibleToken.Vault}>(ftVaultData.storagePath)
            acct.capabilities.publish(vaultCap, at: ftVaultData.metadataPath)
            let receiverCap = acct.capabilities.storage.issue<&{FungibleToken.Receiver}>(ftVaultData.storagePath)
            acct.capabilities.publish(receiverCap, at: ftVaultData.receiverPath)

        }

        // Redeem the ticket
        let cap = acct.capabilities.get<&{FungibleToken.Receiver}>(ftVaultData.receiverPath)
        let manager = LostAndFound.borrowShelfManager()
        let shelf = manager.borrowShelf(redeemer: acct.address)!
        let typeIdentifier = "A.".concat(contractAddress.toString().slice(from: 2, upTo: contractAddress.toString().length)).concat(".").concat(contractName).concat(".Vault")
        let ticketType = CompositeType(typeIdentifier) ?? panic("Could not create CompositeType for ".concat(typeIdentifier))
        shelf.redeem(type: ticketType, ticketID: ticketID, receiver: cap)
    }
}
