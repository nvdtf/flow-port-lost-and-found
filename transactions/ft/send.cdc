import "FungibleToken"
import "FungibleTokenMetadataViews"
import "LostAndFound"
import "FlowToken"

// Send fungible tokens to the given recipient's LostAndFound inbox
transaction(contractAddress: Address, contractName: String, amount: UFix64, recipient: Address, memo: String) {

    let sentVault: @{FungibleToken.Vault}
    let flowProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    let flowReceiver: Capability<&FlowToken.Vault>

    prepare(signer: auth(BorrowValue, Storage, Capabilities) &Account) {

        // Find the fungible token vault data from the deployed contract
        let resolverRef = getAccount(contractAddress)
            .contracts.borrow<&{FungibleToken}>(name: contractName)
            ?? panic("Could not borrow a reference to the fungible token contract")

        let ftVaultData = resolverRef.resolveContractView(
            resourceType: nil,
            viewType: Type<FungibleTokenMetadataViews.FTVaultData>()
        ) as! FungibleTokenMetadataViews.FTVaultData?
            ?? panic("Could not resolve the FTVaultData view for the given Fungible token contract")

        // Get a reference to the signer's stored vault
        let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &{FungibleToken.Vault}>(from: ftVaultData.storagePath)
            ?? panic("The signer does not store an FungibleToken.Vault object at the path "
                    .concat(ftVaultData.storagePath.toString())
                    .concat(". The signer must initialize their account with this vault first!"))

        // Withdraw tokens from the signer's stored vault
        self.sentVault <- vaultRef.withdraw(amount: amount)

        // Provide needed storage tokens
        var provider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>? = nil
        signer.capabilities.storage.forEachController(forPath: /storage/flowTokenVault, fun(c: &StorageCapabilityController): Bool {
            if c.borrowType == Type<auth(FungibleToken.Withdraw) &FlowToken.Vault>() {
                provider = c.capability as! Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
            }

            return true
        })

        if provider == nil {
            provider = signer.capabilities.storage.issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(/storage/flowTokenVault)
        }

        self.flowProvider = provider!
        self.flowReceiver = signer.capabilities.get<&FlowToken.Vault>(/public/flowTokenReceiver)!
    }

    execute {

        // Estimate the deposit
        let depositEstimate <- LostAndFound.estimateDeposit(redeemer: recipient, item: <-self.sentVault, memo: memo, display: nil)
        let storageFee <- self.flowProvider.borrow()!.withdraw(amount: depositEstimate.storageFee)
        let r <- depositEstimate.withdraw()

        // Send to LostAndFound
        LostAndFound.deposit(
            redeemer: recipient,
            item: <-r,
            memo: memo,
            display: nil,
            storagePayment: &storageFee as auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
            flowTokenRepayment: self.flowReceiver
        )

        // Return any remaining storage fees in this vault
        self.flowReceiver.borrow()!.deposit(from: <-storageFee)
        destroy depositEstimate
    }

}