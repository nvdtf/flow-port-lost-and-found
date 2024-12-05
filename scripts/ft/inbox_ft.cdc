import "FungibleToken"
import "LostAndFound"

access(all) struct FungibleTokenTicket {
    access(all) let memo: String?
    access(all) let redeemer: Address
    access(all) let type: Type
    access(all) let typeIdentifier: String
    access(all) let balance: UFix64
    access(all) let ticketID : UInt64

    init(_ ticket: &LostAndFound.Ticket, ticketID: UInt64) {
        self.memo = ticket.memo
        self.redeemer = ticket.redeemer
        self.type = ticket.type
        self.typeIdentifier = ticket.type.identifier
        self.balance = ticket.getFungibleTokenBalance()!
        self.ticketID = ticketID
    }
}

// returns the current fungible token tickets in the given redeemer's inbox
access(all) fun main(addr: Address): [FungibleTokenTicket] {

    let tickets: [FungibleTokenTicket] = []

    let shelf = LostAndFound.borrowShelfManager().borrowShelf(redeemer: addr)
    if shelf == nil {
        return []
    }

    let types = shelf!.getRedeemableTypes()

    for type in types {
        if type.isSubtype(of: Type<@{FungibleToken.Vault}>()) {

            let bin = shelf!.borrowBin(type: type)!
            let ids = bin.getTicketIDs()

            for id in ids {
                let ticket = bin.borrowTicket(id: id)!
                if !ticket.redeemed {
                    tickets.append(FungibleTokenTicket(ticket, ticketID: id))
                }
            }

        }

    }
    return tickets
}