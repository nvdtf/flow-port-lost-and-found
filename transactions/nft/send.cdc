import "NonFungibleToken"
import "MetadataViews"
import "ViewResolver"
import "FungibleToken"
import "LostAndFound"
import "FlowToken"

// Send a non-fungible token to the given recipient's LostAndFound inbox
transaction(contractAddress: Address, contractName: String, nftID: UInt64, recipient: Address, memo: String) {

    let withdrawRef: auth(NonFungibleToken.Withdraw) &{NonFungibleToken.Collection}
    let flowProvider: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    let flowReceiver: Capability<&FlowToken.Vault>

    prepare(signer: auth(BorrowValue, Storage, Capabilities) &Account) {

        // Find the NFT collection data from the deployed contract
        let viewResolver = getAccount(contractAddress).contracts.borrow<&{ViewResolver}>(name: contractName)
            ?? panic("Could not borrow ViewResolver reference to the contract. Make sure the provided contract name ("
                      .concat(contractName).concat(") and address (").concat(contractAddress.toString()).concat(") are correct!"))

        let collectionData = viewResolver.resolveContractView(resourceType: nil, viewType: Type<MetadataViews.NFTCollectionData>()) as! MetadataViews.NFTCollectionData?
            ?? panic("Could not resolve NFTCollectionData view. The ".concat(contractName).concat(" contract needs to implement the NFTCollectionData Metadata view in order to execute this transaction"))

        // Borrow a reference to the signer's NFT collection
        self.withdrawRef = signer.storage.borrow<auth(NonFungibleToken.Withdraw) &{NonFungibleToken.Collection}>(
                from: collectionData.storagePath
            ) ?? panic("The signer does not store a "
                        .concat(contractName)
                        .concat(".Collection object at the path ")
                        .concat(collectionData.storagePath.toString())
                        .concat("The signer must initialize their account with this collection first!"))

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
        let nft <- self.withdrawRef.withdraw(withdrawID: nftID)
        let display = nft.resolveView(Type<MetadataViews.Display>()) as! MetadataViews.Display?
        let depositEstimate <- LostAndFound.estimateDeposit(redeemer: recipient, item: <-nft, memo: memo, display: display)
        let storageFee <- self.flowProvider.borrow()!.withdraw(amount: depositEstimate.storageFee)
        let r <- depositEstimate.withdraw()

        // Send to LostAndFound
        LostAndFound.deposit(
            redeemer: recipient,
            item: <-r,
            memo: memo,
            display: display,
            storagePayment: &storageFee as auth(FungibleToken.Withdraw) &{FungibleToken.Vault},
            flowTokenRepayment: self.flowReceiver
        )

        // Return any remaining storage fees in this vault
        self.flowReceiver.borrow()!.deposit(from: <-storageFee)
        destroy depositEstimate
    }

}