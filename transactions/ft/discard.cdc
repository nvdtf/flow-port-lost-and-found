import "FungibleToken"
import "FungibleTokenMetadataViews"
import "Burner"

import "LostAndFound"

// Discards a fungible token ticket from the given redeemer's inbox
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

        // To discard a ticket, we need to first redeem it and then discard it
        // so the account must have an initialized collection
        var initialized = false
        if acct.storage.borrow<&AnyResource>(from: ftVaultData.storagePath) == nil {

            // Create a new vault if not initialized
            let emptyVault <-ftVaultData.createEmptyVault()
            acct.storage.save(<-emptyVault, to: ftVaultData.storagePath)
            let vaultCap = acct.capabilities.storage.issue<&{FungibleToken.Vault}>(ftVaultData.storagePath)
            acct.capabilities.publish(vaultCap, at: ftVaultData.metadataPath)
            let receiverCap = acct.capabilities.storage.issue<&{FungibleToken.Receiver}>(ftVaultData.storagePath)
            acct.capabilities.publish(receiverCap, at: ftVaultData.receiverPath)

            initialized = true
        }

        let cap = acct.capabilities.get<&{FungibleToken.Receiver}>(ftVaultData.receiverPath)
        let manager = LostAndFound.borrowShelfManager()
        let shelf = manager.borrowShelf(redeemer: acct.address)!
        let typeIdentifier = "A.".concat(contractAddress.toString().slice(from: 2, upTo: contractAddress.toString().length)).concat(".").concat(contractName).concat(".Vault")
        let ticketType = CompositeType(typeIdentifier) ?? panic("Could not create CompositeType for ".concat(typeIdentifier))
        let bin = shelf.borrowBin(type: ticketType)!
        let ticket = bin.borrowTicket(id: ticketID)!
        let balance = ticket.getFungibleTokenBalance()!

        shelf.redeem(type: ticketType, ticketID: ticketID, receiver: cap)

        // Discard and destroy
        let sourceVault = acct.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(
                from: ftVaultData.storagePath)
			?? panic("The signer does not store a Vault object at the path "
                .concat(ftVaultData.storagePath.toString()))

        let burnVault <- sourceVault.withdraw(amount: balance) as! @{FungibleToken.Vault}
        Burner.burn(<-burnVault)

        // If we initialized the collection, uninitialize it
        if initialized {
            let r <- acct.storage.load<@AnyResource>(from: ftVaultData.storagePath)
            destroy r
            acct.capabilities.unpublish(ftVaultData.receiverPath)
            acct.capabilities.unpublish(ftVaultData.metadataPath)
        }

    }
}