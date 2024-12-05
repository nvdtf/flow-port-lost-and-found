import "NonFungibleToken"
import "LostAndFound"

access(all) struct NonFungibleTokenTicket {
    access(all) let memo: String?
    access(all) let redeemer: Address
    access(all) let type: Type
    access(all) let typeIdentifier: String
    access(all) let displayName : String?
    access(all) let displayDescription : String?
    access(all) let displayThumbnail : String?
    access(all) let nftID : UInt64
    access(all) let ticketID : UInt64

    init(_ ticket: &LostAndFound.Ticket, ticketID: UInt64) {
        self.memo = ticket.memo
        self.redeemer = ticket.redeemer
        self.type = ticket.type
        self.typeIdentifier = ticket.type.identifier
        self.displayName = ticket.display?.name
        self.displayDescription = ticket.display?.description
        self.displayThumbnail = ticket.display?.thumbnail?.uri()
        self.nftID = ticket.getNonFungibleTokenID()!
        self.ticketID = ticketID
    }
}

// returns the current NFT tickets in the given redeemer's inbox
access(all) fun main(addr: Address): [NonFungibleTokenTicket] {
    let tickets: [NonFungibleTokenTicket] = []

    let shelf = LostAndFound.borrowShelfManager().borrowShelf(redeemer: addr)
    if shelf == nil {
        return []
    }

    let types = shelf!.getRedeemableTypes()

    for type in types {
        if type.isSubtype(of: Type<@{NonFungibleToken.NFT}>()) {

            let bin = shelf!.borrowBin(type: type)!
            let ids = bin.getTicketIDs()

            for id in ids {
                let ticket = bin.borrowTicket(id: id)!
                if !ticket.redeemed {
                    tickets.append(NonFungibleTokenTicket(ticket, ticketID: id))
                }
            }

        }

    }
    return tickets
}