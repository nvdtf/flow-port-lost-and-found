import "LostAndFound"
import "LostAndFoundHelper"

// returns the number of tickets in the given redeemer's inbox
access(all) fun main(addr: Address): UInt16 {
    let tickets = LostAndFound.borrowAllTickets(addr: addr)
    return UInt16(tickets.length)
}